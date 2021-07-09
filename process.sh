#!/bin/bash
set -euxo pipefail

# create output table
psql -f sql/create_output.sql

# make sure the FilterRings function is present
psql -f sql/ST_FilterRings.sql

# --------------------------------------
# process tiles for each data source in parallel
# --------------------------------------

# DRA
time psql -t -P border=0,footer=no \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092%'" \
    | parallel psql -f sql/dra.sql -v tile={1}

# FTEN - Active
time psql -t -P border=0,footer=no \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092%'" \
    | parallel psql -f sql/ften_active.sql -v tile={1}

# FTEN - Retired
time psql -t -P border=0,footer=no \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092%'" \
    | parallel psql -f sql/ften_retired.sql -v tile={1}

# Results
time psql -t -P border=0,footer=no \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092%'" \
    | parallel psql -f sql/results.sql -v tile={1}

# ABR
time psql -t -P border=0,footer=no \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092%'" \
    | parallel psql -f sql/abr.sql -v tile={1}

# OG development permits pre06
time psql -t -P border=0,footer=no \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092%'" \
    | parallel psql -f sql/og_dev_pre06.sql -v tile={1}

# OG permits
time psql -t -P border=0,footer=no \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092%'" \
    | parallel psql -f sql/og_permits.sql -v tile={1}

# og permit right-of-ways
time psql -t -P border=0,footer=no \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092%'" \
    | parallel psql -f sql/og_permits_row.sql -v tile={1}
