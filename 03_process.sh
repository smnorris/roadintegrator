#!/bin/bash
set -euxo pipefail

# create output table
psql -f sql/create_integratedroads.sql

# --------------------------------------
# Process each data source, in descending order of priority
# Each data source is chunked into tiles, which are loaded in parallel
# --------------------------------------

# DRA
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/01_dra.sql -v tile={1}

# FTEN - Active
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/02_ften_active.sql -v tile={1}

# FTEN - Retired
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/03_ften_retired.sql -v tile={1}

# Results
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/04_results.sql -v tile={1}

# ABR
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/05_abr.sql -v tile={1}

# OG development permits pre06
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/06_og_dev_pre06.sql -v tile={1}

# OG permits
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/07_og_permits.sql -v tile={1}

# og permit right-of-ways
time psql -tXA \
-c "SELECT map_tile FROM whse_basemapping.bcgs_20k_grid
    WHERE map_tile LIKE '092C%'" \
    | parallel psql -f sql/08_og_permits_row.sql -v tile={1}

# after loading, index the output for faster joins back to sources
psql -c "CREATE INDEX ON integratedroads (transport_line)"
psql -c "CREATE INDEX ON integratedroads (map_label)"
psql -c "CREATE INDEX ON integratedroads (road_section_line_id)"
psql -c "CREATE INDEX ON integratedroads (og_petrlm_dev_rd_pre06_pub_id)"
psql -c "CREATE INDEX ON integratedroads (og_road_segment_permit_id)"

# create a view that links output geoms back to source attribs
psql -f sql/integratedroads_vw.sql