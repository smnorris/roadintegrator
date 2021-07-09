-- -----------------------
-- name: og_permits_row!
-- Convert results road polys to line and load to output, snapping to existing roads
-- -----------------------

-- extract features from tile
WITH tile AS
(SELECT
  map_tile,
  og_road_area_permit_id,
  (ST_Dump(geom)).geom as geom
FROM (
  SELECT
   r.og_road_area_permit_id,
   t.map_tile,
    CASE
      WHEN ST_CoveredBy(r.geom, t.geom) THEN r.geom
      ELSE ST_Intersection(t.geom, r.geom)
    END AS geom
  FROM whse_mineral_tenure.og_road_area_permit_sp r
  INNER JOIN whse_basemapping.bcgs_20k_grid t
  ON ST_Intersects(r.geom, t.geom)
  WHERE t.map_tile = :'tile'
) as f
WHERE ST_Dimension(geom) = 2
),

-- convert polys to lines
src AS (
SELECT
  row_number() over() as id, * FROM
(  SELECT
    map_tile,
    og_road_area_permit_id,
    (ST_Dump(ST_ApproximateMedialAxis(
      ST_ForceRHR(
        ST_FilterRings(geom, 10)  -- remove holes <10m area
      )
    ))).geom as geom
  FROM tile
  WHERE ST_Area(geom) > 10  -- don't bother processing polys <10m area
) as f
WHERE ST_Length(geom) > 6), -- don't bother processing output road lines <6m long

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
    a.og_road_area_permit_id,
    ST_Snap(a.geom, b.geom, 7) as geom
  FROM src a
  INNER JOIN within_tolerance b ON
  a.id = b.id
)

-- Finally, insert the difference into output table
INSERT INTO integratedroads
(
  map_tile,
  og_road_area_permit_id,
  geom
)
SELECT
  :'tile' AS map_tile,
  f.og_road_area_permit_id,
  f.geom
FROM (
  SELECT
    a.og_road_area_permit_id,
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
  n.og_road_area_permit_id,
  n.geom
FROM src n
LEFT OUTER JOIN snapped s
ON n.id = s.id
WHERE s.id IS NULL;