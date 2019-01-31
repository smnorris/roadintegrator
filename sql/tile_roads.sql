-- extract data for given tile
INSERT INTO $out_table
  ($fields, map_tile, geom)

SELECT * FROM
  (SELECT
    $fields,
    b.map_tile,
    CASE
      WHEN ST_CoveredBy(a.geom, b.geom) THEN ST_Multi(a.geom)
      ELSE  ST_Multi(
               ST_CollectionExtract(
                 ST_Safe_Intersection(a.geom, b.geom),
                 2)
               )
   END as geom
  FROM $src_table a
  INNER JOIN tiles_20k b
  ON ST_Intersects(a.geom, b.geom)
  WHERE b.map_tile = %s) as foo
WHERE st_length(geom) > .01