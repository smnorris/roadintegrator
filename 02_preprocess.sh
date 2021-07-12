#!/bin/bash
set -euxo pipefail

# --------------------------------------
# Preprocess the polygon road sources, converting to lines
# --------------------------------------

# make sure the FilterRings function is present
psql -f sql/ST_FilterRings.sql

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
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/results2line.sql -v tile={1}

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
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/og_permits_row2line.sql -v tile={1}
