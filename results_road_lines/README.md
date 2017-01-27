# RESULTS road lines


Convert road polygons in [RESULTS Forest Cover Inventory](https://catalogue.data.gov.bc.ca/dataset/results-forest-cover-inventory) (`WHSE_FOREST_COVER.RSLT_FOREST_COVER_INV_SVW`) to lines.

## Background
This job was previously run on FME using the `CenterLineReplacer` transformer. However, versions of FME >2013 bail on the job. ArcGIS doesn't have an equivalent `MedialAxis` function that I'm aware of, so this script runs the job in PostGIS. Similar pre-processing of the polygons in FME would likely work as well.


## Requirements

- PostgreSQL/PostGIS (with [SFCGAL](http://postgis.net/2015/10/25/postgis_sfcgal_extension/), runs successfully on 9.6/2.3.0)
- SFCGAL
- GDAL/OGR (for loading / dumping the data from/to .gdb)
- Python 2.7+
- [click](http://click.pocoo.org/5/)
- [pgdb](https://github.com/smnorris/pgdb)


## Setup
Replace the database credentials below with your own as required.

- install Python dependencies something like this:

        pip install click
        pip install git+https://github.com/smnorris/pgdb#egg=pgdb

- the script assumes that the `whse_basemapping` and `temp` schemas exist, create if they do not:

        psql -d postgis -U postgres -c "CREATE SCHEMA temp"
        psql -d postgis -U postgres -c "CREATE SCHEMA whse_basemapping"

- download [source RESULTS data](https://catalogue.data.gov.bc.ca/dataset/results-forest-cover-inventory) and load to postgres with something like this (ensuring that just the road polys are loaded with the `-where` option):

        ogr2ogr \
          --config PG_USE_COPY YES \
          -t_srs EPSG:3005 \
          -f PostgreSQL \
          PG:"host=localhost user=postgres dbname=postgis password=postgres" \
          -lco SCHEMA=temp \
          -lco GEOMETRY_NAME=geom \
          -dim 2 \
          -nln rslt_forest_cover_inv_svw \
          -nlt PROMOTE_TO_MULTI \
          -where "stocking_status_code = 'NP' AND stocking_type_code IN ('RD','UNN') AND silv_polygon_number not in ('landing', 'lnd') AND geometry_exist_ind = 'Y'" \
          <in_file>.gdb \
          <in_layer>

- download the [BCGS 1:20,000 grid](https://catalogue.data.gov.bc.ca/dataset/bcgs-1-20-000-grid) and load to postgres. The script expects the data to be in schema `whse_basemapping`, so a command something like this will load it:

        ogr2ogr \
          --config PG_USE_COPY YES \
          -t_srs EPSG:3005 \
          -f PostgreSQL \
          PG:"host=localhost user=postgres dbname=postgis password=postgres" \
          -lco SCHEMA=whse_basemapping \
          -lco GEOMETRY_NAME=geom \
          -dim 2 \
          -nln bcgs_20k_grid \
          -nlt PROMOTE_TO_MULTI \
          <in_file>.gdb \
          <in_layer>

- ensure that SFCGAL is enabled, hopefully [your distribution includes it](http://postgis.net/2015/10/25/postgis_sfcgal_extension):

        psql -d postgis -U postgres -c "CREATE EXTENSION postgis_sfcgal;"

- if not using the default postgres connection credentials or schemas, modify as required in the python script and sql files

## Run the job

`python results_road_lines.py`