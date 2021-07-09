-- -----------------------
-- name: ften_retired!
-- Process and load retired ften roads, snapping to existing roads
-- -----------------------

-- get only active ften roads for the tile
WITH src AS (
  SELECT
    map_label,
    map_tile,
    (ST_Dump(geom)).geom as geom
  FROM (
    SELECT
     r.map_label,
     t.map_tile,
      CASE
        WHEN ST_CoveredBy(r.geom, t.geom) THEN ST_Force2D(r.geom)
        ELSE ST_Force2D(ST_Intersection(t.geom, r.geom))
      END AS geom
    FROM whse_forest_tenure.ften_road_section_lines_svw r
    INNER JOIN whse_basemapping.bcgs_20k_grid t
    ON ST_Intersects(r.geom, t.geom)
    WHERE t.map_tile = :'tile'
    AND r.life_cycle_status_code = 'RETIRED'
  ) as f
  WHERE ST_Dimension(geom) = 1
),

-- clean the data a bit more, snapping endpoints to same-source features within 5m
snapped_endpoints AS
(
  SELECT 
    a.map_label,
    st_distance(st_endpoint(a.geom), b.geom) as dist_end,
    st_distance(st_startpoint(a.geom), b.geom) as dist_start,
    (ST_Dump(ST_Snap(a.geom, b.geom, 5))).geom::geometry(LineString, 3005) AS geom
  FROM src AS a
  INNER JOIN src AS b
  ON ST_DWithin(ST_EndPoint(a.geom), b.geom, 5) OR ST_DWithin(ST_StartPoint(a.geom), b.geom, 5)
  WHERE a.map_label != b.map_label
  AND (ST_Distance(ST_EndPoint(a.geom), b.geom) > 0 OR ST_Distance(ST_StartPoint(a.geom), b.geom) > 0)
  AND ST_Length(a.geom) < ST_Length(b.geom)
),

-- node new intersections created above
noded AS
(
  SELECT 
    row_number() over() as id, 
    geom 
  FROM (
    SELECT 
      (st_dump(st_node(st_union(COALESCE(s.geom, t.geom))))).geom as geom 
    FROM src t
    LEFT JOIN snapped_endpoints s
    ON t.map_label = s.map_label
    ) AS f
),

-- get the attributes back
noded_attrib AS
(
  SELECT DISTINCT ON (n.id)
    n.id,
    t.map_label,
    t.map_tile,
    n.geom
  FROM noded n
  INNER JOIN src t
  ON ST_Intersects(n.geom, t.geom)
  ORDER BY n.id, ST_Length(ST_Intersection(n.geom, t.geom)) DESC
),

-- find existing roads within 7m
within_tolerance AS
(
  SELECT
    a.id,
    st_union(i.geom) as geom
  FROM integratedroads i
  INNER JOIN noded_attrib a
  ON ST_DWithin(a.geom, i.geom, 7)
  AND i.map_tile = a.map_tile
  GROUP BY a.id
),

-- snap to features found above
snapped AS
(
  SELECT
    a.id,
    a.map_label,
    ST_Snap(a.geom, b.geom, 7) as geom
  FROM noded_attrib a
  INNER JOIN within_tolerance b ON
  a.id = b.id
)

-- Finally, insert the difference into output table
INSERT INTO integratedroads
(
  map_tile,
  map_label,
  geom
)
SELECT
  :'tile' AS map_tile,
  f.map_label,
  f.geom
FROM (
  SELECT
    a.map_label,
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
  n.map_label,
  n.geom
FROM noded_attrib n
LEFT OUTER JOIN snapped s
ON n.id = s.id
WHERE s.id IS NULL;