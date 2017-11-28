-- create medial axis for polys > 10sqm
INSERT INTO $out_table
  (map_tile, geom)
SELECT
  map_tile,
  ST_ApproximateMedialAxis(ST_ForceRHR(filter_rings(geom, 10))) as geom
FROM $src_table
WHERE ST_Area(geom) > 10
AND map_tile = %s