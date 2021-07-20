-- name: create_output#
-- Create the empty output table

DROP TABLE IF EXISTS integratedroads;

CREATE TABLE integratedroads (
    integratedroads_id serial primary key,
    bcgw_source character varying,
    map_tile character varying,
    transport_line_id integer,
    map_label character varying,
    results_id integer,
    road_section_line_id integer,
    og_petrlm_dev_rd_pre06_pub_id integer,
    og_road_segment_permit_id integer,
    og_permits_row_id integer,
    geom geometry(Linestring, 3005)
);

CREATE INDEX ON integratedroads USING GIST (geom);