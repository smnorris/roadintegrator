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

# summarize road source by length
ogr2ogr \
  -f GPKG \
  -progress \
  -update \
  -nln bcgw_source_km \
-sql "SELECT
  bcgw_source,
  round((sum(st_length(geom) / 1000)::numeric), 2)  as length_km
FROM integratedroads_vw
GROUP BY bcgw_source" \
  integratedroads.gpkg \
  "PG:host=localhost user=postgres dbname=roadintegrator password=postgres"

zip -r integratedroads.gpkg.zip integratedroads.gpkg
