-- -----------------------
-- Create output view with all required attributes
-- -----------------------

CREATE MATERIALIZED VIEW integratedroads_vw AS

-- determine source from the id present in the table, with exception of poly data sources
WITH sourced AS
(
SELECT DISTINCT ON (i.integratedroads_id)
  i.integratedroads_id,
  i.map_tile,
  i.transport_line_id,
  COALESCE(i.map_label, src.map_label) as map_label,
  src.forest_cover_id,
  COALESCE(i.road_section_line_id, src.road_section_line_id) as road_section_line_id,
  COALESCE(i.og_petrlm_dev_rd_pre06_pub_id, src.og_petrlm_dev_rd_pre06_pub_id) as og_petrlm_dev_rd_pre06_pub_id,
  COALESCE(i.og_road_segment_permit_id, src.og_road_segment_permit_id) as og_road_segment_permit_id,
  src.og_road_area_permit_id,
  ST_Length(ST_MakeValid((ST_Dump(i.geom)).geom)::geometry(Linestring, 3005)) AS length_metres,
  ST_MakeValid((ST_Dump(i.geom)).geom)::geometry(Linestring, 3005) AS geom
FROM integratedroads i
LEFT OUTER JOIN integratedroads_sources src
  ON i.integratedroads_id = src.integratedroads_id
ORDER BY i.integratedroads_id, ften_length desc, results_area desc, abr_length desc, og_dev_pre06_length desc, og_permits_length desc, og_permits_row_area desc
),

bcgw AS
(
  SELECT integratedroads_id,
  CASE
    WHEN i.transport_line_id IS NOT NULL THEN 'WHSE_BASEMAPPING.TRANSPORT_LINE'
    WHEN i.map_label IS NOT NULL THEN 'WHSE_FOREST_TENURE.FTEN_ROAD_SECTION_LINES_SVW'
    WHEN i.road_section_line_id IS NOT NULL THEN 'WHSE_FOREST_TENURE.ABR_ROAD_SECTION_LINE'
    WHEN i.og_petrlm_dev_rd_pre06_pub_id IS NOT NULL THEN 'WHSE_MINERAL_TENURE.OG_PETRLM_DEV_RDS_PRE06_PUB_SP'
    WHEN i.og_road_segment_permit_id IS NOT NULL THEN 'WHSE_MINERAL_TENURE.OG_ROAD_SEGMENT_PERMIT_SP'
    WHEN i.results_id IS NOT NULL THEN 'WHSE_FOREST_VEGETATION.RSLT_FOREST_COVER_INV_SVW'
    WHEN i.og_permits_row_id IS NOT NULL THEN 'WHSE_MINERAL_TENURE.OG_ROAD_AREA_PERMIT_SP'
  END AS bcgw_source
  FROM integratedroads i
)

