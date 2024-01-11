-- -----------------------
-- Load highest priority features (DRA)
-- These features are unchanged, with 2 exceptions:
--   - cut to tiles
--   - vertices added at 10m intervals to improve snapping results
-- -----------------------

WITH tile AS (

  SELECT
    map_tile,
    transport_line_id,
    (ST_Dump(geom)).geom as geom
  FROM (
    SELECT
     t.map_tile,
     r.transport_line_id,
      CASE
        WHEN ST_CoveredBy(r.geom, t.geom) THEN ST_Force2D(r.geom)
        ELSE ST_Force2D(ST_Intersection(t.geom, r.geom))
      END AS geom
    FROM whse_basemapping.transport_line r
    INNER JOIN whse_basemapping.bcgs_20k_grid t
    ON ST_Intersects(r.geom, t.geom)
    WHERE t.map_tile LIKE :'tile'||'%'
  ) as f
  WHERE ST_Dimension(geom) = 1
)

INSERT INTO integratedroads
(
  transport_line_id,
  map_tile,
  geom
)
SELECT
  transport_line_id,
  map_tile,
  geom
  --ST_Segmentize(geom, 10) as geom
FROM tile;