-- test.sql
-- used for debugging tiles that bail, generally where geom needed to be cleaned

DROP TABLE IF EXISTS temp.results_roads_test;

CREATE TABLE temp.results_roads_test
(results_roads_id SERIAL PRIMARY KEY,
  map_tile text,
  geom geometry);

WITH road_polys_prelim AS
(SELECT
   map_tile,
   -- clean the input polys
   -- the key is to generously simplify them, medial axis is an approximation anyway
   ST_MakeValid(
     ST_SnapToGrid(
       ST_SimplifyPreserveTopology(
         ST_Buffer(
            (ST_Dump(
              ST_Union(geom))).geom, .1), 1), .001)) as geom
 FROM
    -- grab data from given tile
    (SELECT
       b.map_tile,
       CASE
         WHEN ST_CoveredBy(a.geom, b.geom) THEN a.geom
         ELSE ST_MakeValid(ST_Multi(ST_CollectionExtract(ST_Intersection(
                          a.geom, b.geom
                          ), 3)))
       END as geom
     FROM temp.rslt_forest_cover_inv_svw a
     INNER JOIN whse_basemapping.bcgs_20k_grid b
     ON ST_Intersects(a.geom, b.geom)
     WHERE b.map_tile = '092G062') as foo
GROUP BY map_tile),

-- dump really small polys
road_polys AS
(SELECT * FROM road_polys_prelim WHERE ST_Area(geom) > 10)

INSERT INTO temp.results_roads_test
  (map_tile, geom)
SELECT
  r.map_tile,
  --r.geom
  ST_ApproximateMedialAxis(ST_ForceRHR(filter_rings(r.geom, 10))) as geom
FROM road_polys r
