-- -----------------------
-- name: dra_src!
-- Reload all DRA features (unsegmented)
-- -----------------------

INSERT INTO integratedroads
(
  map_tile,
  transport_line_id,
  geom
)

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
WHERE ST_Dimension(geom) = 1;

