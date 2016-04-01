import os
import csv
import tempfile
import uuid

import arcpy

# Nice to have handy
BC_ALBERS ="""
PROJCS['NAD_1983_BC_Environment_Albers',
GEOGCS['GCS_North_American_1983',
DATUM['D_North_American_1983',SPHEROID['GRS_1980',
6378137.0,298.257222101]],PRIMEM['Greenwich',0.0],
UNIT['Degree',0.0174532925199433]],
PROJECTION['Albers'],
PARAMETER['False_Easting',1000000.0],
PARAMETER['False_Northing',0.0],
PARAMETER['Central_Meridian',-126.0],
PARAMETER['Standard_Parallel_1',50.0],
PARAMETER['Standard_Parallel_2',58.5],
PARAMETER['Latitude_Of_Origin',45.0],
UNIT['Meter',1.0]];IsHighPrecision
"""

def get_fields(layer):
    """
    Return a list of non-arc fields in the specified source
    Not extensively tested, the required attribute may not be a reliable filter
    """
    return [field.name for field in arcpy.ListFields(layer)
            if not field.required and not field.type == "Geometry"]


def clean_fieldlist(in_string):
    """
    Return a python list from a comma separated list of fields,
    removing any spaces from ends of input
    """
    return [s.strip() for s in in_string.split(",")]


def arc_to_csv(in_table, out_file, field_list=None):
    """
    Just say no to exporting to .dbf. The 80s are long gone.
    Oddly, there is no arcpy tool for writing to csv, so roll our own here.
    Note that this dumps only attributes, not geometry.
    To dump *everything* to csv, including geometry, use the spatial statistics
    tool: arcpy.ExportXYv_stats
    (thanks to matt wilkie (@maphewyk) for pointing this out)
    """
    # make sure input fieldList is clean, no spaces between the commas plz
    if field_list:
        field_list = clean_fieldlist(field_list)

    src = arcpy.SearchCursor(in_table)
    # use only fields of interest
    fields = [f.name for f in arcpy.ListFields(in_table)]
    if field_list:
        fields = [f for f in fields if f in field_list]
    data = [fields, ]
    for row in src:
        data.append([row.getValue(field) for field in fields])
    with open(out_file, 'wb') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerows(data)


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
                                   inputfields[index].lower(), "VISIBLE", "")
            else:
                fieldInfo.addField(inputfields[index],
                                   inputfields[index], "HIDDEN", "")
        else:
            fieldInfo.addField(inputfields[index],
                               inputfields[index], "VISIBLE", "")
    return fieldInfo


def copy_data(sourcePath, destPath, query=None, fieldList=None, aoi=None,
              overwrite=False, clip=False, tableOnly=False):
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
        #print('copy_data: ' + sourcePath + " copied to " + destPath)


def create_bcgw_connection(usr, pwd):
    """
    Create a BCGW connection
    """
    tempPath = tempfile.gettempdir()
    tempConnectionFile = "TempBCGWConnection.sde"
    bcgw = os.path.join(tempPath, tempConnectionFile)
    # create connection only if it doesn't exist
    if not os.path.exists(bcgw):
        arcpy.CreateArcSDEConnectionFile_management(tempPath,
                                                tempConnectionFile,
                                                "slkux1.env.gov.bc.ca",
                                                "5153",
                                                "IDWPROD1",
                                                "DATABASE_AUTH",
                                                usr,
                                                pwd)
    return bcgw


def read_datalist(inFile):
    """
    Read a csv, returning data as a list of key/value pairs.
    """
    datalist = [row for row in csv.DictReader(open(inFile, 'rb'))]
    return datalist


def create_wksp(path, gdb):
    """
    Create a .gdb workspace in given path
    """
    wksp = os.path.join(path, gdb)
    # create the workspace if it doesn't exist
    if not arcpy.Exists(wksp):
        arcpy.CreateFileGDB_management(path, gdb)
    return os.path.join(path, gdb)


