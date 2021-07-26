-- Load roads that are not covered by 7m buffer of higher priority roads

-- cut source roads to tile, make sure they are singlepart
WITH tile AS
(
  SELECT
    map_tile,
    :pk,
    (ST_Dump(geom)).geom as geom
  FROM (
    SELECT
     t.map_tile,
     r.:pk,
      CASE
        WHEN ST_CoveredBy(r.geom, t.geom) THEN ST_Force2D(r.geom)
        ELSE ST_Force2D(ST_Intersection(t.geom, r.geom))
      END AS geom
    FROM :src_roads r
    INNER JOIN whse_basemapping.bcgs_20k_grid t
    ON ST_Intersects(r.geom, t.geom)
    WHERE t.map_tile = :'tile'
  ) as f
),

-- find higher priority roads within 7m of the roads selected above
higher_priority AS
(SELECT
    i.geom
  FROM tile t
  INNER JOIN integratedroads i
  ON ST_DWithin(t.geom, i.geom, 8)
  WHERE i.map_tile = :'tile'
),

-- buffer the higher priority roads
buff AS
(
  SELECT ST_Union(ST_Buffer(geom, 7)) as geom
  FROM higher_priority
),

-- cut the low priority roads by the buffers
diff AS
(
  SELECT row_number() over() as id, *
  FROM (
    SELECT
      r.map_tile,
      r.:pk,
      (ST_Dump(ST_Difference(r.geom, b.geom))).geom as geom
    FROM tile r
    INNER JOIN buff b ON ST_Intersects(r.geom, b.geom)
  WHERE ST_Dimension(r.geom) = 1
  ) as f
  WHERE ST_Dimension(geom) = 1
  AND ST_Length(geom) > 7
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
FROM diff a
CROSS JOIN LATERAL (
  SELECT
    id,
    ST_Distance(ST_StartPoint(a.geom), b.geom) as dist,
    geom
  FROM higher_priority b
  WHERE ST_Distance(ST_Startpoint(a.geom), b.geom) > 0
  ORDER BY ST_StartPoint(a.geom) <-> b.geom
  LIMIT 1
) as nn
INNER JOIN whse_basemapping.bcgs_20k_grid t
ON a.map_tile = t.map_tile
WHERE nn.dist <= 7.01
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
FROM diff a
CROSS JOIN LATERAL (
  SELECT
    id,
    ST_Distance(ST_EndPoint(a.geom), b.geom) as dist,
    geom
  FROM higher_priority b
  WHERE ST_Distance(ST_Endpoint(a.geom), b.geom) > 0
  ORDER BY ST_EndPoint(a.geom) <-> b.geom
  LIMIT 1
) as nn
INNER JOIN whse_basemapping.bcgs_20k_grid t
ON a.map_tile = t.map_tile
WHERE nn.dist <= 7.01
AND NOT ST_DWithin(ST_Endpoint(a.geom), ST_ExteriorRing(t.geom), .1) -- do not snap endpoints created at tile intersections
),

-- do not snap existing vertices to target, add new vertices at the ends of the lines
snapped AS
(
  SELECT
    a.id,
    a.map_tile,
    a.:pk,
    CASE
      WHEN s.id IS NOT NULL AND e.id IS NULL                        -- add vertex at start
      THEN ST_AddPoint(a.geom, s.geom, 0)
      WHEN s.id IS NOT NULL AND e.id IS NOT NULL                    -- add vertex at end
      THEN ST_AddPoint(ST_Addpoint(a.geom, s.geom, 0), e.geom, -1)
      WHEN s.id IS NULL AND e.id IS NOT NULL                        -- add vertex at start and end
      THEN ST_Addpoint(a.geom, e.geom, -1)
      ELSE a.geom
    END as geom
  FROM diff a
  LEFT JOIN start_snapped s ON a.id = s.id
  LEFT JOIN end_snapped e ON a.id = e.id
),

-- get low priority roads that do not intersect the buffs
new AS
(
  SELECT
    r.map_tile,
    r.:pk,
    r.geom
  FROM tile r
  INNER JOIN buff b
  ON ST_Intersects(r.geom, b.geom) IS FALSE
)

-- and insert
INSERT INTO integratedroads
(map_tile, :pk, geom)
SELECT
  map_tile,
  :pk,
  geom
FROM snapped
WHERE ST_Dimension(geom) = 1
AND ST_Length(geom) > 5
UNION ALL
SELECT
  map_tile,
  :pk,
  geom
FROM new
WHERE ST_Dimension(geom) = 1;