SELECT
  i.integratedroads_id AS INTEGRATEDROADS_ID,
  bcgw.bcgw_source AS BCGW_SOURCE,
  m.date_downloaded AS BCGW_EXTRACTION_DATE,
  map_tile AS MAP_TILE,
  i.transport_line_id AS TRANSPORT_LINE_ID,
  dra_struct.transport_line_structure_code  AS DRA_STRUCTURE,
  dra_type.transport_line_type_code         AS DRA_TYPE,
  dra_surf.transport_line_surface_code      AS DRA_SURFACE,
  dra.structured_name_1                     AS DRA_NAME_FULL,
  dra.structured_name_1_id                  AS DRA_ROAD_NAME_ID,
  dra.capture_date                          AS DRA_DATA_CAPTURE_DATE,
  dra.total_number_of_lanes                 AS DRA_TOTAL_NUMBER_OF_LANES,
  i.map_label                               AS FTEN_MAP_LABEL,
  ften.forest_file_id                       AS FTEN_FOREST_FILE_ID,
  ften.road_section_id                      AS FTEN_ROAD_SECTION_ID,
  ften.file_status_code                     AS FTEN_FILE_STATUS_CODE,
  ften.file_type_code                       AS FTEN_FILE_TYPE_CODE,
  ften.file_type_description                AS FTEN_FILE_TYPE_DESCRIPTION,
  ften.life_cycle_status_code               AS FTEN_LIFE_CYCLE_STATUS_CODE,
  ften.award_date                           AS FTEN_AWARD_DATE,
  ften.retirement_date                      AS FTEN_RETIREMENT_DATE,
  ften.client_number                        AS FTEN_CLIENT_NUMBER,
  ften.client_name                          AS FTEN_CLIENT_NAME,
  i.forest_cover_id                         AS RESULTS_FOREST_COVER_ID,
  results.stocking_status_code              AS RESULTS_STOCKING_STATUS_CODE,
  results.stocking_type_code                AS RESULTS_STOCKING_TYPE_CODE,
  results.silv_polygon_number               AS RESULTS_SILV_POLYGON_NUMBER,
  i.road_section_line_id                    AS ABR_ROAD_SECTION_LINE_ID,
  abr.forest_file_id                        AS ABR_FOREST_FILE_ID,
  abr.road_section_id                       AS ABR_ROAD_SECTION_ID,
  abr.submission_id                         AS ABR_SUBMISSION_ID,
  abr.update_timestamp                      AS ABR_UPDATE_TIMESTAMP,
  i.og_petrlm_dev_rd_pre06_pub_id           AS OG_PETRLM_DEV_RD_PRE06_PUB_ID,
  og_dev_pre06.petrlm_development_road_type AS PETRLM_DEVELOPMENT_ROAD_TYPE,
  og_dev_pre06.application_received_date    AS APPLICATION_RECEIVED_DATE,
  og_dev_pre06.proponent                    AS PROPONENT,
  i.og_road_segment_permit_id               AS OGP_ROAD_SEGMENT_PERMIT_ID,
  og_permits.road_number                    AS OGP_ROAD_NUMBER,
  og_permits.segment_number                 AS OGP_SEGMENT_NUMBER,
  og_permits.road_type                      AS OGP_ROAD_TYPE,
  og_permits.road_type_desc                 AS OGP_ROAD_TYPE_DESC,
  og_permits.activity_approval_date         AS OGP_ACTIVITY_APPROVAL_DATE,
  og_permits.proponent                      AS OGP_PROPONENT,
  og_permits_row.og_road_area_permit_id     AS OGPROW_OG_ROAD_AREA_PERMIT_ID,
  og_permits_row.land_type                  AS OGPROW_LAND_TYPE,
  og_permits_row.construction_desc          AS OGPROW_CONSTRUCTION_DESC,
  i.length_metres                           AS LENGTH_METRES,
  i.geom
FROM sourced i
INNER JOIN bcgw 
  ON i.integratedroads_id = bcgw.integratedroads_id
INNER JOIN bcdata m 
  ON bcgw.bcgw_source = UPPER(m.table_name)
LEFT OUTER JOIN whse_basemapping.transport_line dra 
  ON i.transport_line_id = dra.transport_line_id
LEFT OUTER JOIN whse_basemapping.transport_line_structure_code dra_struct
  ON dra.transport_line_structure_code = dra_struct.transport_line_structure_code
LEFT OUTER JOIN whse_basemapping.transport_line_type_code dra_type
  ON dra.transport_line_type_code = dra_type.transport_line_type_code
LEFT OUTER JOIN whse_basemapping.transport_line_surface_code dra_surf
  ON dra.transport_line_surface_code = dra_surf.transport_line_surface_code
LEFT OUTER JOIN whse_forest_tenure.ften_road_section_lines_svw ften 
  ON i.map_label = ften.map_label 
LEFT OUTER JOIN whse_forest_vegetation.rslt_forest_cover_inv_svw results
  ON i.forest_cover_id = results.forest_cover_id
LEFT OUTER JOIN whse_forest_tenure.abr_road_section_line abr 
  ON i.road_section_line_id = abr.road_section_line_id 
LEFT OUTER JOIN whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp og_dev_pre06 
  ON i.og_petrlm_dev_rd_pre06_pub_id = og_dev_pre06.og_petrlm_dev_rd_pre06_pub_id
LEFT OUTER JOIN whse_mineral_tenure.og_road_segment_permit_sp og_permits 
  ON i.og_road_segment_permit_id = og_permits.og_road_segment_permit_id
LEFT OUTER JOIN whse_mineral_tenure.og_road_area_permit_sp og_permits_row
  ON i.og_road_area_permit_id = og_permits_row.og_road_area_permit_id;

CREATE INDEX ON integratedroads_vw (integratedroads_id);
CREATE INDEX ON integratedroads_vw USING GIST (geom);