# roadintegrator

Collect and combine various BC road data sources in order of priority.

When a lower priority road feature is within 7m (or otherwise specified) of a higher priority road, it is snapped to the the location of the higher priority road. Once all sources are snapped/integrated, roads from each source are added to the output in order of priority - if the road is not already present.


## Limitations and Caveats

The authoritative source for built roads in British Columbia is the [Digital Road Atlas](https://catalogue.data.gov.bc.ca/dataset/digital-road-atlas-dra-master-partially-attributed-roads). The process used in these scripts is NOT a comprehensive conflation/merge of the input road layers, it is a quick approximation. All outputs are specifically for cumulative effects and strategic level analysis - they should not be considered positionally accurate.

Several specific issues will lead to over-representation of roads:

- the same road present in different source layers will only be de-duplicated by the tool where the features are nearer than the specified tolerance, see [Duplications](#Duplications) below)
- roads are present in the tenure layers that have not been built
- roads may have been decomissioned, overgrown or become otherwise impassible

Additionally, the various road data sources are not 100% comprehensive, there may be roads present in the landscape that are included in the analysis/output product.

## Requirements

- PostgreSQL >= 13 (tested with v13.3)
- PostGIS >= 3.1
- Geos >= 3.9

## Installation

### Python dependencies

1. Install Anaconda or [miniconda](https://docs.conda.io/en/latest/miniconda.html)

2. Open a [conda command prompt](https://docs.conda.io/projects/conda/en/latest/user-guide/getting-started.html)

3. Clone the repository, navigate to the project folder, create and activate provided environment:

        git clone https://github.com/smnorris/roadintegrator.git
        cd roadintegrator

4. Edit the postgres connection environment variables in `environment.yml` to match your database connection as necessary.

5. Create and activate the environment:

        conda env create -f environment.yml
        conda activate roadintegrator

### Database

Optional - if you do not already have a local PostgreSQL 13 / PostGIS 3.1 database.

1. Download and install Docker using the appropriate link for your OS:
    - [MacOS](https://download.docker.com/mac/stable/Docker.dmg)
    - [Windows](https://download.docker.com/win/stable/Docker%20Desktop%20Installer.exe)

2. Get a Postgres docker image with a PostGIS 3.1 / Geos 3.9 enabled database:

        docker pull postgis/postgis:13-master

3. Create a container with the postgis image, using the database name and port specified by the `PGDATABASE` and `PGPORT` environment variables:

        # Linux/Mac

        docker run --name postgis \
          -e POSTGRES_PASSWORD=postgres \
          -e POSTGRES_USER=postgres \
          -e PG_DATABASE=$PGDATABASE \
          -p $PGPORT:5432 \
          -d postgis/postgis:13-master

        # Windows

        docker run --name postgis ^
          -e POSTGRES_PASSWORD=postgres ^
          -e POSTGRES_USER=postgres ^
          -e PG_DATABASE=%PGDATABASE% ^
          -p %PGPORT%:5432 ^
          -d postgis/postgis:13-master

4. Create the database

        psql -c "CREATE DATABASE roadintegrator" postgres

Above creates and runs a container called `postgis` with a postgres server and db available on the port specified by the $PGPORT environment variable (configurable in `environment.yml`)

As long as you don't remove this container, it will retain all the data you put in it. If you have shut down Docker or the container, start it up again with this command:

          docker start postgis


## Configuration


### sources.csv
To modify the source layers used in the analysis, edit the file referenced as `source_csv` in `config.yml`. The default source data list file is the provided `sources.csv`. This table defines all layers in the analysis and can be modified to customize the analysis. Note that order of the rows is not important, the script will sort the rows by the **priority** column. Columns are as follows:

| COLUMN                 | DESCRIPTION                                                                                                                                                                            |
|------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **priority**               | An integer defining the priority of the source. Lower priority roads will be snapped to higher priority roads (within the specified tolerance).
| **manual_download**        | 'Y' if the data must be manually downloaded
| **name**                   | Full name of the source layer
| **alias**                  | A unique underscore separated value used for coding the various road sources (eg `dra`)
| **source_table**           | Full SCHEMA.TABLE object name of source BCGW table
| **primary_key**            | The source layer's primary key
| **fields**                 | The fields in the source layer to retain in the output, in order to be written to output layer
| **url**                    | DataBC Catalogue URL
| **query**                  | A valid CQL or ECQL query for filtering the data (https://docs.geoserver.org/stable/en/user/tutorials/cql/cql_tutorial.html)
| **preprocess_operation**   | Pre-processing operation to apply to layer (`tile` and `roadpoly2line` are the only supported operations)

Note that this tool only supports downloading sources available through the DataBC Catalogue.

## Usage

1. Create the postgres database if it doesn't already exist:

        $ python 1_prep.py create-db

2. Download publicly accessible data:

        $ python 1_prep.py load

3. Manually download any sources that are not publicly accessible and load to the working database (using the alias specified in `sources.csv` with the suffix `_src`. For example:

        $ ogr2ogr \
          --config PG_USE_COPY YES \
          -f PostgreSQL \
          PG:"host=localhost user=postgres dbname=roadintegrator password=postgres" \
          -lco OVERWRITE=YES \
          -lco SCHEMA=public \
          -lco GEOMETRY_NAME=geom \
          -nln abr_src \
          source_data/ABR.gdb \
          ABR_ROAD_SECTION_LINE

4. Preprocess (tile inputs and generate linear features from polygon inputs):

        $ python 1_prep.py preprocess

5. Move the resulting `temp_data/prepped.gdb` to equivalent folder on a machine with ArcGIS 10.6/Python 2.7. and then run the road integration:

        C:\path\to\project> python 2_integrate.py

6. Move the resulting `temp_data/tiles` back to equivalent folder on the machine with Python 3 / GDAL etc and merge the tiled outputs in postgres:

        $ python 3_merge.py

7. Dump output `integrated_roads` layer to final .gdb. Note that this script does read `sources.csv` or `config.yml`, the script must be modified if any changes are made to input data and/or the postgres connection.

        $ ./4_dump.sh




## Duplications
As mentioned above, the analysis is very much an approximation. It works best in areas where roads are not duplicated between sources.
These diagrams illustrate a problematic sample area, showing three input road layers (green as highest priority) and the resulting output (using a 7m tolerance).

### three input layers
![inputs](img/roadintegrator_inputs.png)

### resulting output
![inputs](img/roadintegrator_output.png)

