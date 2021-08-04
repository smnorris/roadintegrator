.PHONY: all db clean

GENERATED_FILES = .whse_basemapping.bcgs_20k_grid \
data/dgtl_road_atlas.gdb \
.whse_basemapping.transport_line \
.whse_basemapping.transport_line_structure_code \
.whse_basemapping.transport_line_type_code \
.whse_basemapping.transport_line_surface_code \
.whse_forest_tenure.ften_road_section_lines_svw \
.whse_forest_vegetation.rslt_forest_cover_inv_svw \
.whse_forest_tenure.abr_road_section_line \
.whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp \
.whse_mineral_tenure.og_road_segment_permit_sp \
.whse_mineral_tenure.og_road_area_permit_sp \
.ften_active \
.ften_retired \
.results \
.og_permits_row \
.integratedroads \
.integratedroads_vw \
integratedroads.gpkg.zip \
summary.md


# Make all targets
all: $(GENERATED_FILES)

# Remove all generated targets, stop and delete the db container
clean:
	rm -Rf $(GENERATED_FILES)
	docker stop roadintegrator-db
	docker rm roadintegrator-db

# shortcut to bcdata command with correct port specified
bc2pg := bcdata bc2pg --db_url postgresql://$(PGUSER):$(PGPASSWORD)@$(PGHOST):$(PGPORT)/$(PGDATABASE)

# create db docker container and add required extensions and functions
db:
	docker pull postgis/postgis:13-master
	docker run --name roadintegrator-db \
	  -e POSTGRES_PASSWORD=$(PGPASSWORD) \
	  -e POSTGRES_USER=$(PGUSER) \
	  -e PG_DATABASE=$(PGDATABASE) \
	  -p ${PGPORT}:5432 \
	  -d postgis/postgis:13-master
	sleep 5  # wait for the db to come up
	psql -c "CREATE DATABASE $(PGDATABASE)" postgres
	psql -c "CREATE EXTENSION postgis"
	psql -c "CREATE EXTENSION postgis_sfcgal"
	psql -f sql/ST_ApproximateMedialAxisIgnoreErrors.sql

# load 20k tiles
.whse_basemapping.bcgs_20k_grid:
	$(bc2pg) WHSE_BASEMAPPING.BCGS_20K_GRID --fid MAP_TILE
	touch $@

# download DRA
data/dgtl_road_atlas.gdb:
	wget --trust-server-names -qNP data ftp://ftp.geobc.gov.bc.ca/sections/outgoing/bmgs/DRA_Public/dgtl_road_atlas.gdb.zip
	unzip -qun -d data "data/dgtl_road_atlas.gdb.zip"
	rm data/dgtl_road_atlas.gdb.zip

# load DRA to db
.whse_basemapping.transport_line: data/dgtl_road_atlas.gdb
	ogr2ogr \
	  -f PostgreSQL \
	  "PG:host=$(PGHOST) user=$(PGUSER) dbname=$(PGDATABASE) port=$(PGPORT)" \
	  -overwrite \
	  -lco GEOMETRY_NAME=geom \
	  -lco FID=transport_line_id \
	  -nln whse_basemapping.transport_line \
	  -where "TRANSPORT_LINE_SURFACE_CODE <> 'B'" \
	  data/dgtl_road_atlas.gdb \
	  TRANSPORT_LINE
	# Because we are not loading this table via bc2pg, no record is added to bcdata table.
	# Do this manually here so we know what day this data was extracted
	psql -c "INSERT INTO bcdata (table_name, date_downloaded) \
	   SELECT 'whse_basemapping.transport_line', CURRENT_TIMESTAMP \
	   ON CONFLICT (table_name) DO \
	   UPDATE SET date_downloaded = EXCLUDED.date_downloaded;"
	touch $@

# load DRA structure/type/surface lookups
.whse_basemapping.transport_line_structure_code: data/dgtl_road_atlas.gdb
	ogr2ogr \
	  -f PostgreSQL \
	  "PG:host=$(PGHOST) user=$(PGUSER) dbname=$(PGDATABASE) port=$(PGPORT)" \
	  -overwrite \
	  -nln whse_basemapping.transport_line_structure_code \
	  data/dgtl_road_atlas.gdb \
	  TRANSPORT_LINE_STRUCTURE_CODE
	touch $@

.whse_basemapping.transport_line_type_code: data/dgtl_road_atlas.gdb
	ogr2ogr \
	  -f PostgreSQL \
	  "PG:host=$(PGHOST) user=$(PGUSER) dbname=$(PGDATABASE) port=$(PGPORT)" \
	  -overwrite \
	  -nln whse_basemapping.transport_line_type_code \
	  data/dgtl_road_atlas.gdb \
	  TRANSPORT_LINE_TYPE_CODE
	touch $@

