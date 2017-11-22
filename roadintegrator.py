import os
import logging
import tempfile
import csv
import shutil
import yaml
from datetime import date
import time
import getpass
from multiprocessing import Pool
from functools import partial

import click
import bcdata
import arcpy

import arcutil


logging.basicConfig(level=logging.INFO)

HELP = {
    "csv": 'Path to csv that lists all input data sources',
    "email": 'A valid email address, used for DataBC downloads',
    "dl_path": 'Path to folder holding downloaded data',
    "alias": "The 'alias' key identifing the source of interest, from source csv"}


def get_files(path):
    """Returns an iterable containing the full path of all files in the
    specified path.
    https://github.com/OpenBounds/Processing/blob/master/utils.py
    """
    if os.path.isdir(path):
        for (dirpath, dirnames, filenames) in os.walk(path):
            for filename in filenames:
                if not filename[0] == '.':
                    yield os.path.join(dirpath, filename)
    else:
        yield path


def read_csv(path):
    """
    Returns list of dicts from file, sorted by 'hierarchy' column
    https://stackoverflow.com/questions/72899/
    """
    source_list = [source for source in csv.DictReader(open(path, 'rb'))]
    # convert hierarchy value to integer
    for source in source_list:
        source.update((k, int(v)) for k, v in source.iteritems()
                      if k == "hierarchy" and v != '')
    return sorted(source_list, key=lambda k: k['hierarchy'])


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


def get_path_parts(path):
    """Splits a path into parent directories and file.
    """
    return path.split(os.sep)


def download_bcgw(url, dl_path, email=None, gdb=None):
    """Download BCGW data using DWDS
    """
    # make sure an email is provided
    if not email:
        email = os.environ["BCDATA_EMAIL"]
    if not email:
        raise Exception("An email address is required to download BCGW data")
    # check that the extracted download isn't already in tmp
    if gdb and os.path.exists(os.path.join(dl_path, gdb)):
        return os.path.join(dl_path, gdb)
    else:
        download = bcdata.download(url, email)
        if not download:
            raise Exception("Failed to create DWDS order")
        # move the downloaded .gdb to specified dl_path
        out_gdb = os.path.split(download)[1]
        shutil.copytree(download, os.path.join(dl_path, out_gdb))
        return os.path.join(dl_path, out_gdb)


def parse_layers_tiles(param, layers, tiles):
    """
    Create lists from strings if provided.
    Otherwise supply defaults
    """
    if layers:
        layers = layers.split(",")
        layers = [l for l in param["layers"] if l["alias"] in layers]
    else:
        layers = param["layers"]

    return (layers, tiles)


def initialize_output(param):
    """
    Create empty output feature class
    """
    wksp, fc = os.path.split(out_fc)
    # set workspace to in_memory in an attempt to speed things up a bit
    arcpy.env.workspace = 'in_memory' #wksp
    # overwrite any existing outputs
    arcpy.env.overwriteOutput = True

    # create output feature class
    if not arcpy.Exists(out_fc):
        arcpy.CreateFeatureclass_management(wksp, fc,
                                            "POLYLINE", "", "", "",
                                            BC_ALBERS_SR)
        # add all columns noted in source .csv
        for road in param["layers"]:
            fields = arcutil.clean_fieldlist(road["primary_key"])+arcutil.clean_fieldlist(road["fields"])
            for field in arcpy.ListFields(os.path.join(srcWksp, road["alias"])):
                if field.name in fields:
                    # only add a field once
                    # (ften primary key is listed twice as ften is coming from
                    # two source layers - they are mutually exclusive so a single
                    # key should be fine)
                    if field.name not in [f.name for f in arcpy.ListFields(outFC)]:
                        arcpy.AddField_management(outFC,
                                                  field.name,
                                                  ARC_TYPE_LOOKUP[field.type],
                                                  field.precision,
                                                  field.scale,
                                                  field.length)
            # add date and source fields
            arcpy.AddField_management(outFC,
                                      "BCGW_SOURCE", "TEXT", "", "", "255")
            arcpy.AddField_management(outFC,
                                      "BCGW_EXTRACTION_DATE",
                                      "TEXT", "", "", "255")


