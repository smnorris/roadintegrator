import os
import csv

import shutil
import subprocess
import yaml
import click

import fiona


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
    click.echo("Merging tiles to output...")
    sources = read_csv(CONFIG["source_csv"])
    tiles = TILES.split(",")

    out_gdb = os.path.join(os.getcwd(), "integrated_roads.gdb")

    # remove existing output
    if os.path.exists(out_gdb):
        shutil.rmtree(out_gdb)

    # Build an orderd list of fields noted for retention
    out_fields = []
    for source in sources:
        # Do not keep fields from tile layer or layers coming from poly roads
        if source["alias"] != "tiles_20k" and source["preprocess_operation"] != "roadpoly2line":
            fieldlist = [source["primary_key"]] + source["fields"].split(",")
            # prepend the alias to the field name
            out_fields = out_fields + [source["alias"] + "_" + f.lower() for f in fieldlist]

    # build string remapping field name to UPPER
    fieldstring = ", ".join([f.strip() + " AS " + f.strip().upper() for f in out_fields])

    # loop through the tiles, appending to output file
    for tile in tiles:
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
            fieldquery = fieldstring
            # substitute NULL as input for missing fields
            for f in missing_fields:
                fieldquery = fieldquery.replace(" "+f.lower()+" ", " NULL ")

            sql = """SELECT
                bcgw_source AS BCGW_SOURCE,
                bcgw_extraction_date AS BCGW_EXTRACTION_DATE,
                map_tile AS MAP_TILE_20K,
                {f},
                shape
                FROM {lyr}""".format(
                f=fieldquery, lyr=in_layer
            )
            command = [
                "ogr2ogr",
                "-f",
                "FileGDB",
                "-nln",
                "integrated_roads",
                "-dialect",
                "SQLITE",
                "-sql",
                sql,
                out_gdb,
                in_gdb,
            ]
            if os.path.exists(out_gdb):
                command.insert(1, "-update")
                command.insert(2, "-append")
            click.echo(" ".join(command))
            subprocess.run(command)


if __name__ == "__main__":
    merge()
