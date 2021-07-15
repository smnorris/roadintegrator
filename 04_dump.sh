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

# summarize road source by length and percentage in the dump gpkg
ogr2ogr \
  -f GPKG \
  -progress \
  -update \
  -nln bcgw_source_summary \
-sql "WITH total AS
(
  SELECT SUM(ST_Length(geom)) AS total_length
  FROM integratedroads_vw
)
SELECT
  bcgw_source,
  to_char(bcgw_extraction_date, 'YYYY-MM-DD') as bcgw_extraction_date,
  ROUND((SUM(ST_Length(geom) / 1000)::numeric))  AS length_km,
  ROUND(
    (((SUM(ST_Length(geom)) / t.total_length)) * 100)::numeric, 1) as pct
FROM integratedroads_vw, total t
GROUP BY bcgw_source, to_char(bcgw_extraction_date, 'YYYY-MM-DD'), total_length
ORDER BY bcgw_source" \
  integratedroads.gpkg \
  "PG:host=localhost user=postgres dbname=roadintegrator password=postgres"

zip -r integratedroads.gpkg.zip integratedroads.gpkg

# also generate some markdown for readme
# https://gist.github.com/rastermanden/94c4a663176c41248f3e
psql -c "WITH total AS
(
  SELECT SUM(ST_Length(geom)) / 1000 AS total_km
  FROM integratedroads_vw
),
len_per_source AS
(
SELECT
  p.priority,
  r.bcgw_source,
  to_char(r.bcgw_extraction_date, 'YYYY-MM-DD') as bcgw_extraction_date,
  SUM(ST_Length(geom)) / 1000 as length_km
FROM integratedroads_vw r
INNER JOIN source_priority p ON r.bcgw_source = UPPER(p.bcgw_source)
GROUP BY p.priority, r.bcgw_source, to_char(r.bcgw_extraction_date, 'YYYY-MM-DD')
)
SELECT
  priority::text,
  LOWER(bcgw_source) as source,
  bcgw_extraction_date as extraction_date,
  to_char(ROUND(length_km::numeric), 'FM9,999,999') AS length_km,
  ROUND(((length_km / t.total_km ) * 100)::numeric, 2)::text as length_pct
FROM len_per_source, total t
UNION ALL
SELECT
  '' as priority,
  '' as bcgw_source,
  'TOTAL' as bcgw_extraction_date,
  to_char(total_km, 'FM999,999,999') as total_km,
  '' length_pct
FROM total;" | sed 's/+/|/g' | sed 's/^/|/' | sed 's/$/|/' |  grep -v rows | grep -v '||'