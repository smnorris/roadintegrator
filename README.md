# roadintegrator

Collect various BC road data sources, preprocess and tile, then use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to merge the roads into a single layer.

Note that the road merging process is an approximation - the output should not be considered definitive. See [output](##output) below for more details.

Output is for Cumulative Effects reporting tools and similar road density analyses; for projects requiring a clean road network (routing, mapping, etc) please use the individual source road layers. 

## Requirements

- Python 2.7
- ArcGIS Desktop (with Advanced License, tested with v10.1)
- GDAL/OGR (tested with v2.2.1)
- PostgreSQL (tested with v10.1)
- PostGIS with [SFCGAL](http://postgis.net/2015/10/25/postgis_sfcgal_extension/) (tested with v2.4)

**NOTE**: as the script requires ArcGIS, it runs only on Windows.

## Setup

1. Ensure that Python 2.7 64 bit (and scripts) bundled with ArcGIS are available at the command prompt. Either check your PATH Environment variable via the Control Panel or open a 64 bit command prompt window and modify the PATH directly like this (modify the path based on your ArcGIS install path):

        set PATH="E:\sw_nt\Python27\ArcGISx6410.3";"E:\sw_nt\Python27\ArcGISx6410.3\Scripts";%PATH%

2. Ensure pip is installed, [install]((https://pip.pypa.io/en/stable/installing/)) if it is not.

3. (Optional) Consider installing dependencies to a virtual environment rather than to the system Python or your home directory:

         $ pip install virtualenv                   # if not already installed
         $ mkdir roadintegrator_venv
         $ virtualenv roadintegrator_venv
         $ roadintegrator_venv\Scripts\activate     # activate the env

4. Clone the repository:  
        
        git clone https://github.com/bcgov/roadintegrator.git

5. Using pip, install the required Python libraries:  
        
        cd roadintegrator
        pip install --user -r requirements.txt
        

6. Using the `pgxn` client (installed via `requirements.txt`, above), install the `lostgis` extension:

        $ pgxn install lostgis

        
## Configuration

### config.yml
To modify processing tolerances and default database/files/folders, edit `config.yml`. 

### sources.csv
To modify the source layers used in the analysis, edit the file referenced as `source_csv` in `config.yml`. The default source data list file is the provided `sources.csv`. This table defines all layers in the analysis and can be modified to customize the analysis. Note that order of the rows is not important, the script will sort the rows by the **hierarchy** column. Columns are as follows:

| COLUMN                 | DESCRIPTION                                                                                                                                                                            | 
|------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| 
| **manual_download**        | A value of `T` indicates that a direct download url is not available for the data. Download these sources manually to the downloads folder and give the file the same name as the layer's **alias**.
| **priority**               | An integer defining the priority of the source. Lower priority roads will be snapped to higher priority roads (within the specified tolerance). Sources required for processing but not included in the roads hierarchy (eg tiles) should be give a hierarchy value of `0`. 
| **name**                   | Full name of the source layer 
| **alias**                  | A unique underscore separated value used for coding the various road sources (eg `dra`)
|**source_table**            | Full schema.table name of source BCGW table
|**primary_key**             | The source layer's primary key
| **fields**                 | The fields in the source layer to retain in the output
| **url**                    | Download url for the data source
| **layer_in_file**          | The layer of interest within the downloaded file
| **query**                  | A SQL query defining the subset of data of interest from the given file/layer (SQLite dialect)
| **preprocess_operation**   | Pre-processing operation to apply to layer (`tile` and `roadpoly2line` are the only supported operations)
| **license**                | The license under which the data is distrubted

Note that only Province of BC data sources are supported for download.

## Usage

1. Download and consolidate all required data:
    
        $ python roadintegrator.py load

2. Preprocess (tile inputs and generate lines from RESULTS polygons):

        $ python roadintegratory.py preprocess

3. Run the road integration:

        $ python roadintegrator.py process

4. When processing is complete, find output layer in `output` gdb specified in `config.yml`


## Methodology

- download all required source data from DataBC Catalogue
- load all source data to PostGIS
- in PostGIS, preprocess source road layers, creating lines from RESULTS road polyons and tiling all sources
- dump sources road layers into a single gdb
- looping through tiles (20k or 250k):
    + use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to conflate the roads into a single layer based on hierarchy specified in `sources.csv`
    + with all linework within the tolerance of `Integrate` aligned in the various sources, remove lines present in higher priority sources from lower priority datasets using the `Erase` tool
    + merge the resulting layers into a single output roads layer for the given tile
- merge all tiles into a provincial roads layer

## Output
As mentioned above, the analysis is very much an approximation. It works best in areas where roads are not duplicated between sources.
These diagrams illustrate a problematic sample area, showing three input road layers (green as highest priority) and the resulting output (using a 7m tolerance). 

### three input layers
![inputs](img/roadintegrator_inputs.png)

### resulting output
![inputs](img/roadintegrator_output.png)