.whse_basemapping.transport_line_surface_code: data/dgtl_road_atlas.gdb
	ogr2ogr \
	  -f PostgreSQL \
	  "PG:host=$(PGHOST) user=$(PGUSER) dbname=$(PGDATABASE) port=$(PGPORT)" \
	  -overwrite \
	  -nln whse_basemapping.transport_line_surface_code \
	  data/dgtl_road_atlas.gdb \
	  TRANSPORT_LINE_SURFACE_CODE
	touch $@

# ften roads
.whse_forest_tenure.ften_road_section_lines_svw:
	$(bc2pg) WHSE_FOREST_TENURE.FTEN_ROAD_SECTION_LINES_SVW \
	  --fid MAP_LABEL \
	  --query "LIFE_CYCLE_STATUS_CODE IN ('ACTIVE','RETIRED')"
	touch $@

# Results road polygons
.whse_forest_vegetation.rslt_forest_cover_inv_svw:
	$(bc2pg) WHSE_FOREST_VEGETATION.RSLT_FOREST_COVER_INV_SVW \
  	--fid FOREST_COVER_ID \
  	--query "STOCKING_STATUS_CODE = 'NP' AND STOCKING_TYPE_CODE IN ('RD','UNN') \
  	         AND SILV_POLYGON_NUMBER NOT IN ('landing', 'lnd') AND GEOMETRY_EXIST_IND = 'Y'"
	touch $@

# As-built roads
# **NOTE**
# data/ABR.gdb must be manually downloaded before running
.whse_forest_tenure.abr_road_section_line: data/ABR.gdb
	ogr2ogr -f PostgreSQL \
	  "PG:host=$(PGHOST) user=$(PGUSER) dbname=$(PGDATABASE) port=$(PGPORT)" \
	  -overwrite \
	  -t_srs EPSG:3005 \
	  -lco GEOMETRY_NAME=geom \
	  -lco FID=ROAD_SECTION_LINE_ID \
	  -nln whse_forest_tenure.abr_road_section_line \
	  data/ABR.gdb \
	  ABR_ROAD_SECTION_LINE
	# Because we are not loading this table via bc2pg, no record is added to bcdata table.
	# Do this manually here so we know what day this data was extracted
	psql -c "INSERT INTO bcdata (table_name, date_downloaded) \
	   SELECT 'whse_forest_tenure.abr_road_section_line', CURRENT_TIMESTAMP \
	   ON CONFLICT (table_name) DO \
	   UPDATE SET date_downloaded = EXCLUDED.date_downloaded;"
	touch $@

# Oil and Gas Dev, pre06
.whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp:
	$(bc2pg) WHSE_MINERAL_TENURE.OG_PETRLM_DEV_RDS_PRE06_PUB_SP \
	  --fid OG_PETRLM_DEV_RD_PRE06_PUB_ID
	touch $@

# Oil and Gas permits, road segments
.whse_mineral_tenure.og_road_segment_permit_sp:
	$(bc2pg) WHSE_MINERAL_TENURE.OG_ROAD_SEGMENT_PERMIT_SP \
	  --fid OG_ROAD_SEGMENT_PERMIT_ID
	touch $@

# Oil and Gas permits, road right of way (polygons)
.whse_mineral_tenure.og_road_area_permit_sp:
	$(bc2pg) WHSE_MINERAL_TENURE.OG_ROAD_AREA_PERMIT_SP \
  	  --fid OG_ROAD_AREA_PERMIT_ID
	touch $@

## preprocessing

# clean active ften roads
.ften_active: .whse_forest_tenure.ften_road_section_lines_svw
	psql -c "CREATE TABLE ften_active \
	( ften_active_id serial primary key, \
	  map_label character varying, \
	  map_tile character varying, \
	  geom geometry(Linestring,3005));"
	psql -tXA \
	-c "SELECT DISTINCT map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_forest_tenure.ften_road_section_lines_svw r \
	    ON ST_Intersects(t.geom, r.geom) \
	    WHERE life_cycle_status_code = 'ACTIVE' \
	    ORDER BY map_tile" \
	    | parallel --progress --joblog $@.log \
	      psql -f sql/ften_active.sql -v tile={1}
	psql -c "CREATE INDEX on ften_active USING GIST (geom);"
	touch $@

# clean retired ften roads
.ften_retired: .whse_forest_tenure.ften_road_section_lines_svw
	psql -c "CREATE TABLE ften_retired \
	( ften_retired_id serial primary key, \
	  map_label character varying, \
	  map_tile character varying, \
	  geom geometry(Linestring,3005));"
	psql -tXA \
	-c "SELECT DISTINCT map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_forest_tenure.ften_road_section_lines_svw r \
	    ON ST_Intersects(t.geom, r.geom) \
	    WHERE life_cycle_status_code = 'RETIRED' \
	    ORDER BY map_tile" \
	    | parallel --progress --joblog $@.log \
	      psql -f sql/ften_retired.sql -v tile={1}
	psql -c "CREATE INDEX on ften_retired USING GIST (geom);"
	touch $@

