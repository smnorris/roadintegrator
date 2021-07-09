# roadintegrator

Quckly merge various BC road data sources into a single layer.

## Sources


|Priority | Name                        | Table                        |
|---------|-----------------------------|------------------------------|
| 1 |[Digital Road Atlas (DRA)](https://catalogue.data.gov.bc.ca/dataset/digital-road-atlas-dra-master-partially-attributed-roads) | WHSE_BASEMAPPING.DRA_DGTL_ROAD_ATLAS_MPAR_SP |
| 2 | [Forest Tenure Road Section Lines](https://catalogue.data.gov.bc.ca/dataset/forest-tenure-road-section-lines) | WHSE_FOREST_TENURE.FTEN_ROAD_SECTION_LINES_SVW |
| 3 | [RESULTS - Forest Cover Inventory - roads](https://catalogue.data.gov.bc.ca/dataset/results-forest-cover-inventory) | WHSE_FOREST_VEGETATION.RSLT_FOREST_COVER_INV_SVW |
| 4 | As Built Roads (ABR) | WHSE_FOREST_TENURE.ABR_ROAD_SECTION_LINE |
| 5 | [OGC Petroleum Development Roads Pre-2006](https://catalogue.data.gov.bc.ca/dataset/ogc-petroleum-development-roads-pre-2006-public-version) | WHSE_MINERAL_TENURE.OG_PETRLM_DEV_RDS_PRE06_PUB_SP |
| 6 | [Oil and Gas Commission Road Segment Permits](https://catalogue.data.gov.bc.ca/dataset/oil-and-gas-commission-road-segment-permits) | WHSE_MINERAL_TENURE.OG_ROAD_SEGMENT_PERMIT_SP |
| 7 | [Oil and Gas Commission Road Right of Way Permits](https://catalogue.data.gov.bc.ca/dataset/oil-and-gas-commission-road-right-of-way-permits) | WHSE_MINERAL_TENURE.OG_ROAD_AREA_PERMIT_SP |

## Method

Roads are loaded to the output layer in order of decreasing priority. When a lower priority road feature is within 7m of an already loaded (higher priority road), it is snapped to the the location of the higher priority road and only the difference between the features is added to the output.

## Limitations and Caveats

The authoritative source for built roads in British Columbia is the [Digital Road Atlas](https://catalogue.data.gov.bc.ca/dataset/digital-road-atlas-dra-master-partially-attributed-roads). The process used in these scripts **IS NOT A COMPRENSIVE CONFLATION/MERGE** of the input road layers, it is a quick approximation. All outputs are specifically for cumulative effects and strategic level analysis - they should not be considered positionally accurate.

Several specific issues will lead to over-representation of roads:

- the same road present in different source layers will only be de-duplicated by the tool where the features are nearer than the specified tolerance, see [Duplications](#Duplications) below)
- roads are present in the tenure layers that have not been built
- roads may have been decomissioned, overgrown or become otherwise impassible

Additionally, the various road data sources are not 100% comprehensive, there may be roads present in the landscape that are not included in the analysis and output product.


## Installation

### Processing environment

1. Install Anaconda or [miniconda](https://docs.conda.io/en/latest/miniconda.html)

2. Open a [conda command prompt](https://docs.conda.io/projects/conda/en/latest/user-guide/getting-started.html)

3. Clone the repository, navigate to the project folder, create and activate provided environment:

        git clone https://github.com/smnorris/roadintegrator.git
        cd roadintegrator

4. If necessary, edit the postgres connection environment variables in `environment.yml` to match your database connection parameters (the provided default is set to `localhost` with port `5435` to avoid collision with existing local databases).

5. Create environment/load dependencies, and activate the environment:

        conda env create -f environment.yml
        conda activate roadintegrator

### Database

The analysis requires:

- PostgreSQL >= 13.3
- PostGIS >= 3.1
- GEOS >= 3.9

If you do not already have a database meeting these requirements, use Docker to quickly set one up:

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

Above creates and runs a container called `postgis` with a postgres server and db available on the port specified by the `$PGPORT` environment variable (configurable in `environment.yml`)

As long as you do not remove this container, it will retain all the data you put in it. If you have shut down Docker or the container, start it up again with this command:

          docker start postgis

## Usage

1. Manually extract `WHSE_FOREST_TENURE.ABR_ROAD_SECTION_LINE` from BCGW, save to file `source_data/ABR.gdb/ABR_ROAD_SECTION_LINE`

2. Download all other sources and load all data to the postgres db:

        ./load.sh

3. Process all roads:

        ./process.sh

4. Dump output to file:

        ./dump.sh


## Duplications
As mentioned above, this analysis is very much a rough approximation. It works well in areas where roads are not duplicated between sources or where source road networks are near-coincident.

These diagrams illustrate a problematic sample area, showing three input road layers (green as highest priority) and the resulting output (using a 7m tolerance).

### three input layers
![inputs](img/roadintegrator_inputs.png)

### resulting output
![inputs](img/roadintegrator_output.png)

