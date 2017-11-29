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
import hashlib
import logging
import multiprocessing
import os
import shutil
from urlparse import urlparse
import yaml

import click

import bcdata
import pgdb


with open('config.yml', 'r') as ymlfile:
    CONFIG = yaml.load(ymlfile)

HELP = {
    'csv': 'Path to csv that lists all input data sources',
    'email': 'A valid email address, used for DataBC downloads',
    'dl_path': 'Path to folder holding downloaded data',
    'alias': "The 'alias' key identifing the source of interest, from source csv",
    'out_file': 'Output geopackage name',
    'out_format': 'Output format. Default GPKG (Geopackage)'}

logging.basicConfig(level=logging.INFO)


def info(*strings):
    logging.info(' '.join(strings))


def error(*strings):
    logging.error(' '.join(strings))


def read_csv(path):
    """Return list of dicts from file, sorted by 'priority' column
    """
    source_list = [source for source in csv.DictReader(open(path, 'rb'))]
    # convert priority value to integer
    for source in source_list:
        source.update((k, int(v)) for k, v in source.iteritems()
                      if k == 'priority' and v != '')
    return sorted(source_list, key=lambda k: k['priority'])


def download_bcgw(url, dl_path, email=None, force_refresh=False):
    """Download BCGW data using DWDS
    """
    # make sure an email is provided
    if not email:
        email = os.environ['BCDATA_EMAIL']
    if not email:
        raise Exception('An email address is required to download BCGW data')
    # check that the extracted download isn't already in tmp
    gdb = hashlib.sha224(url).hexdigest()+'.gdb'
    if os.path.exists(os.path.join(dl_path, gdb)) and not force_refresh:
        return os.path.join(dl_path, gdb)
    else:
        download = bcdata.download(url, email)
        if not download:
            raise Exception('Failed to create DWDS order')
        shutil.copytree(download, os.path.join(dl_path, gdb))
        return os.path.join(dl_path, gdb)


def tiled_sql_sfcgal(sql, tile):
    """Create an sfcgal enabled connection and execute query for specified tile
    """
    db = pgdb.connect(CONFIG['db_url'], schema='public')
    db.execute('SET postgis.backend = sfcgal')
    db.execute(sql, (tile,))


def tiled_sql_geos(sql, tile):
    """Create an sfcgal enabled connection and execute query for specified tile
    """
    db = pgdb.connect(CONFIG['db_url'], schema='public')
    db.execute('SET postgis.backend = geos')
    db.execute(sql, (tile,))


def tile(source, n_processes):
    """Tile input road table
    """
    alias = source['alias']
    db = pgdb.connect(CONFIG['db_url'], schema='public')

    # move input table to '_src'
    if alias+'_src' not in db.tables:
        sql = 'ALTER TABLE {t} RENAME TO {t}_src'.format(t=alias)
        db.execute(sql)

    # get a list of tiles present in the data
    # (this takes a little while, so keep the result on hand)
    if alias+'_tiles' not in db.tables:
        info(alias+': generating list of tiles')
        sql = """CREATE TABLE {out} AS
                 SELECT a.map_tile
                 FROM tiles_20k a
                 INNER JOIN {src} b ON ST_Intersects(a.geom, b.geom)
                 ORDER BY a.map_tile""".format(src=alias+'_src',
                                               out=alias+'_tiles')
        db.execute(sql)
    tiles = [t for t in db[alias+'_tiles'].distinct('map_tile')]

    # create empty output table
    db[alias].drop()
    fields = source['primary_key']+','+source['fields'].lower()
    db.execute("""CREATE TABLE {t} AS
                  SELECT {f},
                  ''::text as map_tile,
                  geom
                  FROM {src}
                  LIMIT 0
               """.format(t=alias,
                          f=fields,
                          src=alias+'_src'))

    lookup = {'src_table': alias+'_src',
              'out_table': alias,
              'fields': fields}
    sql = db.build_query(db.queries['tile_roads'], lookup)

    # tile, clean and add required columns
    info(alias+': tiling and cleaning')
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
    alias = source['alias']
    db = pgdb.connect(CONFIG['db_url'], schema='public')

    # move input table to '_src'
    if alias+'_src' not in db.tables:
        sql = 'ALTER TABLE {t} RENAME TO {t}_src'.format(t=alias)
        db.execute(sql)

    # create filter_rings function
    db.execute(db.queries['filter_rings'])

    # get a list of tiles present in the data
    # (this takes a little while, so keep the result on hand)
    if alias+'_tiles' not in db.tables:
        info(alias+': generating list of tiles')
        sql = """CREATE TABLE {out} AS
                 SELECT a.map_tile
                 FROM tiles_20k a
                 INNER JOIN {src} b ON ST_Intersects(a.geom, b.geom)
                 ORDER BY a.map_tile""".format(src=alias+'_src',
                                               out=alias+'_tiled')
        db.execute(sql)
    tiles = [t for t in db[alias+'_tiles'].distinct('map_tile')]

    # create tiled/cleaned layer
    if alias+'_cleaned' not in db.tables:
        db.execute("""CREATE TABLE {t}
                    ({t}_id SERIAL PRIMARY KEY,
                     map_tile text,
                     geom geometry)""".format(t=alias+'_cleaned'))

        lookup = {'src_table': alias+'_src',
                  'out_table': alias+'_cleaned'}
        sql = db.build_query(db.queries['results_tile_clean'], lookup)

        # tile and clean using GEOS backend
        info(alias+': tiling and cleaning')
        func = partial(tiled_sql_geos, sql)
        pool = multiprocessing.Pool(processes=n_processes)
        results_iter = pool.imap_unordered(func, tiles)
        with click.progressbar(results_iter, length=len(tiles)) as bar:
            for _ in bar:
                pass
        pool.close()
        pool.join()

    # create output layer
    db.execute("""CREATE TABLE {t}
                    ({t}_id SERIAL PRIMARY KEY,
                     map_tile text,
                     geom geometry)""".format(t=alias))

    lookup = {'src_table': alias+'_cleaned',
              'out_table': alias}
    sql = db.build_query(db.queries['roadpoly2line'], lookup)
    # process poly2line using SFCGAL backend
    info(alias+': generating road lines from polygons')
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
    """Create a fresh database
    """
    pgdb.create_db(CONFIG['db_url'])
    db = pgdb.connect(CONFIG['db_url'])
    db.execute('CREATE EXTENSION postgis')
    db.execute('CREATE EXTENSION postgis_sfcgal')
    db.execute('CREATE EXTENSION lostgis')


