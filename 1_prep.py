# Copyright 2017 Province of British Columbia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import csv
from datetime import date
from functools import partial
import logging
import multiprocessing
import os
from urllib.parse import urlparse
import subprocess
import yaml

import click

import pgdata


with open("config.yml", "r") as ymlfile:
    CONFIG = yaml.load(ymlfile)

HELP = {
    "csv": "Path to csv that lists all input data sources",
    "alias": "The 'alias' key identifing the source of interest, from source csv",
    "out_file": "Output geopackage name",
    "out_format": "Output format. Default GPKG (Geopackage)",
}

logging.basicConfig(level=logging.INFO)


def info(*strings):
    logging.info(" ".join(strings))


def error(*strings):
    logging.error(" ".join(strings))


def make_sure_path_exists(path):
    """
    Make directories in path if they do not exist.
    Modified from http://stackoverflow.com/a/5032238/1377021
    """
    try:
        os.makedirs(path)
        return path
    except:
        pass


def get_250k_tiles(db):
    sql = """SELECT DISTINCT substring({c} from 1 for 4) as tile
             FROM tiles_20k
          """.format(
        c=CONFIG["tile_column"]
    )
    return [t[0] for t in db.query(sql)]


def read_csv(path):
    """Return list of dicts from file, sorted by 'priority' column
    """
    source_list = [source for source in csv.DictReader(open(path, "r"))]
    # convert priority value to integer
    for source in source_list:
        source.update(
            (k, int(v)) for k, v in source.items() if k == "priority" and v != ""
        )
    return sorted(source_list, key=lambda k: k["priority"])


def tiled_sql_sfcgal(sql, tile):
    """Create an sfcgal enabled connection and execute query for specified tile
    """
    db = pgdata.connect(CONFIG["db_url"], schema="public")
    db.execute("SET postgis.backend = sfcgal")
    db.execute(sql, (tile,))


def tiled_sql_geos(sql, tile):
    """Create an sfcgal enabled connection and execute query for specified tile
    """
    db = pgdata.connect(CONFIG["db_url"], schema="public")
    db.execute("SET postgis.backend = geos")
    db.execute(sql, (tile,))


def add_meta_columns(db, source):
    """ Add and populate required columns: bcgw_extraction_date, bcgw_source
    """
    alias = source["alias"]
    info("adding bcgw source and extraction date columns")
    for col in ["bcgw_source", "bcgw_extraction_date"]:
        sql = """ALTER TABLE {t} ADD COLUMN IF NOT EXISTS {c} text
              """.format(
            t=alias, c=col
        )
        db.execute(sql)
    sql = """UPDATE {t} SET {c1} = %s, {c2} = %s
          """.format(
        t=alias, c1="bcgw_source", c2="bcgw_extraction_date"
    )
    db.execute(sql, (source["source_table"], date.today().isoformat()))


def tile(source, n_processes):
    """Tile input road table
    """
    alias = source["alias"]
    db = pgdata.connect(CONFIG["db_url"], schema="public")

    # move input table to '_src'
    if alias + "_src" not in db.tables:
        sql = "ALTER TABLE {t} RENAME TO {t}_src".format(t=alias)
        db.execute(sql)

    # get a list of tiles present in the data
    # (this takes a little while, so keep the result on hand)
    if alias + "_tiles" not in db.tables:
        info(alias + ": generating list of tiles")
        sql = """CREATE TABLE {out} AS
                 SELECT a.map_tile
                 FROM tiles_20k a
                 INNER JOIN {src} b ON ST_Intersects(a.geom, b.geom)
                 ORDER BY a.map_tile""".format(
            src=alias + "_src", out=alias + "_tiles"
        )
        db.execute(sql)
    tiles = [t for t in db[alias + "_tiles"].distinct("map_tile")]

    # create empty output table
    db[alias].drop()
    fields = source["primary_key"] + "," + source["fields"].lower()
    db.execute(
        """CREATE TABLE {t} AS
                  SELECT {f},
                  ''::text as map_tile,
                  ST_Multi(geom) as geom
                  FROM {src}
                  LIMIT 0
               """.format(
            t=alias, f=fields, src=alias + "_src"
        )
    )

    lookup = {"src_table": alias + "_src", "out_table": alias, "fields": fields}
    sql = db.build_query(db.queries["tile_roads"], lookup)

    # tile, clean
    info(alias + ": tiling and cleaning")
    func = partial(tiled_sql_geos, sql)
    pool = multiprocessing.Pool(processes=n_processes)
    results_iter = pool.imap_unordered(func, tiles)
    with click.progressbar(results_iter, length=len(tiles)) as bar:
        for _ in bar:
            pass
    pool.close()
    pool.join()


