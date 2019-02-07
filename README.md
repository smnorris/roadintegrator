# roadintegrator

Collect various BC road data sources, preprocess and tile, then use the ArcGIS
[Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000)
to merge the roads into a single layer.

Note that the road merging process is an approximation - the output should not
be considered definitive. See [output](#output) below for more details.

Output is for Cumulative Effects reporting tools and similar road density analyses;
for projects requiring a clean road network (routing, mapping, etc) please use
the individual source road layers.

## Requirements

Two scripts are provided, each has different requirements:

For `1_prep.py`:

- Python 3 (tested with v3.7)
- GDAL/OGR (tested with v2.4.0)
- PostgreSQL (tested with v10.6)
- PostGIS with [SFCGAL](http://postgis.net/2015/10/25/postgis_sfcgal_extension/) (tested with v2.5)

For `2_integrate.py`:

- ArcGIS Desktop (tested with v10.6)
- Python 2


## Setup

1. On data preparation machine (with GDAL, Postgres), clone the repository,
create virtualenv, install Python dependencies:

        $ git clone https://github.com/bcgov/roadintegrator.git
        $ cd roadintegrator
        $ virtualenv venv
        $ venv\Scripts\activate
        $ pip install -r requirements.txt

2. On ArcGIS machine, clone the repositiory, install dependencies. Also, the tool requires the [64bit ArcGIS Python](http://desktop.arcgis.com/en/arcmap/latest/analyze/executing-tools/64bit-background.htm) - integrate will fail with topology errors using the 32bit Python. The PATH below is for ArcGIS 10.6 on a GTS server, modify as required:

        C:\> git clone https://github.com/smnorris/roadintegrator.git
        C:\> cd roadintegrator
        C:\roadintegrator> pip install --user click
        C:\roadintegrator> pip install --user pyaml
        C:\roadintegrator> SET PATH="E:\sw_nt\Python27\ArcGISx6410.6";"E:\sw_nt\Python27\ArcGISx6410.6\Scripts";%PATH%


## Configuration

### config.yml
To modify processing tolerances and default database/files/folders, edit `config.yml`.

### sources.csv
To modify the source layers used in the analysis, edit the file referenced as `source_csv` in `config.yml`. The default source data list file is the provided `sources.csv`. This table defines all layers in the analysis and can be modified to customize the analysis. Note that order of the rows is not important, the script will sort the rows by the **hierarchy** column. Columns are as follows:

| COLUMN                 | DESCRIPTION                                                                                                                                                                            |
|------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **priority**               | An integer defining the priority of the source. Lower priority roads will be snapped to higher priority roads (within the specified tolerance). Sources required for processing but not included in the roads hierarchy (eg tiles) should be give a hierarchy value of `0`.
| **name**                   | Full name of the source layer
| **alias**                  | A unique underscore separated value used for coding the various road sources (eg `dra`)
| **source_table**           | Full schema.table name of source BCGW table
| **primary_key**            | The source layer's primary key
| **fields**                 | The fields in the source layer to retain in the output
| **url**                    | Download url for the data source
| **query**                  | A valid CQL or ECQL query for filtering the data (https://docs.geoserver.org/stable/en/user/tutorials/cql/cql_tutorial.html)
| **preprocess_operation**   | Pre-processing operation to apply to layer (`tile` and `roadpoly2line` are the only supported operations)

Note that this tool only supports downloading sources available through the DataBC Catalogue.

## Usage

1. Create the postgres database if it doesn't already exist:

        $ python 1_prep.py create-db

2. Download publicly accessible data:

        $ python 1_prep.py load

3. Manually download any sources that are not publicly accessible and load to the working database.

4. Preprocess (tile inputs and generate linear features from polygon inputs):

        $ python 1_prep.py preprocess

5. If required, manually copy the prepped data (`prepped.gdb` in folder noted as `temp_data` in `config.yml`) to the same `temp_data` folder on the ArcGIS machine, then run the road integration:

        C:\path\to\project> python 2_integrate.py

See `--help` for each command to view available options. For example:

```
$ python 1_prep.py load --help
Usage: 1_prep.py load [OPTIONS]

  Download data, load to postgres

Options:
  -s, --source_csv PATH  Path to csv that lists all input data sources
  -a, --alias TEXT       The 'alias' key identifing the source of interest,
                         from source csv
  --force_refresh        Force re-download
  --help                 Show this message and exit.
```

When processing is complete, find output layer in `output` gdb specified in `config.yml`


## Methodology

- download all required source data from DataBC Catalogue
- load all source data to PostGIS
- in PostGIS, preprocess source road layers, creating lines from input road polyons and tiling all sources
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

