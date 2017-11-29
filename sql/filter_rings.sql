-- Copyright 2017 Province of British Columbia
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--
-- See the License for the specific language governing permissions and limitations under the License.

-- ----------------------------------------------------------------------------------------------------

-- Credit for this function:
-- http://www.spatialdbadvisor.com/postgis_tips_tricks/92/filtering-rings-in-polygon-postgis
CREATE OR REPLACE FUNCTION filter_rings(geometry,FLOAT) RETURNS geometry AS
$$ SELECT ST_BuildArea(ST_Collect(d.built_geom)) AS filtered_geom
     FROM (SELECT ST_BuildArea(ST_Collect(c.geom)) AS built_geom
             FROM (SELECT b.geom
                     FROM (SELECT (ST_DumpRings(ST_GeometryN(ST_Multi($1),/*ST_Multi converts any Single Polygons to MultiPolygons */
                                                            generate_series(1,ST_NumGeometries(ST_Multi($1)) )
                                                            ))).*
                           ) b
                    WHERE b.path[1] = 0 OR
                         (b.path[1] > 0 AND ST_Area(b.geom) > $2)
                   ) c
           ) d
$$
LANGUAGE 'sql' IMMUTABLE;