-- -----------------------
-- clean active FTEN roads slightly, snapping endpoints and re-noding
-- -----------------------

WITH src AS (
  SELECT row_number() over() as id, *
  FROM (
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
      AND r.life_cycle_status_code = 'ACTIVE'
    ) as f
    WHERE ST_Dimension(geom) = 1
  ) as b
),

start_snapped AS
(
  SELECT
  a.id,
  ST_LineInterpolatePoint(
    nn.geom,
    ST_LineLocatePoint(
      nn.geom,
        ST_StartPoint(a.geom)
    )
  ) as geom
FROM src a
CROSS JOIN LATERAL (
  SELECT
    id,
    ST_Distance(ST_StartPoint(a.geom), b.geom) as dist,
    geom
  FROM src b
  WHERE a.id != b.id
  AND ST_Distance(ST_Startpoint(a.geom), b.geom) > 0
  ORDER BY ST_StartPoint(a.geom) <-> b.geom
  LIMIT 1
) as nn
INNER JOIN whse_basemapping.bcgs_20k_grid t
ON a.map_tile = t.map_tile
WHERE nn.dist <= 7
AND NOT ST_DWithin(ST_Startpoint(a.geom), ST_ExteriorRing(t.geom), .1) -- do not snap endpoints created at tile intersections
),

end_snapped AS
(
  SELECT
  a.id,
  ST_LineInterpolatePoint(
    nn.geom,
    ST_LineLocatePoint(
      nn.geom,
        ST_EndPoint(a.geom)
    )
  ) as geom
FROM src a
CROSS JOIN LATERAL (
  SELECT
    id,
    ST_Distance(ST_EndPoint(a.geom), b.geom) as dist,
    geom
  FROM src b
  WHERE a.id != b.id
  AND ST_Distance(ST_Endpoint(a.geom), b.geom) > 0
  ORDER BY ST_EndPoint(a.geom) <-> b.geom
  LIMIT 1
) as nn
INNER JOIN whse_basemapping.bcgs_20k_grid t
ON a.map_tile = t.map_tile
WHERE nn.dist <= 7
AND NOT ST_DWithin(ST_Endpoint(a.geom), ST_ExteriorRing(t.geom), .1) -- do not snap endpoints created at tile intersections
),

snapped AS
(
  SELECT
    a.id,
    a.map_label,
    a.map_tile,
    CASE
      WHEN s.id IS NOT NULL AND e.id IS NULL                        -- snap just start
      THEN ST_Setpoint(a.geom, 0, s.geom)
      WHEN s.id IS NOT NULL AND e.id IS NOT NULL                    -- snap just end
      THEN ST_SetPoint(ST_Setpoint(a.geom, 0, s.geom), -1, e.geom)
      WHEN s.id IS NULL AND e.id IS NOT NULL                        -- snap start and end
      THEN ST_Setpoint(a.geom, -1, e.geom)
      ELSE a.geom
    END as geom
  FROM src a
  LEFT JOIN start_snapped s ON a.id = s.id
  LEFT JOIN end_snapped e ON a.id = e.id
),

-- node the linework
noded AS
(
  SELECT
    row_number() over() as id,
    geom
  FROM (
    SELECT
      (st_dump(st_node(st_union(geom)))).geom as geom
    FROM snapped
    ) AS f
),

-- get the attributes back
noded_attrib AS
(
  SELECT DISTINCT ON (n.id)
    n.id,
    t.map_tile,
    t.map_label,
    n.geom
  FROM noded n
  INNER JOIN snapped t
  ON ST_Intersects(n.geom, t.geom)
  ORDER BY n.id, ST_Length(ST_Intersection(n.geom, t.geom)) DESC
)

INSERT INTO ften_active
(map_tile, map_label, geom)
SELECT
  map_tile,
  map_label,
  geom
FROM noded_attrib;