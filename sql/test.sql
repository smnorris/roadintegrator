-- extract data for given tile
WITH tile AS
  (SELECT
       b.map_tile,
       CASE
         WHEN ST_CoveredBy(a.geom, b.geom) THEN a.geom
         ELSE ST_Safe_Repair(
                ST_Multi(
                  ST_CollectionExtract(
                    ST_Safe_Intersection(a.geom, b.geom
                          ), 3)))
       END as geom
     FROM results_src a
     INNER JOIN tiles_20k b
     ON ST_Intersects(a.geom, b.geom)
     WHERE b.map_tile = '082E014'),

-- clean extracted polygon data
-- buffer slightly and simplify by 1m - medial axis is an approximation anyway
cleaned AS
(SELECT
   map_tile,
   ST_Safe_Repair(
     ST_SnapToGrid(
       ST_SimplifyPreserveTopology(
         ST_Buffer(
           (ST_Dump(
              ST_Buffer(
                ST_Collect(geom), 0))).geom, .1), 1), .001)) as geom
 FROM tile
GROUP BY map_tile)

-- create medial axis for polys > 10sqm

SELECT
  map_tile,
  ST_ApproximateMedialAxis(ST_ForceRHR(filter_rings(geom, 10))) as geom
FROM cleaned
WHERE ST_Area(geom) > 10;