def remap(table, remapdict, sql=None):
    """
    Remap values in a table/layer based on provided dictionary and query

        >>> import arcutil as aut
        >>> newvalues = {"a": 777, "b": 325, "c": "!d!"}
        >>> aut.remap("mytable", newvalues, "a = 888")

    In this example, column c is set to column d.

    To apply the update to just a subset of records, supply a where clause
    http://resources.arcgis.com/en/help/main/10.2/index.html#//002z0000001r000000

    Arc attempts to type match to the target columns but things will break down
    if they aren't compatible.

    Expressions are not supported - if making calculations based on a source
    field, use the update cursor or calculatefield directly.
    """
    targetFields = remapdict.keys()
    sourceIndex = {}
    sourceFields = []
    # build an index that links source column to target column
    n = 0
    for t in targetFields:
        if "!" in str(remapdict[t]):
            sourceIndex[t] = n
            sourceFields.append(remapdict[t].replace("!", ""))
            n+=1
    # make sure we aren't trying to update a column that is noted as a source
    if sourceFields:
        for f in sourceFields:
            if f in targetFields:
                return "Invalid input. Source fields (denoted with '!') cannot be targets"
    fields = targetFields+sourceFields
    with arcpy.da.UpdateCursor(table, fields, sql) as cursor:
        nTargets = len(targetFields)
        targetNames = cursor.fields[:len(targetFields)]
        if sourceFields:
            sourceNames = cursor.fields[len(targetFields):]
        for row in cursor:
            if not sourceFields:
                cursor.updateRow([remapdict[col] for col in targetNames])
            else:
                newRow = []
                for col in targetNames:
                    if "!" not in remapdict[col]:
                        newRow.append(remapdict[col])
                    else:
                        newRow.append(row[nTargets + sourceIndex[col]])
                for i, col in enumerate(sourceNames):
                    newRow.append(row[nTargets + i])
                cursor.updateRow(tuple(newRow))


def check_projection(wksp, prj):
    """
    Ensure that all layers in provided workspace are in specified projection
    """
    #projectionName = "NAD_1983_BC_Environment_Albers"
    projectionName = os.path.splitext(os.path.basename(prj))[0]

    ow = arcpy.env.workspace
    arcpy.env.workspace = wksp
    # get a list of all feature classes
    layers = arcpy.ListFeatureClasses("", "Polygon")
    for layer in layers:
        dsc = arcpy.Describe(layer)
        if dsc.spatialReference.Name != projectionName:
            print("Reprojecting "+layer+" to "+projectionName)
            sr = arcpy.SpatialReference(prj)
            arcpy.Project_management(layer, layer+"_alb", sr)
            arcpy.Delete_management(layer)
            arcpy.Rename_management(layer+"_alb", layer)
    arcpy.env.workspace = ow


def add_bcgs_index(inLayer,
                   outLayer,
                   tiles="Database Connections\BCGW.sde\WHSE_BASEMAPPING.BCGS_20k_GRID",
                   tile_column="MAP_TILE"):
    """
    An indexed map_tile column can be FAR faster at finding things than a
    spatial index. Overlay input layer with specified tiles and index result.
    """
    arcpy.Intersect_analysis([inLayer, tiles], outLayer)
    arcpy.AddIndex_management(outLayer, tile_column,
                              os.path.split(outLayer)[0] + "_{c}_idx".format(c=tile_column.lower()))
    return outLayer


def repair_all(wksp):
    ow = arcpy.env.workspace
    arcpy.env.workspace = wksp
    layers = arcpy.ListFeatureClasses("")
    for layer in layers:
        arcpy.RepairGeometry_management(layer)
    arcpy.env.workspace = ow


def get_grid(ingrid, outpath, gridname):
    """Download grid from BCGW"""
    outgrid = os.path.join(outpath, gridname)
    copy_data(ingrid,
              outgrid,
              fieldList="MAP_TILE")
    arcpy.AddField_management(outgrid, "bcgs_20k_grid", "TEXT", "", "", 32)
    arcpy.CalculateField_management(outgrid,
                                    "bcgs_20k_grid",
                                    "!MAP_TILE!",
                                    "PYTHON_9.3")
    arcpy.DeleteField_management(outgrid, "MAP_TILE")
    return outgrid
