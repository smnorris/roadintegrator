ogr2ogr \
  -f FileGDB \
  -progress \
  -nlt LINESTRING \
  -nln integrated_roads \
  -lco GEOMETRY_NULLABLE=NO \
  -lco GEOMETRY_NAME=Shape \
  -sql "SELECT
    bcgw_source AS \"BCGW_SOURCE\",
    bcgw_extraction_date AS \"BCGW_EXTRACTION_DATE\",
    map_tile AS \"MAP_TILE\",
    dra_digital_road_atlas_line_id AS \"DRA_DIGITAL_ROAD_ATLAS_LINE_ID\",
    dra_road_class AS \"DRA_ROAD_CLASS\",
    dra_road_surface AS \"DRA_ROAD_SURFACE\",
    dra_road_name_full AS \"DRA_ROAD_NAME_FULL\",
    dra_road_name_id AS \"DRA_ROAD_NAME_ID\",
    dra_data_capture_date AS \"DRA_DATA_CAPTURE_DATE\",
    COALESCE(ften_active_map_label, ften_retired_map_label) AS \"FTEN_MAP_LABEL\",
    COALESCE(ften_active_forest_file_id, ften_retired_forest_file_id) AS \"FTEN_FOREST_FILE_ID\",
    COALESCE(ften_active_road_section_id, ften_retired_road_section_id) AS \"FTEN_ROAD_SECTION_ID\",
    COALESCE(ften_active_file_status_code, ften_retired_file_status_code) AS \"FTEN_FILE_STATUS_CODE\",
    COALESCE(ften_active_file_type_code, ften_retired_file_type_code) AS \"FTEN_FILE_TYPE_CODE\",
    COALESCE(ften_active_file_type_description, ften_retired_file_type_description) AS \"FTEN_FILE_TYPE_DESCRIPTION\",
    COALESCE(ften_active_life_cycle_status_code, ften_retired_life_cycle_status_code) AS \"FTEN_LIFE_CYCLE_STATUS_CODE\",
    COALESCE(to_date(ften_active_award_date, 'YYYY/MM/DD'), ften_retired_award_date) AS \"FTEN_AWARD_DATE\",
    COALESCE(to_date(ften_active_retirement_date, 'YYYY/MM/DD'), ften_retired_retirement_date) AS \"FTEN_RETIREMENT_DATE\",
    COALESCE(ften_active_client_number, ften_retired_client_number) AS \"FTEN_CLIENT_NUMBER\",
    COALESCE(ften_active_client_name, ften_retired_client_name) AS \"FTEN_CLIENT_NAME\",
    abr_road_section_line_id AS \"ABR_ROAD_SECTION_LINE_ID\",
    abr_forest_file_id AS \"ABR_FOREST_FILE_ID\",
    abr_road_section_id AS \"ABR_ROAD_SECTION_ID\",
    abr_submission_id AS \"ABR_SUBMISSION_ID\",
    abr_update_timestamp AS \"ABR_UPDATE_TIMESTAMP\",
    og_dev_pre06_og_petrlm_dev_rd_pre06_pub_id AS \"OG_DEV_PRE06_OG_PETRLM_DEV_RD_PRE06_PUB_ID\",
    og_dev_pre06_petrlm_development_road_type AS \"OG_DEV_PRE06_PETRLM_DEVELOPMENT_ROAD_TYPE\",
    og_dev_pre06_application_received_date AS \"OG_DEV_PRE06_APPLICATION_RECEIVED_DATE\",
    og_dev_pre06_proponent AS \"OG_DEV_PRE06_PROPONENT\",
    og_permits_og_road_segment_permit_id AS \"OG_PERMITS_OG_ROAD_SEGMENT_PERMIT_ID\",
    og_permits_road_number AS \"OG_PERMITS_ROAD_NUMBER\",
    og_permits_segment_number AS \"OG_PERMITS_SEGMENT_NUMBER\",
    og_permits_road_type AS \"OG_PERMITS_ROAD_TYPE\",
    og_permits_road_type_desc AS \"OG_PERMITS_ROAD_TYPE_DESC\",
    og_permits_activity_approval_date AS \"OG_PERMITS_ACTIVITY_APPROVAL_DATE\",
    og_permits_proponent AS \"OG_PERMITS_PROPONENT\",
    ST_MakeValid((ST_Dump(geom)).geom) as \"Shape\"
  FROM integrated_roads" \
  integrated_roads.gdb \
  "PG:host=localhost user=postgres dbname=roadintegrator password=postgres"

ogr2ogr \
  -f FileGDB \
  -progress \
  -update \
  -nln bcgw_source_km \
-sql "SELECT
  bcgw_source,
  round((sum(st_length(geom) / 1000)::numeric), 2)  as length_km
FROM integrated_roads
GROUP BY bcgw_source" \
  integrated_roads.gdb \
  "PG:host=localhost user=postgres dbname=roadintegrator password=postgres"

