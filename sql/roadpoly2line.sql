-- ---------------
-- For given tile, convert input polygons to lines, loading to specified output table
--
-- psql accessible variables:
--
-- tile      - bcgs_20k_grid map_tile
-- in_table  - input table with road geoms (Polygon/Multipolygon, 3005)
-- out_table - output table with map_tile column and linestring 3005 geom column

--
-- Note that this query requires two additional functions:
--
-- 1. ST_ApproximateMedialAxisIgnoreErrors
-- Skip/note features with touching interior rings (eg donut hole that touches
-- exterior at a single point). The bare ST_ApproximateMedialAxis will bail on these
-- valid features - https://github.com/Oslandia/SFCGAL/issues/138)
--
-- 2. ST_FilterRings
-- Filter out small interior rings.
-- Simply using the exterior ring of input polygons would be nicer but input features
-- from RESULTS can be very complex. Filtering out small interior rings helps smooth
-- out the processing but is very slow - this is the bottleneck in this process.
-- ---------------

-- extract features from tile
WITH tile AS
(SELECT
  (ST_Dump(geom)).geom as geom
FROM (
  SELECT
    CASE
      WHEN ST_CoveredBy(ST_MakeValid(r.geom), ST_Buffer(t.geom, 10)) THEN r.geom
      ELSE ST_Intersection(ST_Buffer(t.geom, 10), ST_MakeValid(r.geom))
    END AS geom
  FROM whse_forest_vegetation.rslt_forest_cover_inv_svw r
  INNER JOIN whse_basemapping.bcgs_20k_grid t
  ON ST_Intersects(r.geom, t.geom)
  WHERE t.map_tile = :'tile'
) as f
WHERE ST_Dimension(geom) = 2
),

-- clean the geometries
-- note that the st_subdivide will create small gaps in the output roads
cleaned AS
(
  SELECT
      (ST_Dump(                       -- singlepart
        ST_MakeValid(                 -- clean
          ST_ForceRHR(                -- clean
           -- ST_FilterRings(geom, 50)  -- remove holes <50m area -- this is too slow, just leave the holes for now
          geom
          )
        )
      )).geom
     as geom
  FROM tile
),

-- convert to lines
lines AS
(
  SELECT
    (ST_Dump(
      ST_ApproximateMedialAxisIgnoreErrors(geom)
      )
    ).geom as geom
  FROM cleaned
),

-- cut to tile (because a slightly buffered tile is used above)
cut_to_tile AS
(
  SELECT
    row_number() over() as id,
    CASE
      WHEN ST_CoveredBy(r.geom, t.geom) THEN r.geom
      ELSE ST_Intersection(t.geom, r.geom)
    END AS geom
  FROM lines r
  INNER JOIN whse_basemapping.bcgs_20k_grid t
  ON ST_Intersects(r.geom, t.geom)
  WHERE t.map_tile = :'tile'
)

-- find obvious duplicates
-- this slows things down too much
/*
dups AS
(
  SELECT
   a.id as id_a,
   b.id as id_b
  FROM cut_to_tile a
  INNER JOIN cut_to_tile b
  ON ST_Equals(a.geom, b.geom)
  WHERE a.id < b.id
)

-- insert all lines >= 7m
-- (removes artifacts at curves in input polys)
-- try and merge the output lines
INSERT INTO :out_table
(
  map_tile,
  geom
)
SELECT
  :'tile' as map_tile,
  geom
FROM
(
SELECT
    (ST_Dump(ST_Linemerge(ST_Collect(geom)))).geom as geom
FROM cut_to_tile a
LEFT OUTER JOIN dups b
ON a.id = b.id_b
WHERE b.id_b IS NULL
) as f
WHERE ST_length(a.geom) >= 7;
*/

INSERT INTO :out_table
(
  map_tile,
  geom
)
-- insert all lines >= 7m (after merging the lines)
SELECT
  :'tile' as map_tile,
  geom
FROM
(
  SELECT (ST_Dump(ST_Linemerge(ST_Collect(geom)))).geom as geom
  FROM cut_to_tile
) as f
WHERE ST_Length(geom) >= 7;