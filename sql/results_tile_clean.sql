-- extract data for given tile
WITH tile AS
  (SELECT
       b.map_tile,
       CASE
         WHEN ST_CoveredBy(a.geom, b.geom) THEN a.geom
         ELSE ST_Safe_Repair(
                ST_Multi(
                  ST_CollectionExtract(
                    ST_Safe_Intersection(a.geom, b.geom),
                    3)
                  )
                )
       END as geom
     FROM $src_table a
     INNER JOIN tiles_20k b
     ON ST_Intersects(a.geom, b.geom)
     WHERE b.map_tile = %s)

-- clean extracted polygon data
-- buffer slightly and simplify by 1m - medial axis is an approximation anyway
INSERT INTO $out_table
  (map_tile, geom)
SELECT
   map_tile,
   ST_Safe_Repair(
     ST_SnapToGrid(
       ST_SimplifyPreserveTopology(
         ST_Buffer(
           (ST_Dump(
              ST_Buffer(
                ST_Collect(geom), .01))).geom, .01), 1), .001)) as geom
FROM tile
GROUP BY map_tile