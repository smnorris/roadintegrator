-- -----------------------
-- name: results!
-- Snap results roads to higher priority roads, insert difference
-- -----------------------

-- extract features from tile
WITH src AS
(
  SELECT
    id,
    map_tile,
    geom
  FROM results
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

-- snap to source features
snapped AS
(
  SELECT
    a.id,
    --a.forest_cover_id,
    ST_Snap(a.geom, b.geom, 7) as geom
  FROM src a
  INNER JOIN within_tolerance b ON
  a.id = b.id
)

-- Finally, insert the difference into output table
INSERT INTO integratedroads
(
  map_tile,
  bcgw_source,
  geom
)
SELECT
  :'tile' AS map_tile,
  'WHSE_FOREST_VEGETATION.RSLT_FOREST_COVER_INV_SVW' as bcgw_source, -- record source because we do not have an id
  geom
FROM (
  SELECT
    f.geom
  FROM (
    SELECT
      (ST_Dump(ST_Difference(a.geom, b.geom, 1))).geom as geom
    FROM snapped a
    INNER JOIN within_tolerance b
    ON a.id = b.id
    ) as f
  WHERE st_length(geom) > 7
  -- include features that do not get snapped (>7m away from existing road)
  UNION ALL
  SELECT
    n.geom
  FROM src n
  LEFT OUTER JOIN snapped s
  ON n.id = s.id
  WHERE s.id IS NULL
) as b;