import os
import tempfile
import yaml
import getpass
from datetime import date

import click
import arcpy

import arcutil


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
            # if the primary key is remapped to a new name in the source .csv,
            # handle that here
            if road["new_primary_key"]:
                road["primary_key"] = road["new_primary_key"]
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
    print param["TMP"]
    # get BCGW credentials
    if "BCGW_USR" not in param.keys():
        param["BCGW_USR"] = getpass.getuser()
    param["BCGW_PWD"] = getpass.getpass("Enter BCGW password:")

    # create BCGW connection if not present
    param["BCGW"] = arcutil.create_bcgw_connection(param["BCGW_USR"],
                                                   param["BCGW_PWD"])
    # get tile grid and point to it
    if not arcpy.Exists(param["grid"]):
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
    # make sure fieldlist is clean
    layer["fields"] = arcutil.clean_fieldlist(layer["fields"])
    return param


def get_source_data(param):
    """
    Extract and cut inputs with specified grid

    Since road data isn't too dense (compared to VRI anyway), we can just use
    the intersect tool for entire layers and do this in-memory
    """
    wksp = param["src_wksp"]
    click.echo("Extracting, tiling and indexing source data")
    for roads in param["layers"]:
        if not arcpy.Exists(os.path.join(wksp, roads["alias"])):
            click.echo(" - "+os.path.split(roads["source"])[1])
            # define fields to pull
            if not layer["create_key"]:
                fields = layer["primary_key"]+layer["fields"]
            else:
                fields = layer["fields"]
            fieldlist = ",".join(fields)
            if not roads["tile_column"]:
                arcutil.copy_data(roads["source"],
                                  os.path.join("in_memory", roads["alias"]),
                                  roads["query"],
                                  fieldlist=fieldlist)
                arcpy.Intersect_analysis([os.path.join("in_memory",
                                                       roads["alias"]),
                                          os.path.join(wksp, "grid")],
                                         os.path.join(wksp, roads["alias"]))
                arcpy.AddIndex_management(os.path.join(wksp, roads["alias"]),
                                          param["tile_column"],
                                          roads["alias"]+'map_tile_idx')
            # simply copy pre-tiled data, making sure tile column is standard
            if roads["tile_column"]:
                arcutil.copy_data(roads["source"],
                                  os.path.join(wksp, roads["alias"]),
                                  roads["query"],
                                  fieldlist=fieldlist)
                if roads["tile_column"] != param["tile_column"]:
                    arcpy.AddField_management(os.path.join(wksp,
                                                           roads["alias"]),
                                              param["tile_column"],
                                              "TEXT", "", "", "32")
                    arcpy.AddIndex_management(os.path.join(wksp,
                                                           roads["alias"]),
                                              param["tile_column"],
                                              roads["alias"]+'map_tile_idx')
            # add date and source
            arcpy.AddField_management(os.path.join(wksp, roads["alias"]),
                                      "BCGW_SOURCE", "TEXT", "", "", "255")
            arcpy.AddField_management(os.path.join(wksp, roads["alias"]),
                                      "BCGW_EXTRACTION_DATE",
                                      "TEXT", "", "", "255")
            arcutil.remap(os.path.join(wksp, roads["alias"]),
                          {"BCGW_EXTRACTION_DATE": date.today().isoformat()})
            if roads["noted_source"]:
                bcgw_source = os.path.split(roads["noted_source"])[1]
            else:
                bcgw_source = os.path.split(roads["source"])[1]
            arcutil.remap(os.path.join(wksp, roads["alias"]),
                          {"BCGW_SOURCE": bcgw_source})

            # add new primary key if so noted
            # the new key is just a copy of the objectid, added so that it
            # gets retained in subsequent operations
            if roads["create_key"]:
                arcutil.add_unique_id(os.path.join(wksp, roads["alias"]),
                                      roads["new_primary_key"])


def process(param, tile):
    """
    From provided list of road data, shift lower priority roads within
    specified tolerance of higher priority roads to match position of higher
    priority roads.
    """
    # try and do all work in memory
    arcpy.env.workspace = "in_memory"

    # get data for each source layer within given tile
    for layer in param["layers"]:
        mem_layer = layer["alias"]+"_"+tile
        fieldlist = ",".join(layer["primary_key"],
                             layer["fields"],
                             ["BCGW_SOURCE", "BCGW_EXTRACTION_DATE"])
        arcutil.copy_data(os.path.join(param["src_wksp"], layer["alias"]),
                          mem_layer,
                          param["tile_column"]+" LIKE '"+tile+"%'",
                          fieldlist=fieldlist)
        arcpy.RepairGeometry_management(mem_layer)

    # use only layers that actually have data
    layers = [l["alias"] ]
    layers = [road for road in  if get_count(road["alias"]+"_"+job) > 0]

    # repair geometry for each layer
    for roadlayer in roadSources:
        roadlayer["alias"] = roadlayer["alias"]+"_"+job
        arcpy.RepairGeometry_management(roadlayer["alias"])

    # extract just the aliases/feature class names
    roads = [r["alias"] for r in roadSources]

    # only run the integrate / erase etc if there is more than one road source for the
    # given tile
    if len(roads) > 1:
        # regenerate priority numbers, in case empty layers have been removed
        integrateData = ";".join([r+" "+str(i+1) for i,r in enumerate(roads)])

        # modify extracted road data in place, snapping roads within 7m
        arcpy.Integrate_management(integrateData, tolerance)

        # start with the roads of top priority,
        inlayer = roads[0]
        # then loop through the rest of the roads
        for i in range(1, len(roads)):
            outlayer = "temp_"+job+"_"+str(i)

            # erase first layer or previous output with next roads layer
            print "erasing "+inlayer+" roads from "+roads[i]
            arcpy.Erase_analysis(roads[i],
                                 inlayer,
                                 "temp_missing_roads_"+job,
                                 "0.01 Meters")

            # merge the output missing roads with the previous input
            print "merging roads remaining from "+roads[i]+" with "+inlayer+" to create "+outlayer
            arcpy.Merge_management(["temp_missing_roads_"+job,inlayer], outlayer)
            arcpy.Delete_management("temp_missing_roads_"+job)
            inlayer = outlayer

        # create temp output workspace for given tile
        temp_wksp = arcutil.create_wksp(param["tiledir"], "temp_"+tile+".gdb")

        # append to output
        arcpy.Append_management([outlayer], outFC, "NO_TEST")

    elif len(roads) == 1:
        # append single road source to output
        arcpy.Append_management([roads[0]], outFC, "NO_TEST")

    elif len(roads) == 0:
        # if there aren't any roads, don't do anything
        print 'No roads present in tile'

    # cleanup
    for road in read_datalist(roadlist):
        arcpy.Delete_management(road["alias"]+"_"+job)


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
def integrate():
    """
    Combine all road layers into single output
    """
    param = setup()
    process(param)


if __name__ == '__main__':
    cli()
