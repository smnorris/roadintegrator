-- -----------------------
-- name: get_tiles
-- -----------------------

SELECT 
  map_tile
FROM whse_basemapping.bcgs_20k_grid
WHERE map_tile = '092C050'--LIKE '092C%%'
LIMIT 1;