#!/bin/bash
set -euxo pipefail

# create output table
psql -f sql/create_integratedroads.sql

# --------------------------------------
# Process each data source, in descending order of priority
# Each data source is chunked into tiles, which are loaded in parallel
# --------------------------------------

# DRA (process by 250k tile, processing is minor)
time psql -tXA \
-c "SELECT DISTINCT
      substring(t.map_tile from 1 for 4) as map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_basemapping.transport_line r
    ON ST_Intersects(t.geom, r.geom)
    ORDER BY substring(t.map_tile from 1 for 4)" \
    | parallel psql -f sql/01_dra.sql -v tile={1}

# process all additional sources by 20k tile
# FTEN - Active
time psql -tXA \
-c "SELECT DISTINCT t.map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_forest_tenure.ften_road_section_lines_svw r
    ON ST_Intersects(t.geom, r.geom)
    WHERE r.life_cycle_status_code = 'ACTIVE'
    ORDER BY t.map_tile" \
    | parallel psql -f sql/02_ften_active.sql -v tile={1}

# FTEN - Retired
time psql -tXA \
-c "SELECT DISTINCT t.map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_forest_tenure.ften_road_section_lines_svw r
    ON ST_Intersects(t.geom, r.geom)
    WHERE r.life_cycle_status_code = 'RETIRED'
    ORDER BY t.map_tile" \
    | parallel psql -f sql/03_ften_retired.sql -v tile={1}

# Results
time psql -tXA \
-c "SELECT DISTINCT map_tile FROM results" \
    | parallel psql -f sql/04_results.sql -v tile={1}

# ABR
time psql -tXA \
-c "SELECT DISTINCT t.map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_forest_tenure.abr_road_section_line r
    ON ST_Intersects(t.geom, r.geom)
    ORDER BY t.map_tile" \
    | parallel psql -f sql/05_abr.sql -v tile={1}

# OG development permits pre06
time psql -tXA \
-c "SELECT DISTINCT t.map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp r
    ON ST_Intersects(t.geom, r.geom)
    ORDER BY t.map_tile" \
    | parallel psql -f sql/06_og_dev_pre06.sql -v tile={1}

# OG permits
time psql -tXA \
-c "SELECT DISTINCT t.map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_mineral_tenure.og_road_segment_permit_sp r
    ON ST_Intersects(t.geom, r.geom)
    ORDER BY t.map_tile" \
    | parallel psql -f sql/07_og_permits.sql -v tile={1}

# og permit right-of-ways
time psql -tXA \
-c "SELECT DISTINCT map_tile FROM og_permits_row" \
    | parallel psql -f sql/08_og_permits_row.sql -v tile={1}

# The st_segmentized geoms from DRA used to improve snapping are redundant
# and some tools cannot handle this level of data density. Delete the DRA geoms
# and replace with source features
psql -c "DELETE FROM integratedroads WHERE transport_line_id IS NOT NULL"
time psql -tXA \
-c "SELECT DISTINCT
      substring(t.map_tile from 1 for 4) as map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_basemapping.transport_line r
    ON ST_Intersects(t.geom, r.geom)
    ORDER BY substring(t.map_tile from 1 for 4)" \
    | parallel psql -f sql/dra_src.sql -v tile={1}

# index the foreign keys for faster joins back to source tables
psql -c "CREATE INDEX ON integratedroads (transport_line_id)"
psql -c "CREATE INDEX ON integratedroads (map_label)"
psql -c "CREATE INDEX ON integratedroads (road_section_line_id)"
psql -c "CREATE INDEX ON integratedroads (og_petrlm_dev_rd_pre06_pub_id)"
psql -c "CREATE INDEX ON integratedroads (og_road_segment_permit_id)"

# and finally create output view with required data/columns
psql -f sql/integratedroads_vw.sql