# convert RESULTS polygon roads to lines
.results: .whse_forest_vegetation.rslt_forest_cover_inv_svw
	psql -c "CREATE TABLE results \
	( results_id serial primary key, \
	  map_tile character varying, \
	  geom geometry(Linestring, 3005))"
	psql -tXA \
	-c "SELECT DISTINCT t.map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_forest_vegetation.rslt_forest_cover_inv_svw r \
	    ON ST_Intersects(t.geom, r.geom) \
	    WHERE ST_ISValid(r.geom) \
	    ORDER BY t.map_tile" \
	    | parallel --progress --joblog $@.log \
	      psql -f sql/roadpoly2line.sql \
	        -v tile={1} \
	        -v in_table=whse_forest_vegetation.rslt_forest_cover_inv_svw \
	        -v out_table=results
	psql -c "CREATE INDEX ON results USING GIST (geom)"
	touch $@

# convert OG permit right of ways (poly) to lines
.og_permits_row: .whse_mineral_tenure.og_road_area_permit_sp
	psql -c "CREATE TABLE og_permits_row \
	( og_permits_row_id serial primary key, \
	  map_tile character varying, \
	  geom geometry(Linestring, 3005))"
	psql -tXA \
	-c "SELECT DISTINCT t.map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_mineral_tenure.og_road_area_permit_sp r \
	    ON ST_Intersects(t.geom, r.geom) \
	    ORDER BY t.map_tile" \
	     | parallel --progress --joblog $@.log \
	       psql -f sql/roadpoly2line.sql \
	       -v tile={1} \
	       -v in_table=whse_mineral_tenure.og_road_area_permit_sp \
	       -v out_table=og_permits_row
	psql -c "CREATE INDEX ON og_permits_row USING GIST (geom)"
	touch $@

# load data to integratedroads table
.integratedroads: .whse_basemapping.transport_line .ften_active .ften_active .results .whse_forest_tenure.abr_road_section_line .whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp .whse_mineral_tenure.og_road_segment_permit_sp .og_permits_row
	# create output table
	psql -f sql/integratedroads.sql

	# load DRA (just dump everything in, these features remain unchanged)
	psql -tXA \
	-c "SELECT DISTINCT \
	      substring(t.map_tile from 1 for 4) as map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_basemapping.transport_line r \
	    ON ST_Intersects(t.geom, r.geom) \
	    ORDER BY substring(t.map_tile from 1 for 4)" \
	    | parallel psql -f sql/dra.sql -v tile={1}

	# load all other sources
	./integrateroads.sh

	# index the foreign keys for faster joins back to source tables
	psql -c "CREATE INDEX ON integratedroads (transport_line_id)"
	psql -c "CREATE INDEX ON integratedroads (map_label)"
	psql -c "CREATE INDEX ON integratedroads (road_section_line_id)"
	psql -c "CREATE INDEX ON integratedroads (og_petrlm_dev_rd_pre06_pub_id)"
	psql -c "CREATE INDEX ON integratedroads (og_road_segment_permit_id)"
	touch $@

.integratedroads_vw: .integratedroads
	# and finally create output view with required data/columns
	psql -f sql/integratedroads_vw.sql
	touch $@

# dump to geopackage
integratedroads.gpkg.zip: .integratedroads_vw
	ogr2ogr \
    -f GPKG \
    -progress \
    -nlt LINESTRING \
    -nln integratedroads \
    -lco GEOMETRY_NULLABLE=NO \
    -sql "SELECT * FROM integratedroads_vw" \
    integratedroads.gpkg \
    "PG:host=$(PGHOST) user=$(PGUSER) dbname=$(PGDATABASE) port=$(PGPORT)" \

	# summarize road source by length and percentage in the output gpkg
	ogr2ogr \
	  -f GPKG \
	  -progress \
	  -update \
	  -nln bcgw_source_summary \
	-sql "WITH total AS \
	( \
	  SELECT SUM(ST_Length(geom)) AS total_length \
	  FROM integratedroads_vw \
	) \
	SELECT \
	  bcgw_source, \
	  to_char(bcgw_extraction_date, 'YYYY-MM-DD') as bcgw_extraction_date, \
	  ROUND((SUM(ST_Length(geom) / 1000)::numeric))  AS length_km, \
	  ROUND( \
	    (((SUM(ST_Length(geom)) / t.total_length)) * 100)::numeric, 1) as pct \
	FROM integratedroads_vw, total t \
	GROUP BY bcgw_source, to_char(bcgw_extraction_date, 'YYYY-MM-DD'), total_length \
	ORDER BY bcgw_source" \
	  integratedroads.gpkg \
	  "PG:host=$(PGHOST) user=$(PGUSER) dbname=$(PGDATABASE) port=$(PGPORT)"

	zip -r $@ integratedroads.gpkg
	rm integratedroads.gpkg

summary.md: .integratedroads_vw
	# Generate summary table as markdown for easy viewing on GH
	# https://gist.github.com/rastermanden/94c4a663176c41248f3e
	psql -f sql/summary.sql | sed 's/+/|/g' | sed 's/^/|/' | sed 's/$$/|/' | grep -v rows | grep -v '||' > summary.md