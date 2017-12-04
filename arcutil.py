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

import os
import uuid

import arcpy


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
