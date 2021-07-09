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

## Usage

1. Manually download As Built Roads to `source_data/ABR.gdb/ABR_ROAD_SECTION_LINE`

2. Download all other sources and load all data to the postgres db:

        ./load.sh

3. Process all roads:

        ./process.sh

4. Dump output to file:

        ./dump.sh


## Duplications
As mentioned above, the analysis is very much an approximation. It works best in areas where roads are not duplicated between sources.
These diagrams illustrate a problematic sample area, showing three input road layers (green as highest priority) and the resulting output (using a 7m tolerance).

### three input layers
![inputs](img/roadintegrator_inputs.png)

### resulting output
![inputs](img/roadintegrator_output.png)

