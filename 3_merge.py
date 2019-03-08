import os
import csv
from subprocess import Popen, PIPE

import shutil
import subprocess
import yaml
import click
import fiona

import pgdata

# just hold all tile names as a string to make things simple
TILES = "082E,082F,082G,082J,082K,082L,082M,082N,082O,083C,083D,083E,092B,092C,092E,092F,092G,092H,092I,092J,092K,092L,092M,092N,092O,092P,093A,093B,093C,093D,093E,093F,093G,093H,093I,093J,093K,093L,093M,093N,093O,093P,094A,094B,094C,094D,094E,094F,094G,094H,094I,094J,094K,094L,094M,094N,094O,094P,102I,102O,102P,103A,103B,103C,103F,103G,103H,103I,103J,103K,103O,103P,104A,104B,104C,104F,104G,104H,104I,104J,104K,104L,104M,104N,104O,104P,114I,114O,114P"

with open("config.yml", "r") as ymlfile:
    CONFIG = yaml.load(ymlfile)


HELP = {
    "csv": "Path to csv that lists all input data sources",
    "alias": "The 'alias' key identifing the source of interest, from source csv",
}


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


def merge():
    """Merge output tile .gdb layers into single output
    """
    sources = read_csv(CONFIG["source_csv"])
    tiles = TILES.split(",")

    # Build an orderd list of fields noted for retention
    out_fields = []
    for source in sources:
        # Do not keep fields from tile layer or layers coming from poly roads
        if source["alias"] != "tiles_20k" and source["preprocess_operation"] != "roadpoly2line":
            fieldlist = [source["primary_key"]] + source["fields"].split(",")
            # prepend the alias to the field name
            out_fields = out_fields + [source["alias"] + "_" + f.lower().strip() for f in fieldlist]

    db = pgdata.connect(CONFIG["db_url"], schema="public")
    db["integrated_roads"].drop()
    commands = []
    for tile in tiles:
        click.echo("Examining tile {}".format(tile))
        in_gdb = os.path.join(CONFIG["temp_data"], "tiles", "temp_" + tile + ".gdb")
        in_layer = "roads_" + tile

        # check that input actually has data
        n_recs = 0
        if in_layer in fiona.listlayers(in_gdb):
            with fiona.open(in_gdb) as src:
                # get fields present in the input tile, tiles will only
                # have fields for layers actually present within the tile
                in_fields = src.schema["properties"].keys()
                n_recs = len(list(src))

        if n_recs >= 1:
            # determine which fields are missing from the input
            missing_fields = list(set(out_fields).difference(set(in_fields)))
            # build list of fields to extract, substituting missing fields
            # with NULL
            query_fields = []
            for i, f in enumerate(out_fields):
                if f in missing_fields:
                    query_fields.append("NULL AS " + f)
                else:
                    query_fields.append(f)
            sql = """SELECT
                bcgw_source,
                bcgw_extraction_date,
                map_tile,
                {f}
                FROM {lyr}""".format(
                f=", ".join(query_fields), lyr=in_layer
            )
            commands.append([
                "ogr2ogr",
                "-f",
                "PostgreSQL",
                "PG:host={h} user={u} dbname={db} password={pwd}".format(
                    h=db.host, u=db.user, db=db.database, pwd=db.password
                ),
                "-lco",
                "SCHEMA={schema}".format(schema="public"),
                "-lco",
                "GEOMETRY_NAME=geom",
                "-nln",
                "integrated_roads",
                "-dialect",
                "SQLITE",
                "-sql",
                sql,
                in_gdb]
            )
    # execute the first command, remove it from the list
    click.echo("Creating merged table by loading first tile")
    click.echo(" ".join(commands[0]))
    subprocess.run(commands[0])
    commands.remove(commands[0])

    click.echo("Loading remaining tiles...")
    # add -update -append to the rest of the commands
    for c in commands:
        c.extend(["-update", "-append"])
    # execute in parallel
    # shuzhanfan.github.io/2017/12/parallel-processing-python-subprocess
    procs_list = [Popen(cmd, stdout=PIPE, stderr=PIPE) for cmd in commands]
    for proc in procs_list:
        proc.wait()


if __name__ == "__main__":
    merge()
