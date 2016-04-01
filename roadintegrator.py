import os
import tempfile
import yaml
import getpass
from datetime import date

import click
import arcpy

import arcutil


def initialize_output(param):
    """
    Create empty output feature class
    """
    wksp, fc  = os.path.split(out_fc)
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
                                      "BCGW_SOURCE", "TEXT","", "", "255")
            arcpy.AddField_management(outFC,
                                      "BCGW_EXTRACTION_DATE",
                                      "TEXT","", "", "255")
def setup():
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
    grid = os.path.join(param["src_wksp"], "grid")
    if not arcpy.Exists(param["grid"]):
        arcutil.copy_data(os.path.join(param['BCGW'], param["grid"]),
                          os.path.join(param["src_wksp"], "grid"),
                          fieldList=param["tile_column"])

    # read datalist and tile list
    param["layers"] = arcutil.read_datalist(param["datalist"])
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
            #print layer["source"].replace(placeholder, param[placeholder])
    return param


def get_source_data(param):
    """
    Get required source layers listed in road_inputs.csv
    """
    # get results poly roads
    #fmw = r'''E:\sw_nt\FME\fme.exe "ResultsPolyRoads2Line_FME2012"'''
    #os.system(fmw)
    # extract road layers noted in road_inputs.csv
    wksp = param["src_wksp"]
    click.echo("Extracting, tiling and indexing source data")
    for roads in param["layers"]:
        if not arcpy.Exists(os.path.join(wksp, roads["alias"])):
            click.echo(" - "+os.path.split(roads["source"])[1])
            # Cut inputs with specified grid
            # Since road data isn't too dense (compared to VRI anyway),
            # we can just use the intersect tool for entire layers
            # and do this in-memory
            if roads["tiled"] == 'N':
                arcutil.copy_data(roads["source"],
                          os.path.join("in_memory", roads["alias"]),
                          roads["query"])
                arcpy.Intersect_analysis([os.path.join("in_memory",
                                                       roads["alias"]),
                                          os.path.join(wksp, "grid")],
                                         os.path.join(wksp, roads["alias"]))
                arcpy.AddIndex_management(os.path.join(wksp, roads["alias"]),
                                          param["tile_column"],
                                          roads["alias"]+'map_tile_idx')
                #arcpy.Delete_management(os.path.join(wksp,
                #                                     roads["alias"]+"_prelim"))
            # simply copy pre-tiled data, making sure tile column is standard
            if roads["tiled"] == 'Y':
                arcutil.copy_data(roads["source"],
                                  os.path.join(wksp, roads["alias"]),
                                  roads["query"])
                if roads["tile_column"] != param["tile_column"]:
                    arcpy.AddField_management(os.path.join(wksp, roads["alias"]),
                                              param["tile_column"],
                                              "TEXT","", "", "32")
                    arcpy.AddIndex_management(os.path.join(wksp, roads["alias"]),
                                             param["tile_column"],
                                             roads["alias"]+'map_tile_idx')
            # add date and source
            arcpy.AddField_management(os.path.join(wksp, roads["alias"]),
                                      "BCGW_SOURCE", "TEXT","", "", "255")
            arcpy.AddField_management(os.path.join(wksp, roads["alias"]),
                                      "BCGW_EXTRACTION_DATE",
                                      "TEXT","", "", "255")
            arcutil.remap(os.path.join(wksp, roads["alias"]),
                          {"BCGW_EXTRACTION_DATE": date.today().isoformat()})
            if roads["noted_source"]:
                bcgw_source = os.path.split(roads["noted_source"])[1]
            else:
                bcgw_source = os.path.split(roads["source"])[1]
            arcutil.remap(os.path.join(wksp, roads["alias"]),
                          {"BCGW_SOURCE": bcgw_source})


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
    param = setup()
    get_source_data(param)



@cli.command()
def integrate():
    """
    Combine all road layers into single output
    """
    param = setup()


if __name__ == '__main__':
    cli()
