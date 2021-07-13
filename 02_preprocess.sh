#!/bin/bash
set -euxo pipefail

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
  id serial primary key,
  map_tile character varying,
  geom geometry(Linestring, 3005)
)"
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid" \
    | parallel psql -f sql/roadpoly2line.sql \
        -v tile={1} \
        -v in_table=whse_forest_vegetation.rslt_forest_cover_inv_svw \
        -v out_table=results

# -----
# convert OG permit right of ways (poly) to lines
# -----
psql -c "DROP TABLE IF EXISTS og_permits_row"
psql -c "CREATE TABLE og_permits_row
(
  id serial primary key,
  map_tile character varying,
  geom geometry(Linestring, 3005)
)"
time psql -tXA \
-c "SELECT DISTINCT t.map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_mineral_tenure.og_road_area_permit_sp r
    ON ST_Intersects(t.geom, r.geom)" \
     | parallel psql -f sql/roadpoly2line.sql \
       -v tile={1} \
       -v in_table=whse_mineral_tenure.og_road_area_permit_sp \
       -v out_table=og_permits_row
