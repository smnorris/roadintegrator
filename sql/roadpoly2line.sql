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
-- out the processing.
-- ---------------

-- extract features from tile
WITH tile AS
(SELECT
  (ST_Dump(geom)).geom as geom
FROM (
  SELECT
    CASE
      WHEN ST_CoveredBy(r.geom, t.geom) THEN r.geom
      ELSE ST_Intersection(t.geom, r.geom)
    END AS geom
  FROM :in_table r
  INNER JOIN whse_basemapping.bcgs_20k_grid t
  ON ST_Intersects(r.geom, t.geom)
  WHERE t.map_tile = :'tile'
) as f
WHERE ST_Dimension(geom) = 2
),

-- convert to lines, merge the lines
lines AS
(
  SELECT
   row_number() over() AS id,
   (ST_Dump(ST_Linemerge(ST_Collect(geom)))).geom as geom
  FROM (
    SELECT
      (ST_Dump(
        ST_ApproximateMedialAxisIgnoreErrors(
          ST_MakeValid(
            ST_ForceRHR(
              ST_FilterRings(geom, 10)  -- remove holes <10m area
          )
        )
      ))).geom as geom
    FROM tile
    WHERE ST_Area(geom) > 10  -- don't bother processing polys <10m area
  ) as f
)

INSERT INTO :out_table
(
  map_tile,
  geom
)

-- insert all lines >= 6m (removing artifacts at curves in input polys)
-- We could also search the <6m segments for lines that intersect 2 other
-- lines to ensure all parts of network are included.
-- Don't bother with this for now
SELECT
  :'tile' as map_tile,
  geom
FROM lines l1
WHERE ST_Length(geom) >= 6
