#!/usr/bin/env bash

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