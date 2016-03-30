"""
road_integrator.py

Feb 2015, snorris

Aggregates specified roads into a single layer by eliminating duplicate roads 
within specified tolerance.

Methodology taken directly from:
Q:\projects\clients_new\mnro\Road AA\Data\Roads CE Toolbox Final.tbx\Roads Integrated Model


Command line usage:

# extract source data

python road_integrator.py -e

# with source data extracted, run a single tile

python road_integrator.py -t 082E055

# run for all tiles with NULL start time in road_status table on GEOPRD
# (ie, reset this table to do a provincial run)
# call this from multiple command windows to speed the process, then 
# merge the resulting output layers. Outputs are written to file
# 'RoadsOutput_<j>.gdb' where j corresponds to job number provided  

python road_integrator.py -j 1
"""

import sys
import os
from datetime import date
import csv

import click
import sqlalchemy
import arcpy

# point to db connections
BCGW = r"Database Connections\BCGW_pwd.sde"
GEOPRD = r"oracle+cx_oracle://sinorris:Rockslide1@GEOPRD"

# convenient to have SR for creating new feature classes 
BC_ALBERS_SR = "PROJCS['NAD_1983_BC_Environment_Albers',\
    GEOGCS['GCS_North_American_1983',\
    DATUM['D_North_American_1983',SPHEROID['GRS_1980',\
    6378137.0,298.257222101]],PRIMEM['Greenwich',0.0],\
    UNIT['Degree',0.0174532925199433]],\
    PROJECTION['Albers'],\
    PARAMETER['False_Easting',1000000.0],\
    PARAMETER['False_Northing',0.0],\
    PARAMETER['Central_Meridian',-126.0],\
    PARAMETER['Standard_Parallel_1',50.0],\
    PARAMETER['Standard_Parallel_2',58.5],\
    PARAMETER['Latitude_Of_Origin',45.0],\
    UNIT['Meter',1.0]];IsHighPrecision"

# arc type introspection doesn't match required types for creating a new field
ARC_TYPE_LOOKUP = {"String": "TEXT",
                   "SmallInteger": "SHORT",
                   "Single": "FLOAT",
                   "Integer": "LONG",
                   "Double": "DOUBLE",
                   "Date": "DATE",
                   # map oids to integers for purposes of this script, as TRIM
                   # road OIDs are used... TRIM doesn't seem to have a nice pk
                   "OID": "LONG"}


def create_log(db):
    """
    create a table logging progress in the event something bails
    
    There are far faster/more efficient ways to do this but my oracle is rusty
    """
    sql = """CREATE TABLE road_status 
            ( map_tile varchar2(10),
             priority number,
             output_file varchar2(100),
             start_time TIMESTAMP,
             end_time TIMESTAMP,
             bail_time TIMESTAMP)"""
    db.execute(sql)
    # insert tile values 
    # this takes a while, speed by wrapping into a single transaction?
    for tile in db.execute("""SELECT map_tile 
                              FROM whse_basemapping.bcgs_20k_grid@idwprod1
                           """).fetchall():
        db.execute("INSERT INTO road_status (map_tile) VALUES (:1)",tile)


def reset_log(db):
    """
    reset the road_status table in the event full re-processing is required
    """
    db.execute("UPDATE road_status SET start_time = NULL")
    db.execute("UPDATE road_status SET end_time = NULL")
    db.execute("UPDATE road_status SET output_file = NULL")


def get_tile(db):
    """
    get the next tile to be processed
    """
    sql = """SELECT * FROM
             (SELECT map_tile 
             FROM road_status
             WHERE start_time IS NULL
             ORDER BY map_tile)
             WHERE ROWNUM = 1
          """
    tile = db.execute(sql).fetchone()
    if tile:
        return tile[0]
    else:
        return None

def update_tile(db, tile, outputFile, status="START"):
    """
    note that the tile has been processed
    """
    sql = """UPDATE road_status
             SET {f}_time = CURRENT_TIMESTAMP
             WHERE map_tile = :1
          """.format(f=status.lower())
    db.execute(sql, tile)
    sql = """UPDATE road_status
             SET output_file = :1
             WHERE map_tile = :2
          """
    db.execute(sql, (outputFile, tile))
    
    
