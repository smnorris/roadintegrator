DROP TABLE IF EXISTS ften_retired;

CREATE TABLE ften_retired
(map_label character varying primary key, geom geometry(Geometry,3005));

INSERT INTO ften_retired
SELECT
  map_label,
  geom
FROM whse_forest_tenure.ften_road_section_lines_svw
WHERE life_cycle_status_code = 'RETIRED';

CREATE INDEX on ften_active USING GIST (geom);