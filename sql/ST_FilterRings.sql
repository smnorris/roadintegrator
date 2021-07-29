-- Remove holes from polygons smaller than specified size
-- https://www.spdba.com.au/filtering-rings-in-polygon-postgis
-- Note that this is VERY slow.
CREATE OR REPLACE FUNCTION ST_FilterRings(geometry,FLOAT) RETURNS geometry AS
$$ SELECT ST_BuildArea(ST_Collect(d.built_geom)) AS filtered_geom
     FROM
     (SELECT
        ST_BuildArea(ST_Collect(c.geom)) AS built_geom
        FROM
        (SELECT b.geom
         FROM
           (SELECT
             (ST_DumpRings(
                ST_GeometryN(
                  ST_Multi($1),
                    generate_series(1,
                      ST_NumGeometries(
                        ST_Multi($1)))))).*
                           ) b
         WHERE b.path[1] = 0
         OR (b.path[1] > 0 AND ST_Area(b.geom) > $2)
          ) c
      ) d
$$
LANGUAGE 'sql' IMMUTABLE;


