#!/bin/bash
set -euxo pipefail

# create output table
psql -c "DROP TABLE IF EXISTS integratedroads CASCADE"
psql -f sql/create_integratedroads.sql


# DRA (just dump everything in, these features remain unchanged)
time psql -tXA \
-c "SELECT DISTINCT
      substring(t.map_tile from 1 for 4) as map_tile
    FROM whse_basemapping.bcgs_20k_grid t
    INNER JOIN whse_basemapping.transport_line r
    ON ST_Intersects(t.geom, r.geom)
    ORDER BY substring(t.map_tile from 1 for 4)" \
    | parallel psql -f sql/load_dra.sql -v tile={1}
#WHERE map_tile LIKE '103P%'
# define all source tables and their primary keys in array
# bash arrays are like older python dicts, they are not ordered...
# https://stackoverflow.com/questions/29161323/how-to-keep-associative-array-order
declare -A tables;      declare -a ordered;
tables["ften_active"]="map_label"; ordered+=("ften_active")
tables["ften_retired"]="map_label"; ordered+=("ften_retired")
tables["results"]="results_id"; ordered+=("results")
tables["whse_forest_tenure.abr_road_section_line"]="road_section_line_id"; ordered+=("whse_forest_tenure.abr_road_section_line")
tables["whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp"]="og_petrlm_dev_rd_pre06_pub_id"; ordered+=("whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp")
tables["whse_mineral_tenure.og_road_segment_permit_sp"]="og_road_segment_permit_id"; ordered+=("whse_mineral_tenure.og_road_segment_permit_sp")
tables["og_permits_row"]="og_permits_row_id"; ordered+=("og_permits_row")

for source_table in "${ordered[@]}"
  do
    echo "Processing: $source_table"
    psql -tXA \
    -c "SELECT DISTINCT t.map_tile
        FROM whse_basemapping.bcgs_20k_grid t
        INNER JOIN $source_table r
        ON ST_Intersects(t.geom, r.geom)
        ORDER BY t.map_tile" \
        | parallel psql -f sql/load_difference.sql -v tile={1} -v src_roads=$source_table -v pk=${tables[$source_table]}
  done

#       WHERE t.map_tile LIKE '103P%'
# index the foreign keys for faster joins back to source tables
psql -c "CREATE INDEX ON integratedroads (transport_line_id)"
psql -c "CREATE INDEX ON integratedroads (map_label)"
psql -c "CREATE INDEX ON integratedroads (road_section_line_id)"
psql -c "CREATE INDEX ON integratedroads (og_petrlm_dev_rd_pre06_pub_id)"
psql -c "CREATE INDEX ON integratedroads (og_road_segment_permit_id)"

# and finally create output view with required data/columns
psql -f sql/integratedroads_vw.sql