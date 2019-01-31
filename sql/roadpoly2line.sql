-- create medial axis for polys > 10sqm
INSERT INTO $out_table
  (map_tile, geom)
SELECT
  map_tile,
  ST_ApproximateMedialAxis(
    ST_ForceRHR(
      ST_Filter_Rings(geom, 10)  -- remove holes <10m area
    )
  ) as geom
FROM $src_table
WHERE ST_Area(geom) > 10  -- don't bother processing polys <10m area
AND map_tile = %s