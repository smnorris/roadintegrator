INSERT INTO $out_table
  (map_tile, geom)
SELECT
  map_tile,
  ST_Safe_Repair(
    ST_SnapToGrid(
      ST_SimplifyPreserveTopology(
        ST_Safe_Repair(
          (ST_Dump(
            ST_Buffer(
              (ST_Dump(geom)).geom,
            .01)
          )).geom
        ),
      1),
    .01)
  )
FROM
(SELECT
  b.map_tile,
  CASE
   WHEN ST_CoveredBy(a.geom, b.geom) THEN a.geom
   ELSE ST_CollectionExtract(
          ST_Safe_Intersection(a.geom, b.geom),
        3)
  END as geom
FROM $src_table a
INNER JOIN tiles_20k b
ON ST_Intersects(a.geom, b.geom)
WHERE b.map_tile = %s) as t