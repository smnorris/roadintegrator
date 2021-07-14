#!/bin/bash
set -euxo pipefail

# dump to geopackage
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
