COPY (WITH source_priority AS (
  SELECT * FROM (VALUES
  (1,'whse_basemapping.transport_line'),
  (2,'whse_forest_tenure.ften_road_section_lines_svw'),
  (3,'whse_forest_vegetation.rslt_forest_cover_inv_svw'),
  (4,'whse_forest_tenure.abr_road_section_line'),
  (5,'whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp'),
  (6,'whse_mineral_tenure.og_road_segment_permit_sp'),
  (7,'whse_mineral_tenure.og_road_area_permit_sp')
  ) as t (priority, bcgw_source)
),

total AS
(
  SELECT SUM(ST_Length(geom)) / 1000 AS total_km
  FROM integratedroads_vw
),

len_per_source AS
(
  SELECT
    p.priority,
    r.bcgw_source,
    to_char(r.bcgw_extraction_date, 'YYYY-MM-DD') as bcgw_extraction_date,
    SUM(ST_Length(geom)) / 1000 as length_km
  FROM integratedroads_vw r
  INNER JOIN source_priority p ON r.bcgw_source = UPPER(p.bcgw_source)
  GROUP BY p.priority, r.bcgw_source, to_char(r.bcgw_extraction_date, 'YYYY-MM-DD')
)

SELECT
  priority::text,
  LOWER(bcgw_source) as source,
  bcgw_extraction_date as extraction_date,
  to_char(ROUND(length_km::numeric), 'FM9,999,999') AS length_km,
  ROUND(((length_km / t.total_km ) * 100)::numeric, 2)::text as length_pct
FROM len_per_source, total t
UNION ALL
SELECT
  '' as priority,
  '' as bcgw_source,
  'TOTAL' as bcgw_extraction_date,
  to_char(total_km, 'FM999,999,999') as total_km,
  '' length_pct
FROM total) TO STDOUT CSV HEADER;