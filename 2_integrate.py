import os
import time
import logging
import multiprocessing
from functools import partial
import csv
import uuid

import yaml
import click
import arcpy


TILES = "082E,082F,082G,082J,082K,082L,082M,082N,082O,083C,083D,083E,092B,092C,092E,092F,092G,092H,092I,092J,092K,092L,092M,092N,092O,092P,093A,093B,093C,093D,093E,093F,093G,093H,093I,093J,093K,093L,093M,093N,093O,093P,094A,094B,094C,094D,094E,094F,094G,094H,094I,094J,094K,094L,094M,094N,094O,094P,102I,102O,102P,103A,103B,103C,103F,103G,103H,103I,103J,103K,103O,103P,104A,104B,104C,104F,104G,104H,104I,104J,104K,104L,104M,104N,104O,104P,114I,114O,114P"

with open('config.yml', 'r') as ymlfile:
    CONFIG = yaml.load(ymlfile)


HELP = {
    'csv': 'Path to csv that lists all input data sources',
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
    source_list = [source for source in csv.DictReader(open(path, 'r'))]
    # convert priority value to integer
    for source in source_list:
        source.update((k, int(v)) for k, v in source.items()
                      if k == 'priority' and v != '')
    return sorted(source_list, key=lambda k: k['priority'])


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


def n_records(table):
    """ Shortcut to arcpy.GetCount
    """
    result = arcpy.GetCount_management(table)
    return int(result.getOutput(0))


def clean_fieldlist(in_string):
    """
    Return a python list from a comma separated list of fields,
    removing any spaces from ends of input
    """
    if in_string:
        return [s.strip() for s in in_string.split(",")]
    else:
        return []


def pull_items(inData, fieldList=None, lowercasify=False):
    """
    Given an input data source and a comma separated string of field names,
    return a fieldinfo object that includes only the fields listed as VISIBLE
    Given no fields as input returns all fields as VISIBLE
    """
    fieldList = clean_fieldlist(fieldList)
    # create a field info object
    fieldInfo = arcpy.FieldInfo()
    # iterate through fields
    inputfields = [field.name for field in arcpy.ListFields(inData) if not field.required]
    for index in range(len(inputfields)):
        if fieldList:
            if inputfields[index].upper() in [f.upper() for f in fieldList]:
                if lowercasify:
                    fieldInfo.addField(inputfields[index],
                                       inputfields[index].lower(), "VISIBLE", "")
                else:
                    fieldInfo.addField(inputfields[index],
                                       inputfields[index].upper(), "VISIBLE", "")
            else:
                fieldInfo.addField(inputfields[index],
                                   inputfields[index], "HIDDEN", "")
        else:
            fieldInfo.addField(inputfields[index],
                               inputfields[index], "VISIBLE", "")
    return fieldInfo


def copy_data(sourcePath, destPath, query=None, fieldList=None, aoi=None,
              overwrite=False, clip=False, tableOnly=False, lowercasify=False):
    """
    Extract a data layer that has a valid ArcCatalog path to specified location

    Kwargs:
        query     - sql where clause to restrict records returned
        fieldList - a comma delimeted string listing fields to retain
        aoi       - only records intersecting this layer (all features) will be returned
        overwrite - boolean overwrite flag
        clip      - clip output geometries to the aoi layer
    """
    # make sure output does not already exist if overwrite is not enabled
    if not overwrite and arcpy.Exists(destPath):
        print('copy_data error - output exists:' + destPath)
        return
    else:
        # set to overwrite (as the layer existence is already checked above)
        arcpy.env.overwriteOutput = True
        # build fieldinfo object
        if fieldList:
            fieldinfo = pull_items(sourcePath, fieldList, lowercasify)
        else:
            fieldinfo = None
        # if not copying geometry
        if tableOnly is True:
            arcpy.MakeTableView_management(sourcePath, "table_view",
                                           query, "", fieldinfo)
            arcpy.CopyRows_management("table_view", destPath)
        # get spatial data
        else:
            # make feature layer
            featLyr = "t"+str(uuid.uuid1())
            arcpy.MakeFeatureLayer_management(sourcePath,
                                              featLyr,
                                              query,
                                              "",
                                              fieldinfo)
            # just clip data if so specified
            if aoi and clip:
                arcpy.Clip_analysis(featLyr, aoi, destPath)
            else:
                # select features within aoi if given
                if aoi:
                    arcpy.SelectLayerByLocation_management(featLyr,
                                                           "INTERSECT", aoi)
                # copy features
                outpath, outfile = os.path.split(destPath)
                if not outpath:
                    outpath = arcpy.env.workspace
                arcpy.FeatureClassToFeatureClass_conversion(featLyr,
                                                            outpath, outfile)
        # cleanup
        if tableOnly is False:
            arcpy.Delete_management(featLyr)


def create_wksp(path, gdb):
    """
    Create a .gdb workspace in given path
    """
    wksp = os.path.join(path, gdb)
    # create the workspace if it doesn't exist
    if not arcpy.Exists(wksp):
        arcpy.CreateFileGDB_management(path, gdb)
    return os.path.join(path, gdb)


def integrate(sources, tile):
    """
    For given tile:
      - load road data from each source
      - shift low priority roads within specified tolerance of higher priority
        roads to match position of higher priority roads
      - remove duplicate roads from lower priority source
      - merge all road sources into single layer
    """
    src_wksp = os.path.join(CONFIG['temp_data'], 'sources.gdb')
    tile_wksp = os.path.join(CONFIG['temp_data'], 'tiles')
    make_sure_path_exists(tile_wksp)
    out_fc = os.path.join(tile_wksp, 'temp_'+tile+'.gdb', 'roads_'+tile)
    if not arcpy.Exists(out_fc):
        start_time = time.time()
        # create tile workspace
        tile_wksp = create_wksp(tile_wksp, 'temp_'+tile+'.gdb')
        # try and do all work in memory
        arcpy.env.workspace = 'in_memory'
        # get data for each source layer within given tile
        for layer in sources:
            src_layer = os.path.join(src_wksp, layer['alias'])
            mem_layer = layer['alias']+'_'+tile
            tile_query = CONFIG['tile_column']+" LIKE '"+tile+"%'"
            copy_data(src_layer, mem_layer, tile_query)

        # use only layers that actually have data for the tile
        roads = []
        for layer in sources:
            mem_layer = layer['alias']+'_'+tile
            if n_records(mem_layer) > 0:
                roads = roads + [mem_layer]

        # only run the integrate / erase etc if there is more than one road source
        if len(roads) > 1:
            # regenerate priority numbers, in case empty layers have been removed
            integrate_str = ';'.join([r+' '+str(i+1) for i,r in enumerate(roads)])
            # perform integrate, modifing extracted road data in place,
            # snapping roads within tolerance
            arcpy.Integrate_management(integrate_str, CONFIG['tolerance'])
            # start with the roads of top priority,
            in_layer = roads[0]
            # then loop through the rest of the roads
            for i in range(1, len(roads)):
                out_layer = 'temp_'+tile+'_'+str(i)
                # erase first layer or previous output with next roads layer
                arcpy.Erase_analysis(roads[i],
                                     in_layer,
                                     'temp_missing_roads_'+tile,
                                     '0.01 Meters')
                # merge the output missing roads with the previous input
                arcpy.Merge_management(["temp_missing_roads_"+tile, in_layer],
                                       out_layer)
                arcpy.Delete_management("temp_missing_roads_"+tile)
                in_layer = out_layer
            # write to output gdb
            copy_data(out_layer, os.path.join(tile_wksp, "roads_"+tile))
            # delete temp layers
            for i in range(1, len(roads)):
                arcpy.Delete_management("temp_"+tile+"_"+str(i))

        # append single road source to output
        elif len(roads) == 1:
            copy_data(roads[0], os.path.join(tile_wksp, "roads_"+tile))

        # if there aren't any roads, don't do anything
        elif len(roads) == 0:
            click.echo('No roads present in tile '+tile)

        # cleanup
        for layer in sources:
            if arcpy.Exists(layer["alias"]+"_"+tile):
                arcpy.Delete_management(layer["alias"]+"_"+tile)
        elapsed_time = time.time() - start_time
        click.echo("Completed "+tile+": "+str(elapsed_time))


@click.command()
@click.option('--source_csv', '-s', default=CONFIG['source_csv'],
              type=click.Path(exists=True), help=HELP['csv'])
@click.option('--n_processes', '-p', default=multiprocessing.cpu_count() - 1,
              help="Number of parallel processing threads to utilize")
@click.option("--tiles", "-t",
              help='Comma separated list of tiles to process',
              default=TILES)
def process(source_csv, n_processes, tiles):
    """ Process road integration
    """

    start_time = time.time()
    tiles = tiles.split(',')
    sources = read_csv(source_csv)
    # only use a source layer if it has a priority value
    sources = [s for s in sources if s['priority'] != 0]
    # split processing between multiple processes
    # n processes is equal to processess parmeter in config
    click.echo("Processing tiles")
    func = partial(integrate, sources)
    pool = multiprocessing.Pool(processes=n_processes)
    pool.map(func, tiles)
    pool.close()
    pool.join()

    elapsed_time = time.time() - start_time
    click.echo("All tiles complete in : "+str(elapsed_time))
    click.echo("Merging tiles to output...")
    # merge outputs to single output layer
    outputs = []
    for t in tiles:
        fc = os.path.join(CONFIG['temp_data'], 'tiles', 'temp_'+t+'.gdb', 'roads_'+t)
        if arcpy.Exists(fc):
            outputs = outputs + [fc]
    gdb, fc = os.path.split(CONFIG['output'])
    gdb_path, gdb = os.path.split(gdb)
    create_wksp(gdb_path, gdb)
    arcpy.Merge_management(outputs, CONFIG['output'])
    click.echo('Output ready in : ' + CONFIG['output'])


if __name__ == '__main__':
    process()
