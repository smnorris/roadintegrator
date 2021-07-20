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
      AND r.life_cycle_status_code = 'RETIRED'
    ) as f
    WHERE ST_Dimension(geom) = 1
  ) as b
),

-- clean the data a bit more, snapping endpoints to same-source features within 5m
snapped_endpoints AS
(
  SELECT
    a.id,
    a.map_label,
    st_distance(st_endpoint(a.geom), b.geom) as dist_end,
    st_distance(st_startpoint(a.geom), b.geom) as dist_start,
    -- We want to snap endpoints of a to the closest position of line b.
    -- Below simple ST_Snap() works ok in many cases... but we should
    -- use ST_LineLocatePoint() / ST_LineInterpolatePoint instead, to ensure
    -- it is actually/only the endpoint of a that is getting snapped to the closest
    -- point on line b
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
    ON t.id = s.id
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
  INNER JOIN src t
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