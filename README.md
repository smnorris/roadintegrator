# roadintegrator

Collect various BC road data sources, preprocess and tile, then use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to merge the roads into a single layer.

Note that the road merging process is an approximation - the output should not be considered definitive. Output is for Cumulative Effects reporting tools and similar road density analyses; for projects requiring a clean road network please use the individual source road layers.

## Requirements

- Python 2.7
- ArcGIS Desktop (tested with v10.3)
- ArcGIS 64 bit background geoprocessing add-on
- GDAL/OGR (tested with v2.2.1)
- PostgreSQL (tested with v10.1)
- PostGIS with [SFCGAL](http://postgis.net/2015/10/25/postgis_sfcgal_extension/) (tested with v2.4)

**NOTE**: as the `integrate` portion of the script requires ArcGIS, it runs only on Windows.

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
        

## Configuration

### config.yml
To modify processing tolerances and default database/files/folders, edit `config.yml`. 

### sources.csv
To modify the source layers used in the analysis, edit the file referenced as `datalist` in `config.yml`. The default datalist file is the provided `sources.csv`. This table defines all layers in the analysis and can be modified to customize the analysis. Note that order of the rows is not important, the script will sort the rows by the **hierarchy** column. Columns are as follows:

| COLUMN                 | DESCRIPTION                                                                                                                                                                            | 
|------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| 
| **priority**              | An integer defining the priority of the source. Lower priority roads will be snapped to higher priority roads (within the specified tolerance). Sources required for processing but not included in the roads hierarchy (eg tiles) should be give a hierarchy value of `0`. 
| **name**                   | Full name of the source layer 
| **alias**                  | A unique underscore separated value used for coding the various road sources (eg `dra`)
|**primary_key**             | The source layer's primary key
| **fields**                 | The fields in the source layer to retain in the output
| **url**                    | Download url for the data source
| **layer_in_file**          | The layer of interest within the downloaded file
| **query**                  | A SQL query defining the subset of data of interest from the given file/layer (SQLite dialect)
| **metadata_url**           | URL for metadata reference
| **info_url**               | Background/info url in addtion to metadata (if available)
| **preprocess_operation**   |
| **license**                | The license under which the data is distrubted


## Usage

1. Download and consolidate all required data:
    
        $ python roadintegrator.py load

2. Generate road lines from RESULTS roads polygons, see results_roads_lines/README.md

2. Modify configuration files as required. Changing the path to the ResultsRoads layer generated in setup above will likely be required:
    - `road_inputs.csv` - definitions (layer, query, included attributes, etc) for all inputs to analysis
    - `tiles.csv` - list of tiles to process (250k or 20k, 250 works well)
    - `config.yml` - misc config options (number of cores, grid to tile by)

3. Extract and prepare source data, writing to working folder on TEMP (as specified in `config.yml`):
`python roadintegrator.py extract`
Consider manually backing up the extract .gdb to a network drive in event of server reboot during processing.

4. Run the integration/conflation job:
`python roadintegrator.py integrate`

5. When processing is complete, copy output layer from `out.gdb` workspace on TEMP to desired location on a network drive.

**NOTE** *The integrate command spawns as many processess as specified in `config.yml`! You can potentially consume a very significant portion of a server's resources. Please be aware of other users and only run large multiprocessing jobs during non-peak hours.*

## Methodology

- create lines from RESULTS road polyons using PostGIS (see [results_road_lines](results_road_lines))
- consolidate all road sources noted in `road_inputs.csv` into a single gdb
- for each tile noted in tiles.csv (all 250k tils):
    + use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to conflate the roads into a single layer based on input data priorities specified in `road_inputs.csv`
    + with all linework within the tolerance of `Integrage` aligned in the various sources, remove lines present in higher priority sources from lower priority datasets using the `Erase` tool
    + merge the resulting layers into a single output roads layer for the given tile
- merge all tiles into a provincial roads layer

## Performance

Integrate command only, 250k tiles:

6 cores: 21.75min;
8 cores: 16.9min;
10 cores: 14.9min;

## Todo

- multi core extract for more speed

