-- -----------------------
-- name: og_permits_row!
-- Convert results road polys to line and load to output, snapping to existing roads
-- -----------------------

-- extract features from tile
WITH src AS
(
  SELECT
    id,
    map_tile,
    geom
  FROM og_permits_row
  WHERE map_tile = :'tile'
),

-- find existing roads within 7m
within_tolerance AS
(
  SELECT
    a.id,
    st_union(i.geom) as geom
  FROM integratedroads i
  INNER JOIN src a
  ON ST_DWithin(a.geom, i.geom, 7)
  AND i.map_tile = a.map_tile
  GROUP BY a.id
),

-- snap to features found above
snapped AS
(
  SELECT
    a.id,
--    a.og_road_area_permit_id,
    ST_Snap(a.geom, b.geom, 7) as geom
  FROM src a
  INNER JOIN within_tolerance b ON
  a.id = b.id
)

-- insert the difference into output table
INSERT INTO integratedroads
(
  map_tile,
  'WHSE_MINERAL_TENURE.OG_ROAD_AREA_PERMIT_SP' AS bcgw_source, -- record source because we do not have an id
  --og_road_area_permit_id,
  geom
)
SELECT
  :'tile' AS map_tile,
--f.og_road_area_permit_id,
  f.geom
FROM (
  SELECT
    --a.og_road_area_permit_id,
    (ST_Dump(ST_Difference(a.geom, b.geom, 1))).geom as geom
  FROM snapped a
  INNER JOIN within_tolerance b
  ON a.id = b.id
  ) as f
WHERE st_length(geom) > 7
-- include features that do not get snapped (>7m away from existing road)
UNION ALL
SELECT
  :'tile' AS map_tile,
  'WHSE_MINERAL_TENURE.OG_ROAD_AREA_PERMIT_SP' as bcgw_source, -- record source because we do not have an id
--  n.og_road_area_permit_id,
  n.geom
FROM src n
LEFT OUTER JOIN snapped s
ON n.id = s.id
WHERE s.id IS NULL;