def roadpoly2line(source, n_processes):
    """Translate road polygon boundaries into road-like lines
    """
    alias = source["alias"]
    db = pgdata.connect(CONFIG["db_url"], schema="public")

    # move input table to '_src'
    if alias + "_src" not in db.tables:
        sql = "ALTER TABLE {t} RENAME TO {t}_src".format(t=alias)
        db.execute(sql)

    # repair geom and dump to singlepart
    # Note that we do not bother to keep any columns from source table
    if alias + "_tmp" not in db.tables:
        info(alias + ": creating _tmp table with repaired geoms")
        sql = """CREATE TABLE {t}_tmp AS
            SELECT
              (ST_Dump(ST_Safe_Repair((ST_Dump(geom)).geom))).geom as geom
            FROM {t}_src""".format(
            t=alias
        )
        db.execute(sql)

    # get a list of tiles present in the data
    # (this takes a little while, write to table)
    if alias + "_tiles" not in db.tables:
        info(alias + ": generating list of tiles")
        sql = """CREATE TABLE {out} AS
                 SELECT DISTINCT a.map_tile
                 FROM tiles_20k a
                 INNER JOIN {src} b ON ST_Intersects(a.geom, b.geom)
                 ORDER BY a.map_tile""".format(
            src=alias + "_tmp", out=alias + "_tiles"
        )
        db.execute(sql)

    tiles = [t for t in db[alias + "_tiles"].distinct("map_tile")]

    # create tiled/cleaned layer
    if alias + "_cleaned" not in db.tables:
        db.execute(
            """CREATE TABLE {t}
                    ({t}_id SERIAL PRIMARY KEY,
                     map_tile text,
                     geom geometry)""".format(
                t=alias + "_cleaned"
            )
        )

        lookup = {"src_table": alias + "_tmp", "out_table": alias + "_cleaned"}
        sql = db.build_query(db.queries["tile_roads_poly"], lookup)

        # tile and clean using GEOS backend
        info(alias + ": tiling and cleaning")
        func = partial(tiled_sql_geos, sql)
        pool = multiprocessing.Pool(processes=n_processes)
        results_iter = pool.imap_unordered(func, tiles)
        with click.progressbar(results_iter, length=len(tiles)) as bar:
            for _ in bar:
                pass
        pool.close()
        pool.join()

    # create output layer
    db.execute(
        """CREATE TABLE {t}
                    ({t}_id SERIAL PRIMARY KEY,
                     map_tile text,
                     geom geometry)""".format(
            t=alias
        )
    )

    lookup = {"src_table": alias + "_cleaned", "out_table": alias}
    sql = db.build_query(db.queries["roadpoly2line"], lookup)
    # process poly2line using SFCGAL backend
    info(alias + ": generating road lines from polygons")
    func = partial(tiled_sql_sfcgal, sql)
    pool = multiprocessing.Pool(processes=n_processes)
    results_iter = pool.imap_unordered(func, tiles)
    with click.progressbar(results_iter, length=len(tiles)) as bar:
        for _ in bar:
            pass
    pool.close()
    pool.join()


