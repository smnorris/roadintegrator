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