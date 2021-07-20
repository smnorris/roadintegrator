DROP MATERIALIZED VIEW IF EXISTS integratedroads_vw;

CREATE MATERIALIZED VIEW integratedroads_vw AS

-- determine source from the id present in the table, with exception of poly data sources
WITH bcgw AS  
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
  i.integratedroads_id,
  bcgw.bcgw_source,
  m.date_downloaded as bcgw_extraction_date,
  map_tile,
  i.transport_line_id,
  dra_struct.transport_line_structure_code  AS dra_structure,
  dra_type.transport_line_type_code         AS dra_type,
  dra_surf.transport_line_surface_code      AS dra_surface,
  dra.structured_name_1                     AS dra_name_full,
  dra.structured_name_1_id                  AS dra_road_name_id,
  dra.capture_date                          AS dra_data_capture_date,
  i.map_label                               AS ften_map_label,
  ften.forest_file_id                       AS ften_forest_file_id,
  ften.road_section_id                      AS ften_road_section_id,
  ften.file_status_code                     AS ften_file_status_code,
  ften.file_type_code                       AS ften_file_type_code,
  ften.file_type_description                AS ften_file_type_description,
  ften.life_cycle_status_code               AS ften_life_cycle_status_code,
  ften.award_date                           AS ften_award_date,
  ften.retirement_date                      AS ften_retirement_date,
  ften.client_number                        AS ften_client_number,
  ften.client_name                          AS ften_client_name,
  i.road_section_line_id                    AS abr_road_section_line_id,
  abr.forest_file_id                        AS abr_forest_file_id,
  abr.road_section_id                       AS abr_road_section_id,
  abr.submission_id                         AS abr_submission_id,
  abr.update_timestamp                      AS abr_update_timestamp,
  i.og_petrlm_dev_rd_pre06_pub_id           AS og_petrlm_dev_rd_pre06_pub_id,
  og_dev_pre06.petrlm_development_road_type AS petrlm_development_road_type,
  og_dev_pre06.application_received_date    AS application_received_date,
  og_dev_pre06.proponent                    AS proponent,
  i.og_road_segment_permit_id               AS ogp_road_segment_permit_id,
  og_permits.road_number                    AS ogp_road_number,
  og_permits.segment_number                 AS ogp_segment_number,
  og_permits.road_type                      AS ogp_road_type,
  og_permits.road_type_desc                 AS ogp_road_type_desc,
  og_permits.activity_approval_date         AS ogp_activity_approval_date,
  og_permits.proponent                      AS ogp_proponent,
  ST_MakeValid((ST_Dump(i.geom)).geom)::geometry(Linestring, 3005) as geom
FROM integratedroads i
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
LEFT OUTER JOIN whse_forest_tenure.abr_road_section_line abr 
  ON i.road_section_line_id = abr.road_section_line_id 
LEFT OUTER JOIN whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp og_dev_pre06 
  ON i.og_petrlm_dev_rd_pre06_pub_id = og_dev_pre06.og_petrlm_dev_rd_pre06_pub_id
LEFT OUTER JOIN whse_mineral_tenure.og_road_segment_permit_sp og_permits 
  ON i.og_road_segment_permit_id = og_permits.og_road_segment_permit_id;

CREATE INDEX ON integratedroads_vw (integratedroads_id);
CREATE INDEX ON integratedroads_vw USING GIST (geom);