def initialize_output(outFC, srcWksp, roadlist):
    """
    create empty feature class for writing outputs
    """
    wksp, fc  = os.path.split(outFC)
    # set workspace to in_memory in an attempt to speed things up a bit
    arcpy.env.workspace = 'in_memory' #wksp
    # overwrite any existing outputs
    arcpy.env.overwriteOutput = True
    
    # create output feature class
    if not arcpy.Exists(outFC):
        datalist = read_datalist(roadlist)
        arcpy.CreateFeatureclass_management(wksp, fc,
                                            "POLYLINE", "", "", "",
                                            BC_ALBERS_SR)
        # add all columns noted in source .csv
        for road in datalist:
            # if the primary key is remapped to a new name in the source .csv,
            # handle that here
            if road["new_primary_key"]:
                road["primary_key"] = road["new_primary_key"]
            fields = clean_fieldlist(road["primary_key"])+clean_fieldlist(road["fields"])
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
        

def clean_fieldlist(inString):
    """
    Return a python list from a comma separated list of fields,
    removing any spaces from ends of input
    """
    return [s.strip() for s in inString.split(",")]


def read_datalist(inFile):
    """
    Read csv holding input data parameters, return a list of dicts
    Data sources are all presumed to be tables within BCGW
    """
    datalist = [row for row in csv.DictReader(open(inFile,'rb'))]
    datalist = sorted(datalist, key=lambda data: data["priority"])
    return datalist


def pull_items(inData, fieldList=None):
    '''
    Given an input data source and a comma separated string of field names,
    return a fieldinfo object that includes only the fields listed as VISIBLE
    Given no fields as input returns all fields as VISIBLE
    '''
    fieldList = clean_fieldlist(fieldList)
    # create a field info object
    fieldInfo = arcpy.FieldInfo()
    # iterate through fields
    inputfields = [field.name for field in arcpy.ListFields(inData) if not field.required]
    for index in range(len(inputfields)):
        if fieldList:
            if inputfields[index] in fieldList:
                fieldInfo.addField(inputfields[index],
                                   inputfields[index], "VISIBLE","")
            else:
                fieldInfo.addField(inputfields[index],
                                   inputfields[index], "HIDDEN","")
        else:
            fieldInfo.addField(inputfields[index],
                               inputfields[index], "VISIBLE","")
    return fieldInfo


def copy_data(sourcePath, destPath, query=None, fieldList=None, aoi=None,
              overwrite=False, clip=False, tableOnly=False):
    """
    Extract a data layer that has a valid arccatalog path to specified location
    Options:
    - query     - return a subset matching sql where clause
    - fieldList - Comma-delimited list of fields to copy to the new layer.
    - aoi       - return only geometries that intersect specified layer (all features)
    - overwrite - boolean overwrite flag
    - clip      - clip output geometries to the aoi layer
    """
    # make sure output does not already exist if overwrite is not enabled
    if not overwrite and arcpy.Exists(destPath):
        print 'copy_data error - output exists:' + destPath
        return
    else:
        # set to overwrite (as the layer existence is already checked above)
        arcpy.env.overwriteOutput = True
        # build fieldinfo object
        if fieldList:
            fieldinfo = pull_items(sourcePath, fieldList)
        else:
            fieldinfo = None
        
        # if not copying geometry
        if tableOnly == True:
            arcpy.MakeTableView_management(sourcePath, "table_view",
                                           query, "", fieldinfo)
            arcpy.CopyRows_management("table_view", destPath)
        # get spatial data
        else:
            # make feature layer
            arcpy.MakeFeatureLayer_management(sourcePath,
                                              'featureLayer',
                                              query,
                                              "",
                                              fieldinfo)
            # just clip data if so specified
            if aoi and clip:
                arcpy.Clip_analysis('featureLayer', aoi, destPath)
            else:
                # select features within aoi if given
                if aoi:
                    arcpy.SelectLayerByLocation_management('featureLayer',
                                                           "INTERSECT", aoi)
                # copy features
                outpath, outfile = os.path.split(destPath)
                if not outpath:
                    outpath = arcpy.env.workspace
                arcpy.FeatureClassToFeatureClass_conversion("featureLayer",
                                                            outpath, outfile)
        print 'copy_data: '+sourcePath+" copied to "+destPath


