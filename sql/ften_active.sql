DROP TABLE IF EXISTS ften_active;

CREATE TABLE ften_active
(map_label character varying primary key, geom geometry(Geometry,3005));

INSERT INTO ften_active
SELECT
  map_label,
  geom
FROM whse_forest_tenure.ften_road_section_lines_svw
WHERE life_cycle_status_code = 'ACTIVE';

CREATE INDEX on ften_active USING GIST (geom);