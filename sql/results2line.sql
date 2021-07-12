-- extract features from tile
WITH tile AS
(SELECT
  map_tile,
  forest_cover_id,
  (ST_Dump(geom)).geom as geom
FROM (
  SELECT
   r.forest_cover_id,
   t.map_tile,
    CASE
      WHEN ST_CoveredBy(r.geom, t.geom) THEN r.geom
      ELSE ST_Intersection(t.geom, r.geom)
    END AS geom
  FROM whse_forest_vegetation.rslt_forest_cover_inv_svw r
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
      map_tile,
      forest_cover_id,
      (ST_Dump(ST_ApproximateMedialAxis(
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

INSERT INTO results
(
  map_tile,
  geom
)

-- insert all lines >= 6m (removing artifacts at curves in input polys)
SELECT
  :'tile' as map_tile,
  geom
FROM lines l1
WHERE ST_Length(geom) >= 6



-- We could insert *all* lines and post process the results to remove only
-- dangles less than 6m (segment intersects only 1 other segment). But this
-- is fairly resource intensive and does not seem worth the processing time,
-- <6m lines are rarely integral parts of the line network output from
-- ApproximateMedialAxis
-- Something like this might work:

--  SELECT
--    l1.id,
--    l2.id as match
--  FROM lines l1
--  INNER JOIN lines l2
--  ON ST_Intersects(l1.geom, l2.geom)
--  WHERE ST_Length(l1.geom) < 6
--  AND l1.id != l2.id
--  GROUP BY l1.id, l2.id
--  HAVING count(*) > 1
--) r ON l.id = r.id