-- Load roads that are not covered by 7m buffer of higher priority roads

-- cut source roads to tile, make sure they are singlepart
WITH tile AS
(
  SELECT row_number() over() as id, *
  FROM (
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
    WHERE ST_Dimension(geom) = 1
  ) AS b
),

-- find higher priority roads within 7m of the roads selected above, buffer them
buff AS
(SELECT
    ST_Union(ST_Buffer(i.geom, 7)) as geom
  FROM tile t
  INNER JOIN integratedroads i
  ON ST_DWithin(t.geom, i.geom, 8)
  WHERE i.map_tile = :'tile'
),

-- cut the low priority roads by the buffers
diff AS
(
  SELECT
    r.id,
    r.map_tile,
    r.:pk,
    (ST_Dump(ST_Difference(r.geom, b.geom))).geom as geom
  FROM tile r
  INNER JOIN buff b ON ST_Intersects(r.geom, b.geom)
),

-- get low priority roads that do not intersect the buffs
new AS
(
  SELECT
    r.id,
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
FROM diff
WHERE ST_Dimension(geom) = 1
AND ST_Length(geom) > 5
UNION ALL
SELECT
  map_tile,
  :pk,
  geom
FROM new
WHERE ST_Dimension(geom) = 1;