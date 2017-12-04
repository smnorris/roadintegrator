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
WITH tile AS
  (SELECT
       b.map_tile,
       CASE
         WHEN ST_CoveredBy(a.geom, b.geom) THEN a.geom
         ELSE ST_Safe_Repair(
                ST_Multi(
                  ST_CollectionExtract(
                    ST_Safe_Intersection(a.geom, b.geom),
                    3)
                  )
                )
       END as geom
     FROM $src_table a
     INNER JOIN tiles_20k b
     ON ST_Intersects(a.geom, b.geom)
     WHERE b.map_tile = %s)

-- clean extracted polygon data
-- buffer slightly and simplify by 1m - medial axis is an approximation anyway
INSERT INTO $out_table
  (map_tile, geom)
SELECT
   map_tile,
   ST_Safe_Repair(
     ST_SnapToGrid(
       ST_SimplifyPreserveTopology(
         ST_Buffer(
           (ST_Dump(
              ST_Buffer(
                ST_Collect(geom), .01))).geom, .01), 1), .001)) as geom
FROM tile
GROUP BY map_tile