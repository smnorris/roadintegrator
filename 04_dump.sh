#!/bin/bash
set -euxo pipefail

# Dump output to .gdb
# This uses dockerized gdal for easy access to fgdb driver
docker run --rm \
  -v ${PWD}:/output \
  osgeo/gdal:ubuntu-full-3.3.1-fgdb \
  ogr2ogr \
    -f FileGDB \
    -progress \
    -nlt LINESTRING \
    -nln integrated_roads \
    -lco GEOMETRY_NULLABLE=NO \
    -lco GEOMETRY_NAME=Shape \
    -sql "SELECT * FROM integratedroads_vw" \
    integrated_roads.gdb \
    "PG:host=$PGHOST user=$PGUSER dbname=$PGDATABASE port=$PGPORT"

ogr2ogr \
    -f GPKG \
    -progress \
    -nlt LINESTRING \
    -nln integrated_roads \
    -lco GEOMETRY_NULLABLE=NO \
    -sql "SELECT * FROM integratedroads_vw" \
    integratedroads.gpkg \
    "PG:host=$PGHOST user=$PGUSER dbname=$PGDATABASE port=$PGPORT"

zip -r integratedroads.gpkg.zip integratedroads.gpkg
scp integratedroads.gpkg.zip snorris@hillcrestgeo.ca:/var/www/hillcrestgeo.ca/html/outgoing/public