def setup(layers=None, tiles=None):
    """
    Read paramaters file, create required folders, .gdbs, connections
    """
    # read config/parameters
    with open("config.yml", 'r') as ymlfile:
        cfg = yaml.load(ymlfile)
    param = cfg
    # create folder structure in tmp
    param["TMP"] = os.path.join(tempfile.gettempdir(), cfg["tmpdir"])
    try:
        os.makedirs(os.path.join(param["TMP"], "tiles"))
    except OSError:
        if not os.path.isdir(os.path.join(param["TMP"], "tiles")):
            raise
    # create workspaces and point to them in the param dict
    for gdb in ["src", "prep", "out"]:
        param[gdb+"_wksp"] = arcutil.create_wksp(param["TMP"], gdb+".gdb")
    # point to tile processing folder
    param["tiledir"] = os.path.join(param["TMP"], "tiles")
    # create BCGW connection if not present
    if "BCGW_USR" not in param.keys():
        param["BCGW_USR"] = getpass.getuser()
    param["BCGW"] = arcutil.create_bcgw_connection(param["BCGW_USR"])
    # get grid tile layer
    if not arcpy.Exists(os.path.join(param["src_wksp"], "grid")):
        arcutil.copy_data(os.path.join(param['BCGW'], param["grid"]),
                          os.path.join(param["src_wksp"], "grid"),
                          fieldList=param["tile_column"])

    # read datalist and tile list
    param["layers"] = arcutil.read_datalist(param["datalist"])
    if layers:
        layers = layers.split(",")
        subset = [l for l in param["layers"] if l["alias"] in layers]
        param["layers"] = subset
    if tiles:
        param["tiles"] = tiles.split(",")
    else:
        param["tiles"] = [t['MAP_TILE'] for t in arcutil.read_datalist(param["tilelist"])]

    # update source paths prefixed with a $ variable
    # There needs to be a lookup in config.yml for any paths other than
    # BCGW and TMP
    sources = [l["source"] for l in param["layers"] if l["source"][:1] == "$"]
    # Split the path on separators, hopefully it is properly constructed
    pathvars = set([s.split("\\")[0].strip("$") for s in sources])
    for layer in param["layers"]:
        for placeholder in pathvars:
            layer.update({"source": layer["source"].replace("$"+placeholder,
                                                            param[placeholder])})
        # make sure fieldlists are clean
        for column in ["fields", "primary_key"]:
            layer.update({column: arcutil.clean_fieldlist(layer[column])})

    return param


def get_source_data(param):
    """
    Extract and cut inputs with specified grid

    Since road data isn't too dense (compared to VRI anyway), we can just use
    the intersect tool for entire layers and do this in-memory
    """
    wksp = param["src_wksp"]
    click.echo("Extracting, tiling and indexing source data")
    for layer in param["layers"]:
        if not arcpy.Exists(os.path.join(wksp, layer["alias"])):
            click.echo(" - "+os.path.split(layer["source"])[1])
            # define fields to pull
            fields = layer["fields"]
            if not layer["create_key"]:
                fields = layer["primary_key"]+fields
            if layer["tile_column"]:
                fields = fields + [layer["tile_column"]]
            fieldlist = ",".join(fields)
            # copy input layer
            arcutil.copy_data(layer["source"],
                              os.path.join(wksp, layer["alias"]),
                              layer["query"],
                              fieldList=fieldlist)
            # make sure any existing tile column is standard
            if layer["tile_column"] and layer["tile_column"] != param["tile_column"]:
                arcpy.AddField_management(os.path.join(wksp,
                                                       layer["alias"]),
                                          param["tile_column"],
                                          "TEXT", "", "", "32")
                arcutil.remap(os.path.join(wksp, layer["alias"]),
                              {param["tile_column"] : "!"+layer["tile_column"]+"!"})
                arcpy.AddIndex_management(os.path.join(wksp,
                                                       layer["alias"]),
                                          param["tile_column"],
                                          layer["alias"]+'map_tile_idx')
            # add date and source
            arcpy.AddField_management(os.path.join(wksp, layer["alias"]),
                                      "BCGW_SOURCE", "TEXT", "", "", "255")
            arcpy.AddField_management(os.path.join(wksp, layer["alias"]),
                                      "BCGW_EXTRACTION_DATE",
                                      "TEXT", "", "", "255")
            arcutil.remap(os.path.join(wksp, layer["alias"]),
                          {"BCGW_EXTRACTION_DATE": date.today().isoformat()})
            if layer["noted_source"]:
                bcgw_source = os.path.split(layer["noted_source"])[1]
            else:
                bcgw_source = os.path.split(layer["source"])[1]
            arcutil.remap(os.path.join(wksp, layer["alias"]),
                          {"BCGW_SOURCE": bcgw_source})
            # add new primary key if so noted
            # the new key is just a copy of the objectid, added so that it
            # gets retained in subsequent operations
            if layer["create_key"]:
                arcutil.add_unique_id(os.path.join(wksp, layer["alias"]),
                                      layer["primary_key"][0])
            # repair geom
            arcpy.RepairGeometry_management(os.path.join(wksp, layer["alias"]))