@click.group()
def cli():
    pass


@cli.command()
def create_db():
    """Create a fresh database / load extensions / create functions
    """
    pgdata.create_db(CONFIG["db_url"])
    db = pgdata.connect(CONFIG["db_url"])
    db.execute("CREATE EXTENSION postgis")
    db.execute("CREATE EXTENSION postgis_sfcgal")
    db.execute(db.queries["ST_Safe_Repair"])
    db.execute(db.queries["ST_Safe_Intersection"])
    db.execute(db.queries["ST_Safe_Difference"])
    db.execute(db.queries["ST_Filter_Rings"])


@cli.command()
@click.option(
    "--source_csv",
    "-s",
    default=CONFIG["source_csv"],
    type=click.Path(exists=True),
    help=HELP["csv"],
)
@click.option("--alias", "-a", help=HELP["alias"])
@click.option("--force_refresh", is_flag=True, default=False, help="Force re-download")
def load(source_csv, alias, force_refresh):
    """Download data, load to postgres
    """
    db = pgdata.connect(CONFIG["db_url"], schema="public")
    sources = read_csv(source_csv)
    # filter sources based on optional provided alias
    if alias:
        sources = [s for s in sources if s["alias"] == alias]

    # process sources where automated downloads are avaiable
    for source in sources:
        if force_refresh:
            db[source["alias"]].drop()
        # manual downloads:
        # - must be placed in dl_path folder
        # - file must be .gdb with same name as alias specified in sources csv
        if source["alias"] not in db.tables:
            # if source['manual_download'] == 'T':

            #    info('Loading %s from manual download' % source['alias'])
            #    db.ogr2pg(
            #        os.path.join(dl_path, source['alias']+'.gdb'),
            #        in_layer=source['layer_in_file'],
            #        out_layer=source['alias'],
            #        sql=source['query']
            #    )
            # else:
            info("Downloading %s" % source["alias"])
            # Use bcdata bc2pg (ogr2ogr wrapper) to load the data to postgres
            command = [
                "bcdata bc2pg {}".format(source["source_table"]),
                "--schema public",
                "--table {}".format(source["alias"]),
                "--db_url {}".format(CONFIG["db_url"]),
                "--sortby {}".format(source["primary_key"]),
            ]
            if source["query"]:
                command.append('--query "{}"'.format(source["query"]))
            subprocess.call(" ".join(command), shell=True)


@cli.command()
@click.option(
    "--source_csv",
    "-s",
    default=CONFIG["source_csv"],
    type=click.Path(exists=True),
    help=HELP["csv"],
)
@click.option("--alias", "-a", help=HELP["alias"])
@click.option(
    "--n_processes",
    "-p",
    default=multiprocessing.cpu_count() - 1,
    help="Number of parallel processing threads to utilize",
)
def preprocess(source_csv, alias, n_processes):
    """Prepare input road data
    """
    db = pgdata.connect(CONFIG["db_url"], schema="public")
    sources = read_csv(source_csv)
    if alias:
        sources = [s for s in sources if s["alias"] == alias]
    # find sources noted for preprocessing
    sources = [s for s in sources if s["preprocess_operation"]]
    for source in sources:
        info("Preprocessing %s" % source["alias"])
        # call noted preprocessing function
        function = source["preprocess_operation"]
        globals()[function](source, n_processes)
        # add required extraction date and source layer columns
        add_meta_columns(db, source)
        # dump data to .gdb for subsequent arcpy processing
        # (query layers pointing to postgres in arcgis should work fine, but
        # this allows us to use existing code)
        db.pg2ogr(
            "SELECT * FROM {t}".format(t=source["alias"]),
            "FileGDB",
            os.path.join(CONFIG["temp_data"], "sources.gdb"),
            source["alias"],
            geom_type="MULTILINESTRING",
        )


if __name__ == "__main__":
    cli()