@cli.command()
@click.option('--source_csv', '-s', default=CONFIG['source_csv'],
              type=click.Path(exists=True), help=HELP['csv'])
@click.option('--email', help=HELP['email'])
@click.option('--dl_path', default=CONFIG['source_data'],
              type=click.Path(exists=True), help=HELP['dl_path'])
@click.option('--alias', '-a', help=HELP['alias'])
@click.option('--force_refresh', is_flag=True, default=False,
              help='Force re-download')
def load(source_csv, email, dl_path, alias, force_refresh):
    """Download data, load to postgres
    """
    db = pgdb.connect(CONFIG['db_url'], schema='public')
    sources = read_csv(source_csv)
    # filter sources based on optional provided alias
    if alias:
        sources = [s for s in sources if s['alias'] == alias]

    # process sources where automated downloads are avaiable
    for source in sources:
        # manual downloads:
        # - must be placed in dl_path folder
        # - file must be .gdb with same name as alias specified in sources csv
        if source['manual_download'] == 'T':
            info('Loading %s from manual download' % source['alias'])
            file = os.path.join(dl_path, alias+'.gdb')
        else:
            info('Downloading %s' % source['alias'])
            # handle BCGW downloads
            if urlparse(source['url']).hostname == 'catalogue.data.gov.bc.ca':
                file = download_bcgw(source['url'], dl_path, email=email,
                                     force_refresh=force_refresh)
                info('%s downloaded to %s' % source[alias], file)

            # handle all other downloads
            else:
                raise Exception('Only DataBC Catalogue downloads are supported')

        # load downloaded data to postgres
        if source['alias'] not in db.tables or force_refresh:
            db.ogr2pg(file,
                      in_layer=source['layer_in_file'],
                      out_layer=source['alias'],
                      sql=source['query'])

    # process sources where automated downloads are not avaiable
    for source in [s for s in sources if s['manual_download'] == 'T']:
        if source['alias'] not in db.tables or force_refresh:
            db.ogr2pg(file,
                      in_layer=source['layer_in_file'],
                      out_layer=source['alias'],
                      sql=source['query'])


@cli.command()
@click.option('--source_csv', '-s', default=CONFIG['source_csv'],
              type=click.Path(exists=True), help=HELP['csv'])
@click.option('--alias', '-a', help=HELP['alias'])
@click.option('--n_processes', '-p', default=multiprocessing.cpu_count() - 1,
              help="Number of parallel processing threads to utilize")
def preprocess(source_csv, alias, n_processes):
    """Prepare input road data
    """
    sources = read_csv(source_csv)
    if alias:
        sources = [s for s in sources if s['alias'] == alias]
    # find sources noted for preprocessing
    sources = [s for s in sources if s['preprocess_operation']]
    for source in sources:
        info('Preprocessing %s' % source['alias'])
        # call noted preprocessing function
        function = source['preprocess_operation']
        globals()[function](source, n_processes)


if __name__ == '__main__':
    cli()
