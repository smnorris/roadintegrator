# roadintegrator

Quckly merge various BC road data sources into a single layer.

## Sources


|Priority | Name                        | Table                        |
|---------|-----------------------------|------------------------------|
| 1 |[Digital Road Atlas (DRA)](https://catalogue.data.gov.bc.ca/dataset/digital-road-atlas-dra-master-partially-attributed-roads) | WHSE_BASEMAPPING.TRANSPORT_LINE (*from DRA ftp*) |
| 2 | [Forest Tenure Road Section Lines](https://catalogue.data.gov.bc.ca/dataset/forest-tenure-road-section-lines) | WHSE_FOREST_TENURE.FTEN_ROAD_SECTION_LINES_SVW |
| 3 | [RESULTS - Forest Cover Inventory - roads](https://catalogue.data.gov.bc.ca/dataset/results-forest-cover-inventory) | WHSE_FOREST_VEGETATION.RSLT_FOREST_COVER_INV_SVW |
| 4 | As Built Roads (ABR) | WHSE_FOREST_TENURE.ABR_ROAD_SECTION_LINE |
| 5 | [OGC Petroleum Development Roads Pre-2006](https://catalogue.data.gov.bc.ca/dataset/ogc-petroleum-development-roads-pre-2006-public-version) | WHSE_MINERAL_TENURE.OG_PETRLM_DEV_RDS_PRE06_PUB_SP |
| 6 | [Oil and Gas Commission Road Segment Permits](https://catalogue.data.gov.bc.ca/dataset/oil-and-gas-commission-road-segment-permits) | WHSE_MINERAL_TENURE.OG_ROAD_SEGMENT_PERMIT_SP |
| 7 | [Oil and Gas Commission Road Right of Way Permits](https://catalogue.data.gov.bc.ca/dataset/oil-and-gas-commission-road-right-of-way-permits) | WHSE_MINERAL_TENURE.OG_ROAD_AREA_PERMIT_SP |

## Method

First, sources are preprocessed:
- centerlines of polygon road sources are approximated
- FTEN roads are cleaned slightly, snapping endpoints within 7m to other same-source roads

Next, all roads are loaded to the output table in order of decreasing priority. Portions of lower priority roads within 7m of a higher priority road are deleted. Where the endpoint of a remaining lower priority road is within 7m of a higher prioirity road, the endpoint of the lower priority road is snapped to the closest point on the higher priority road.

## Limitations and Caveats

The authoritative source for built roads in British Columbia is the [Digital Road Atlas](https://catalogue.data.gov.bc.ca/dataset/digital-road-atlas-dra-master-partially-attributed-roads). The process used in these scripts **IS NOT A COMPRENSIVE CONFLATION/MERGE** of the input road layers, it is a quick approximation. The intent of the processing is to retain all input features not covered by a higher priority road - due to the nature of duplication in BC road data, the output will always be an over-representation of roads.

Several specific issues will lead to over-representation of roads:

- the same road present in different source layers will only be de-duplicated when features are less than 7m apart, see [Duplications](#Duplications) below)
- roads are present in the tenure layers that have not been built
- roads may have been decomissioned, overgrown or become otherwise impassible

Additional notes:

- the various road data sources are not 100% comprehensive, there may be roads present in the landscape that are not included in the analysis and output product
- because processing is tiled by BCGS 20k tile, any portion of road falling outside of these tiles will not be included (tile edges do not exactly match the surveyed BC border)


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

        ./01_load.sh

3. Convert polygon road sources to lines:

        ./02_preprocess.sh

4. Process all roads, create output view `integratedroads_vw`:

        ./03_process.sh

5. Dump output view to file:

        ./04_dump.sh


## Duplications
As mentioned above, this analysis is very much a rough approximation. It works well in areas where roads are not duplicated between sources or where source road networks are near-coincident.

These diagrams illustrate a problematic sample area, showing three input road layers (green as highest priority) and the resulting output (using a 7m tolerance).

### three input layers
![inputs](img/roadintegrator_inputs.png)

### resulting output
![inputs](img/roadintegrator_output.png)

## Output summary

| priority |                       source                       | extraction_date | length_km | length_pct |
|----------|----------------------------------------------------|-----------------|-----------:|------------:|
| 1        | whse_basemapping.transport_line                    | 2021-07-27      | 792,033   | 82.97|
| 2        | whse_forest_tenure.ften_road_section_lines_svw     | 2021-07-27      | 101,721   | 10.66|
| 3        | whse_forest_vegetation.rslt_forest_cover_inv_svw   | 2021-07-27      | 49,331    | 5.17|
| 4        | whse_forest_tenure.abr_road_section_line           | 2021-07-13      | 2,620     | 0.27|
| 5        | whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp | 2021-07-27      | 1,006     | 0.11|
| 6        | whse_mineral_tenure.og_road_segment_permit_sp      | 2021-07-27      | 7,737     | 0.81|
| 7        | whse_mineral_tenure.og_road_area_permit_sp         | 2021-07-27      | 189       | 0.02|
|          |                                                    | TOTAL           | 954,638   | |

## Alternative approaches

Road network conflation is a common task, many additional approaches and tools are available. This list provides a starting point for additional reading:

- RoadMatcher JUMP/OpenJump plugin [source](https://github.com/ssinger/roadmatcher), [wiki](http://wiki.openstreetmap.org/wiki/RoadMatcher)
- [PostGIS topology](http://blog.mathieu-leplatre.info/use-postgis-topologies-to-clean-up-road-networks.html)
- [Average Path Length Similarity](https://medium.com/the-downlinq/spacenet-road-detection-and-routing-challenge-part-ii-apls-implementation-92acd86f4094)
- [Tiled similarity scoring](https://medium.com/strava-engineering/activity-grouping-the-heart-of-a-social-network-for-athletes-865751f7dca)
- [Hootenanny - a conflation tool](https://github.com/ngageoint/hootenanny)
- [Graph based merging](https://open.library.ubc.ca/cIRcle/collections/ubctheses/24/items/1.0398182)