def process(param, tile):
    """
    For given tile:
      - load road data from each noted source
      - shift lower priority roads within specified tolerance of higher priority
        roads to match position of higher priority roads
      - remove duplicate roads from lower priority source
      - merge all road sources into single layer
    """
    outfc = os.path.join(param["tiledir"], "temp_"+tile+".gdb", "roads_"+tile)
    if not arcpy.Exists(outfc):
        start_time = time.time()
        # create tile workspace
        tile_wksp = arcutil.create_wksp(param["tiledir"], "temp_"+tile+".gdb")
        # try and do all work in memory
        arcpy.env.workspace = "in_memory"

        # create a clip layer from grid
        tile_layer = "tile_"+tile+"_lyr"
        tile_query = param["tile_column"]+" LIKE '"+tile+"%'"
        arcpy.MakeFeatureLayer_management(os.path.join(param["src_wksp"], "grid"),
                                          tile_layer,
                                          tile_query)
        # get data for each source layer within given tile
        for layer in param["layers"]:
            src_layer = os.path.join(param["src_wksp"], layer["alias"])
            mem_layer = layer["alias"]+"_"+tile
            fieldlist = ",".join(layer["primary_key"]+
                                 layer["fields"]+
                                 ["BCGW_SOURCE", "BCGW_EXTRACTION_DATE"])
            # if layer is pre-tiled, simply query it on the tile column
            if param["tile_column"] in [f.name for f in arcpy.ListFields(src_layer)]:
                arcutil.copy_data(src_layer, mem_layer, tile_query, fieldlist)
            # otherwise do a spatial query and clip
            else:
                ftr_layer = layer["alias"]+"_"+tile+"_lyr"
                fieldinfo = arcutil.pull_items(src_layer, fieldlist)
                arcpy.MakeFeatureLayer_management(src_layer, ftr_layer,
                                                  "", "", fieldinfo)
                arcpy.SelectLayerByLocation_management(ftr_layer, "INTERSECT",
                                                       tile_layer)
                arcpy.Clip_analysis(ftr_layer, tile_layer, mem_layer)
                # cleanup
                arcpy.Delete_management(ftr_layer)

            # repair geom slows things down but we want to be tidy
            arcpy.RepairGeometry_management(mem_layer)

        # use only layers that actually have data
        roads = []
        for layer in param["layers"]:
            mem_layer = layer["alias"]+"_"+tile
            if arcutil.n_records(mem_layer) > 0:
                roads = roads + [mem_layer]

        # only run the integrate / erase etc if there is more than one road source
        if len(roads) > 1:
            # regenerate priority numbers, in case empty layers have been removed
            integrate_str = ";".join([r+" "+str(i+1) for i,r in enumerate(roads)])
            # perform integrate, modifing extracted road data in place,
            # snapping roads within tolerance
            arcpy.Integrate_management(integrate_str, param["tolerance"])
            # start with the roads of top priority,
            in_layer = roads[0]
            # then loop through the rest of the roads
            for i in range(1, len(roads)):
                out_layer = "temp_"+tile+"_"+str(i)
                # erase first layer or previous output with next roads layer
                arcpy.Erase_analysis(roads[i],
                                     in_layer,
                                     "temp_missing_roads_"+tile,
                                     "0.01 Meters")
                # merge the output missing roads with the previous input
                arcpy.Merge_management(["temp_missing_roads_"+tile, in_layer],
                                       out_layer)
                arcpy.Delete_management("temp_missing_roads_"+tile)
                in_layer = out_layer
            # write to output gdb
            arcutil.copy_data(out_layer, os.path.join(tile_wksp, "roads_"+tile))
            # delete temp layers
            for i in range(1, len(roads)):
                arcpy.Delete_management("temp_"+tile+"_"+str(i))

        elif len(roads) == 1:
            # append single road source to output
            arcutil.copy_data(roads[0], os.path.join(tile_wksp, "roads_"+tile))
            #arcutil.copy_data(roads[0], "roads_"+tile)

        elif len(roads) == 0:
            # if there aren't any roads, don't do anything
            click.echo('No roads present in tile '+tile)

        # cleanup
        #for fc in arcpy.ListFeatureClasses():
        #    arcpy.Delete_management(fc)
        for layer in param["layers"]:
            if arcpy.Exists(layer["alias"]+"_"+tile):
                arcpy.Delete_management(layer["alias"]+"_"+tile)
        arcpy.Delete_management(tile_layer)
        elapsed_time = time.time() - start_time
        click.echo("Completed "+tile+": "+str(elapsed_time))


# define commands
@click.group()
def cli():
    pass


@cli.command()
@click.option("--layers", "-l",
              help='Comma separated list of layers to extract')
def extract(layers):
    """
    Extract and tile required source layers
    """
    param = setup(layers)
    get_source_data(param)


@cli.command()
@click.option("--tiles", "-t",
              help='Comma separated list of tiles to process')
def integrate(tiles):
    """
    Run road integration
    """
    start_time = time.time()
    param = setup(None, tiles)

    # split processing between multiple processes
    # n processes is equal to processess parmeter in config
    func = partial(process, param)
    pool = Pool(processes=param["processes"])
    pool.map(func, param["tiles"])
    pool.close()
    pool.join()

    elapsed_time = time.time() - start_time
    click.echo("All tiles complete in : "+str(elapsed_time))
    click.echo("Merging tiles to output...")
    # merge outputs to single output layer
    outputs = []
    for t in param["tiles"]:
        fc = os.path.join(param["tiledir"], "temp_"+t+".gdb", "roads_"+t)
        if arcpy.Exists(fc):
            outputs = outputs + [fc]
    arcpy.Merge_management(outputs, os.path.join(param["out_wksp"], param["output"]))
    click.echo("Output ready in : "+os.path.join(param["out_wksp"], param["output"]))

if __name__ == '__main__':
    cli()