def tile_list(fc, field, query=None):
    """
    Return distinct tile names, filtering by query
    """
    return list(set([row[0] for row in arcpy.da.SearchCursor(fc, 
                                                             field, 
                                                             where_clause=query)]))


def get_count(featureClass):
    """
    Why would I want to specify getOutput(0) each time?
    """
    result = arcpy.GetCount_management(featureClass)
    return int(result.getOutput(0))


def update_column(table, column, data, sql=None):
    """
    The update cursor syntax is a bit verbose for the common use case.
    When applying a basic update or remap to a single column, simply specifiy
    table, column and new data as either a constant or a remapping dict.

    This will of course break down if you supply a value that doesn't match
    the column type.

    To apply the update to just a subset of records, supply a where clause
    http://resources.arcgis.com/en/help/main/10.2/index.html#//002z0000001r000000
    """
    with arcpy.da.UpdateCursor(table, [column], sql) as cursor:
        for row in cursor:
            if type(data) is dict:
                for value in dataDict.keys():
                    if row[0] == value:
                        row[0] = dataDict[value]
            else:
                row[0] = data
            cursor.updateRow(row)


def get_source_data(wksp, roadlist):
    """
    To help speed processing, rather than pull data from sources piece by piece,
    simply copy everything and overlay with tiles up-front 
    """
    # create workspace if it doesn't exist
    if not arcpy.Exists(wksp):
        p, f = os.path.split(wksp)
        arcpy.CreateFileGDB_management(p, f)
        
    # extract tiles, intersects below seem to need a local copy
    if not arcpy.Exists("bcgs_20k_grid"):
        copy_data(os.path.join(BCGW, "WHSE_BASEMAPPING.BCGS_20K_GRID"),
                  os.path.join(wksp, "bcgs_20k_grid"))
    
    # extract each road layer
    for roads in read_datalist(roadlist):
        if not arcpy.Exists(os.path.join(wksp,roads["alias"])):
            print 'Copying to local .gdb: '+roads["alias"]
            
            # for everything but trim roads, overlay with 20k tiles
            if roads["alias"] != 'trim':
                copy_data(os.path.join(roads["path"], roads["table"]),
                          os.path.join(wksp, roads["alias"]+"_prelim"),
                          roads["query"])
                print 'Cutting with 20k tiles: '+roads["alias"]
                arcpy.Intersect_analysis([os.path.join(wksp, 
                                                       roads["alias"]+"_prelim"),
                                          os.path.join(wksp, "bcgs_20k_grid")],
                                         os.path.join(wksp, roads["alias"]))
                print 'Indexing by mapsheet: '+roads["alias"]
                arcpy.AddIndex_management(os.path.join(wksp, roads["alias"]), 
                                          "MAP_TILE", 
                                          roads["alias"]+'map_tile_idx')
                arcpy.Delete_management(os.path.join(wksp, 
                                                     roads["alias"]+"_prelim"))
            
            # for trim, simply copy
            else:
                copy_data(os.path.join(roads["path"], roads["table"]),
                          os.path.join(wksp, roads["alias"]),
                          roads["query"])
                arcpy.AddIndex_management(os.path.join(wksp, roads["alias"]), 
                                          "BCGS_TILE", 'trim_bcgs_tile_idx')
            
            # add date and source
            print 'Noting source and extraction date within '+roads["alias"]
            arcpy.AddField_management(os.path.join(wksp, roads["alias"]), 
                                      "BCGW_SOURCE", "TEXT","", "", "255")
            arcpy.AddField_management(os.path.join(wksp, roads["alias"]), 
                                      "BCGW_EXTRACTION_DATE", 
                                      "TEXT","", "", "255")
            if roads["alias"] != "results":
                update_column(os.path.join(wksp, roads["alias"]), 
                              "BCGW_SOURCE", roads["table"])
            # results roads BCGW source should be noted 
            else:
                update_column(os.path.join(wksp, roads["alias"]), 
                              "BCGW_SOURCE", 
                              "WHSE_FOREST_VEGETATION.RSLT_FOREST_COVER_INV_SVW")
            update_column(os.path.join(wksp, roads["alias"]),
                          "BCGW_EXTRACTION_DATE", date.today().isoformat())
        
            
