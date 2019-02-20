import os
import csv

import shutil
import subprocess
import yaml
import click


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

    # build orderd list of fields to retain
    # don't use tile source layers or any layers coming from polygon roads
    sources = [s for s in sources if s["alias"] != "tiles_20k"]
    sources = [s for s in sources if s["preprocess_operation"] != "roadpoly2line"]
    fields = []
    for source in sources:
        fieldlist = [source["primary_key"]] + source["fields"].split(",")
        fields = fields + [source["alias"] + "_" + f.lower() for f in fieldlist]

    fieldstring = ", ".join([f.strip() + " AS " + f.strip().upper() for f in fields])

    # build list of tiles with data
    out_tiles = []
    for tile in tiles:
        in_gdb = os.path.join(CONFIG["temp_data"], "tiles", "temp_" + tile + ".gdb")
        in_layer = "roads_" + tile
        if os.path.exists(in_gdb):
            out_tiles.append(tile)
    for i, tile in enumerate(out_tiles):
        sql = """SELECT
            bcgw_source AS BCGW_SOURCE,
            bcgw_extraction_date AS BCGW_EXTRACTION_DATE,
            map_tile AS MAP_TILE_20K,
            {f},
            geom
            FROM {lyr}""".format(
            f=fieldstring, lyr=in_layer
        )
        command = [
            "ogr2ogr",
            "-progress",
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
        if i != 0:
            command.insert(1, "-update")
            command.insert(2, "-append")
        click.echo(" ".join(command))
        subprocess.call(command)


if __name__ == "__main__":
    merge()
