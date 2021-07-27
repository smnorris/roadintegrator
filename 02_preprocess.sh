#!/bin/bash
set -euxo pipefail

# --------------------------------------
# Extract FTEN active/retired roads into separate tables and clean the features slightly
# (snap endpoints, renode)
# --------------------------------------
psql -c  "DROP TABLE IF EXISTS ften_active;"

psql -c "CREATE TABLE ften_active
( ften_active_id serial primary key,
  map_label character varying,
  map_tile character varying,
  geom geometry(Linestring,3005));"
time psql -tXA \
-c "SELECT DISTINCT map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_forest_tenure.ften_road_section_lines_svw r
    ON ST_Intersects(t.geom, r.geom)
    WHERE life_cycle_status_code = 'ACTIVE'
    ORDER BY map_tile" \
    | parallel psql -f sql/ften_active.sql -v tile={1}
psql -c "CREATE INDEX on ften_active USING GIST (geom);"

psql -c  "DROP TABLE IF EXISTS ften_retired;"
psql -c "CREATE TABLE ften_retired
( ften_retired_id serial primary key,
  map_label character varying,
  map_tile character varying,
  geom geometry(Linestring,3005));"
time psql -tXA \
-c "SELECT DISTINCT map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_forest_tenure.ften_road_section_lines_svw r
    ON ST_Intersects(t.geom, r.geom)
    WHERE life_cycle_status_code = 'RETIRED'
    ORDER BY map_tile" \
    | parallel psql -f sql/ften_retired.sql -v tile={1}

psql -c "CREATE INDEX on ften_retired USING GIST (geom);"

# --------------------------------------
# Preprocess the polygon road sources, converting to lines
# --------------------------------------

# make sure the FilterRings function is present
psql -f sql/ST_FilterRings.sql

# Approx Medial Axis will bail on self-intersecting (but valid) polys
# Ignore them by wrapping them in an exception handler
psql -f sql/ST_ApproximateMedialAxisIgnoreErrors.sql

# -----
# convert RESULTS polygon roads to lines
# -----
psql -c "DROP TABLE IF EXISTS results"
psql -c "CREATE TABLE results
(
  results_id serial primary key,
  map_tile character varying,
  geom geometry(Linestring, 3005)
)"
psql -tXA \
-c "SELECT DISTINCT t.map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_forest_vegetation.rslt_forest_cover_inv_svw r
    ON ST_Intersects(t.geom, r.geom)
    WHERE ST_ISvalid(r.geom)
    ORDER BY t.map_tile" \
    | parallel psql -f sql/roadpoly2line.sql \
        -v tile={1} \
        -v in_table=whse_forest_vegetation.rslt_forest_cover_inv_svw \
        -v out_table=results
psql -c "CREATE INDEX ON results USING GIST (geom)"

# -----
# convert OG permit right of ways (poly) to lines
# -----
psql -c "DROP TABLE IF EXISTS og_permits_row"
psql -c "CREATE TABLE og_permits_row
(
  og_permits_row_id serial primary key,
  map_tile character varying,
  geom geometry(Linestring, 3005)
)"
psql -tXA \
-c "SELECT DISTINCT t.map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_mineral_tenure.og_road_area_permit_sp r
    ON ST_Intersects(t.geom, r.geom)
    ORDER BY t.map_tile" \
     | parallel psql -f sql/roadpoly2line.sql \
       -v tile={1} \
       -v in_table=whse_mineral_tenure.og_road_area_permit_sp \
       -v out_table=og_permits_row
psql -c "CREATE INDEX ON og_permits_row USING GIST (geom)"