def process_roads(roadlist, outFC, tolerance, job):
    """
    From provided list of road data, shift lower priority roads within specified
    tolerance of higher priority roads to match position of higher priority roads.
    """
    roadSources = read_datalist(roadlist)
    # use only roads layers that actually have data
    roadSources = [road for road in roadSources if get_count(road["alias"]+"_"+job) > 0]

    # repair geometry for each road layer
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
     

def get_roads(srcPath, tileval, roadlist, job):
    """
    pull roads data for given tile into memory
    """
    for roads in read_datalist(roadlist):        
        # trim roads area special case, the source doesn't seem to have
        # a unique pk. Create one in source before processing and retain it instead
        if roads["new_primary_key"]:
            roads["primary_key"] = roads["new_primary_key"]
        if roads["alias"] == 'trim':
            query = """BCGS_TILE = '{t}'""".format(t=tileval)
        else:
            query = """MAP_TILE = '{t}'""".format(t=tileval)
        
        # extract the specified road data
        copy_data(os.path.join(srcPath, roads["alias"]),
                  roads["alias"]+"_"+job,
                  query,
                  fieldList=roads["primary_key"]+","+roads["fields"]+",BCGW_SOURCE,BCGW_EXTRACTION_DATE", 
                  overwrite=False)



            


@click.command()
@click.option('--job', '-j', 
              default=1, 
              help='Job number, used as suffix for ouput gdb')
@click.option('--extract', '-e', 
              is_flag=True, 
              help="Extract input data")
@click.option('--usertile', '-t',  
              help="Specify BCGS 20k tile to run")
def road_integrator(job, extract, usertile):    
    # when running script in several different processes at once,
    # specifiy the job number so that output from individual process gets 
    # directed to its own output .gdb (and intermediate data)
    job = str(job)
    
    # Define locations to read, write outputs
    path = r"T:\roads_testing"
    srcWksp = os.path.join(path, "RoadSources.gdb")
    #srcWksp = os.path.join(path, "archive", "RoadSources_bk.gdb")
    outputgdb = "RoadsOutput_"+job+".gdb"
    wksp = os.path.join(path, outputgdb) 
    outFC = os.path.join(wksp, "AllRoads")
    
    # Define input parameters
    roadlist = os.path.join(path, "inputs.csv")  # list of roads to use
    tolerance = "7 meters"                       # (for the integrate function)
    
    # make full copy of source data (everything, including geometries
    if extract:
        get_source_data(srcWksp, 
                        roadlist)
    
    # if not running extract, run the integration
    else:
        # connect to database holding table that logs progress
        engine = sqlalchemy.create_engine(GEOPRD)
        conn = engine.connect()

        # create the output gdb if it doesn't exist
        if not arcpy.Exists(wksp):
            arcpy.CreateFileGDB_management(path, outputgdb)
        
        # create output FC
        initialize_output(outFC, srcWksp, roadlist)
        
        # get the first tile to be run
        if not usertile:
            tile = get_tile(conn)
        else:
            tile = usertile
        
        # continue running until there are no tiles left
        while tile:
            print "Processing tile "+tile
            # note that this tile has been started
            update_tile(conn, tile, outputgdb, "start")
            # get road data
            get_roads(srcWksp, tile, roadlist, job)
            # integrate / aggregate roads
            process_roads(roadlist, outFC, tolerance, job)            
            # note success
            update_tile(conn, tile, outputgdb, "end")
            # get a new tile if tile option wasn't specified
            if not usertile:
                tile = get_tile(conn)
            # otherwise, stop here
            else:
                tile = None
        print 'No tiles remaining'
        

if __name__ == "__main__":
    road_integrator()