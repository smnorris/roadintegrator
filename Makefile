.PHONY: all build db clean

PSQL=psql $(DATABASE_URL) -v ON_ERROR_STOP=1          # point psql to db and stop on errors

# list all targets
GENERATED_FILES = .make/db \
	.make/whse_basemapping.bcgs_20k_grid \
	.make/whse_basemapping.transport_line \
	.make/whse_forest_tenure.abr_road_section_line \
	.make/ften_active \
	.make/ften_retired \
	.make/results \
	.make/og_permits_row \
	.make/integratedroads \
	.make/integratedroads_sources \
	.make/integratedroads_vw \
	data/dgtl_road_atlas.gdb \
	data/ften_road_section_lines_svw.gpkg \
	data/rslt_forest_cover_inv_svw.gpkg \
	data/og_petrlm_dev_rds_pre06_pub_sp.gpkg \
	data/og_road_segment_permit_sp.gpkg \
	data/og_road_area_permit_sp.gpkg \
	integratedroads.gpkg \
	integratedroads.gpkg.zip \
	summary.csv \
	integratedroads_source_data.zip

# Make all targets
all: $(GENERATED_FILES)


# get/build required docker images
build:
	docker-compose build
	docker-compose up -d


# Remove all generated targets, stop and delete the db container
clean:
	rm -Rf $(GENERATED_FILES)
	docker-compose down

# create db, add required extensions/functions, create ouput tables/views
.make/db:
	$(PSQL) -c "CREATE DATABASE roadintegrator" postgres
	$(PSQL) -c "CREATE EXTENSION postgis"
	$(PSQL) -c "CREATE EXTENSION postgis_sfcgal"
	$(PSQL) -f sql/ST_ApproximateMedialAxisIgnoreErrors.sql
	$(PSQL) -f sql/integratedroads.sql
	mkdir -p .make


# -----------------------
# Data load
# -----------------------

# load 20k tiles
.make/whse_basemapping.bcgs_20k_grid: .make/db
	bcdata bc2pg WHSE_BASEMAPPING.BCGS_20K_GRID -k MAP_TILE
	touch $@

# ften roads
data/ften_road_section_lines_svw.gpkg: .make/db
	bcdata bc2pg WHSE_FOREST_TENURE.FTEN_ROAD_SECTION_LINES_SVW \
	  -k MAP_LABEL \
	  --query "LIFE_CYCLE_STATUS_CODE IN ('ACTIVE','RETIRED')"
	# dump to file
	ogr2ogr \
      -f GPKG \
      -progress \
      -nlt MULTILINESTRING \
      -nln ften_road_section_lines_svw \
      -lco GEOMETRY_NULLABLE=NO \
	  -sql "SELECT * FROM whse_forest_tenure.ften_road_section_lines_svw" \
	  $@ \
      "PG:$(DATABASE_URL)"

# Results road polygons
data/rslt_forest_cover_inv_svw.gpkg: .make/db
	bcdata bc2pg WHSE_FOREST_VEGETATION.RSLT_FOREST_COVER_INV_SVW \
  	-k FOREST_COVER_ID \
  	--query "STOCKING_STATUS_CODE = 'NP' AND STOCKING_TYPE_CODE IN ('RD','UNN') \
  	         AND SILV_POLYGON_NUMBER NOT IN ('landing', 'lnd') AND GEOMETRY_EXIST_IND = 'Y'"
	# dump to file
	ogr2ogr \
      -f GPKG \
      -progress \
      -nlt MULTIPOLYGON \
      -nln rslt_forest_cover_inv_svw \
      -lco GEOMETRY_NULLABLE=NO \
	  -sql "SELECT * FROM whse_forest_vegetation.rslt_forest_cover_inv_svw" \
	  $@ \
      "PG:$(DATABASE_URL)"

# Oil and Gas Dev, pre06
data/og_petrlm_dev_rds_pre06_pub_sp.gpkg: .make/db
	bcdata bc2pg WHSE_MINERAL_TENURE.OG_PETRLM_DEV_RDS_PRE06_PUB_SP \
	  -k OG_PETRLM_DEV_RD_PRE06_PUB_ID
	# dump to file
	ogr2ogr \
      -f GPKG \
      -progress \
      -nlt MULTILINESTRING \
      -update \
      -append \
      -nln og_petrlm_dev_rds_pre06_pub_sp \
      -lco GEOMETRY_NULLABLE=NO \
	  -sql "SELECT * FROM whse_mineral_tenure.og_petrlm_dev_rds_pre06_pub_sp" \
	  $@ \
      "PG:$(DATABASE_URL)"

# Oil and Gas permits, road segments
data/og_road_segment_permit_sp.gpkg: .make/db
	bcdata bc2pg WHSE_MINERAL_TENURE.OG_ROAD_SEGMENT_PERMIT_SP \
	  -k OG_ROAD_SEGMENT_PERMIT_ID
	# dump to file
	ogr2ogr \
      -f GPKG \
      -progress \
      -nlt MULTILINESTRING \
      -update \
      -append \
      -nln og_road_segment_permit_sp \
      -lco GEOMETRY_NULLABLE=NO \
	  -sql "SELECT * FROM whse_mineral_tenure.og_road_segment_permit_sp" \
	  $@ \
      "PG:$(DATABASE_URL)"

# Oil and Gas permits, road right of way (polygons)
data/og_road_area_permit_sp.gpkg: .make/db
	bcdata bc2pg WHSE_MINERAL_TENURE.OG_ROAD_AREA_PERMIT_SP \
  	  -k OG_ROAD_AREA_PERMIT_ID
	# dump to file
	ogr2ogr \
      -f GPKG \
      -progress \
      -nlt MULTIPOLYGON \
      -update \
      -append \
      -nln og_road_area_permit_sp \
      -lco GEOMETRY_NULLABLE=NO \
	  -sql "SELECT * FROM whse_mineral_tenure.og_road_area_permit_sp" \
	  $@ \
      "PG:$(DATABASE_URL)"

# download DRA (because we want a file archive, download full dataset rather than loading directly via vsicurl)
data/dgtl_road_atlas.gdb:
	wget --trust-server-names -qNP data ftp://ftp.geobc.gov.bc.ca/sections/outgoing/bmgs/DRA_Public/dgtl_road_atlas.gdb.zip
	unzip -qun -d data "data/dgtl_road_atlas.gdb.zip"
	rm data/dgtl_road_atlas.gdb.zip

# load DRA to db
.make/whse_basemapping.transport_line: data/dgtl_road_atlas.gdb .make/db
	ogr2ogr \
	  -f PostgreSQL \
	  "PG:$(DATABASE_URL)" \
	  -overwrite \
	  -lco GEOMETRY_NAME=geom \
	  -lco FID=transport_line_id \
	  -nln whse_basemapping.transport_line \
	  -where "TRANSPORT_LINE_SURFACE_CODE <> 'B'" \
	  data/dgtl_road_atlas.gdb \
	  TRANSPORT_LINE

	# Because we are not loading this table via bc2pg, no record is added to bcdata table.
	# Do this manually here so we know what day this data was extracted
	$(PSQL) -c "INSERT INTO bcdata.log (table_name, latest_download) \
	   SELECT 'whse_basemapping.transport_line', CURRENT_TIMESTAMP \
	   ON CONFLICT (table_name) DO \
	   UPDATE SET latest_download = EXCLUDED.latest_download;"

	# load DRA structure/type/surface lookups
	ogr2ogr \
	  -f PostgreSQL \
	  "PG:$(DATABASE_URL)" \
	  -overwrite \
	  -nln whse_basemapping.transport_line_structure_code \
	  data/dgtl_road_atlas.gdb \
	  TRANSPORT_LINE_STRUCTURE_CODE
	ogr2ogr \
	  -f PostgreSQL \
	  "PG:$(DATABASE_URL)" \
	  -overwrite \
	  -nln whse_basemapping.transport_line_type_code \
	  data/dgtl_road_atlas.gdb \
	  TRANSPORT_LINE_TYPE_CODE
	ogr2ogr \
	  -f PostgreSQL \
	  "PG:$(DATABASE_URL)" \
	  -overwrite \
	  -nln whse_basemapping.transport_line_surface_code \
	  data/dgtl_road_atlas.gdb \
	  TRANSPORT_LINE_SURFACE_CODE
	# note that because this is a file source, data is not dumped back to file
	touch $@

# As-built roads
# **NOTE**
# data/ABR.gdb must be manually downloaded before running
.make/whse_forest_tenure.abr_road_section_line: data/ABR.gdb .make/db
	$(PSQL) -c "create schema if not exists whse_forest_tenure"
	ogr2ogr -f PostgreSQL \
	  "PG:$(DATABASE_URL)" \
	  -overwrite \
	  -t_srs EPSG:3005 \
	  -lco GEOMETRY_NAME=geom \
	  -lco FID=ROAD_SECTION_LINE_ID \
	  -nln whse_forest_tenure.abr_road_section_line \
	  data/ABR.gdb \
	  ABR_ROAD_SECTION_LINE
	# Because we are not loading this table via bc2pg, no record is added to bcdata table.
	# Do this manually here so we know what day this data was extracted
	$(PSQL) -c "INSERT INTO bcdata.log (table_name, latest_download) \
	   SELECT 'whse_forest_tenure.abr_road_section_line', CURRENT_TIMESTAMP \
	   ON CONFLICT (table_name) DO \
	   UPDATE SET latest_download = EXCLUDED.latest_download;"
	# note that because this is a file source, data is not dumped back to file
	touch $@

# -----------------------
# preprocessing
# -----------------------

# clean active ften roads
.make/ften_active: data/ften_road_section_lines_svw.gpkg
	$(PSQL) -c "DROP TABLE IF EXISTS ften_active"
	$(PSQL) -c "CREATE TABLE ften_active \
	( ften_active_id serial primary key, \
	  map_label character varying, \
	  map_tile character varying, \
	  geom geometry(Linestring,3005));"
	$(PSQL) -tXA \
	-c "SELECT DISTINCT map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_forest_tenure.ften_road_section_lines_svw r \
	    ON ST_Intersects(t.geom, r.geom) \
	    WHERE life_cycle_status_code = 'ACTIVE' \
	    ORDER BY map_tile" \
	    | parallel --jobs -2 --progress --joblog ften_active.log \
	      $(PSQL) -f sql/preprocess_ften_active.sql -v tile={1}
	$(PSQL) -c "CREATE INDEX on ften_active USING GIST (geom);"
	touch $@

# clean retired ften roads
.make/ften_retired: data/ften_road_section_lines_svw.gpkg
	$(PSQL) -c "DROP TABLE IF EXISTS ften_retired"
	$(PSQL) -c "CREATE TABLE ften_retired \
	( ften_retired_id serial primary key, \
	  map_label character varying, \
	  map_tile character varying, \
	  geom geometry(Linestring,3005));"
	$(PSQL) -tXA \
	-c "SELECT DISTINCT map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_forest_tenure.ften_road_section_lines_svw r \
	    ON ST_Intersects(t.geom, r.geom) \
	    WHERE life_cycle_status_code = 'RETIRED' \
	    ORDER BY map_tile" \
	    | parallel --jobs -2 --progress --joblog ften_retired.log \
	      $(PSQL) -f sql/preprocess_ften_retired.sql -v tile={1}
	$(PSQL) -c "CREATE INDEX on ften_retired USING GIST (geom);"
	touch $@

# convert RESULTS polygon roads to lines
.make/results: data/rslt_forest_cover_inv_svw.gpkg
	$(PSQL) -c "DROP TABLE IF EXISTS results"
	$(PSQL) -c "CREATE TABLE results \
	( results_id serial primary key, \
	  map_tile character varying, \
	  geom geometry(Linestring, 3005))"
	$(PSQL) -tXA \
	-c "SELECT DISTINCT t.map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_forest_vegetation.rslt_forest_cover_inv_svw r \
	    ON ST_Intersects(t.geom, r.geom) \
	    WHERE ST_ISValid(r.geom) \
	    ORDER BY t.map_tile" \
	    | parallel --jobs -2 --progress --joblog results.log \
	      $(PSQL) -f sql/roadpoly2line.sql \
	        -v tile={1} \
	        -v in_table=whse_forest_vegetation.rslt_forest_cover_inv_svw \
	        -v out_table=results
	$(PSQL) -c "CREATE INDEX ON results USING GIST (geom)"
	touch $@

# convert OG permit right of ways (poly) to lines
.make/og_permits_row: data/og_road_area_permit_sp.gpkg
	$(PSQL) -c "DROP TABLE IF EXISTS og_permits_row"
	$(PSQL) -c "CREATE TABLE og_permits_row \
	( og_permits_row_id serial primary key, \
	  map_tile character varying, \
	  geom geometry(Linestring, 3005))"
	$(PSQL) -tXA \
	-c "SELECT DISTINCT t.map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_mineral_tenure.og_road_area_permit_sp r \
	    ON ST_Intersects(t.geom, r.geom) \
	    ORDER BY t.map_tile" \
	     | parallel --jobs -2 --progress --joblog og_permits_row.log \
	       $(PSQL) -f sql/roadpoly2line.sql \
	       -v tile={1} \
	       -v in_table=whse_mineral_tenure.og_road_area_permit_sp \
	       -v out_table=og_permits_row
	$(PSQL) -c "CREATE INDEX ON og_permits_row USING GIST (geom)"
	touch $@

# -----------------------
# load data to integratedroads table
# -----------------------
.make/integratedroads: .make/whse_basemapping.transport_line \
	.make/ften_active \
	.make/ften_active \
	.make/results \
	.make/whse_forest_tenure.abr_road_section_line \
	data/og_petrlm_dev_rds_pre06_pub_sp.gpkg \
	data/og_road_segment_permit_sp.gpkg \
	.make/og_permits_row
	# clear output table
	$(PSQL) -c "truncate integratedroads"

	# load DRA (just dump everything in, these features remain unchanged)
	$(PSQL) -tXA \
	-c "SELECT DISTINCT \
	      substring(t.map_tile from 1 for 4) as map_tile \
	    FROM whse_basemapping.bcgs_20k_grid t \
	    INNER JOIN whse_basemapping.transport_line r \
	    ON ST_Intersects(t.geom, r.geom) \
	    ORDER BY substring(t.map_tile from 1 for 4)" \
	    | parallel --jobs -2 $(PSQL) -f sql/load_dra.sql -v tile={1}

	# load all other sources
	./integrateroads.sh

	# index the foreign keys for faster joins back to source tables
	$(PSQL) -c "CREATE INDEX ON integratedroads (transport_line_id)"
	$(PSQL) -c "CREATE INDEX ON integratedroads (map_label)"
	$(PSQL) -c "CREATE INDEX ON integratedroads (road_section_line_id)"
	$(PSQL) -c "CREATE INDEX ON integratedroads (og_petrlm_dev_rd_pre06_pub_id)"
	$(PSQL) -c "CREATE INDEX ON integratedroads (og_road_segment_permit_id)"
	touch $@

# for all output features, identify what other source roads intersect with the road's 7m buffer
.make/integratedroads_sources:
	$(PSQL) -tXA \
	-c "SELECT DISTINCT map_tile FROM integratedroads ORDER BY map_tile" \
	    | parallel --jobs -2 --progress --joblog integratedroads_sources.log \
	      $(PSQL) -f sql/load_sources.sql -v tile={1}
	$(PSQL) -c "CREATE INDEX ON integratedroads_sources (integratedroads_id)"
	$(PSQL) -c "CREATE INDEX ON integratedroads_sources (map_label)"
	$(PSQL) -c "CREATE INDEX ON integratedroads_sources (forest_cover_id)"
	$(PSQL) -c "CREATE INDEX ON integratedroads_sources (road_section_line_id)"
	$(PSQL) -c "CREATE INDEX ON integratedroads_sources (og_petrlm_dev_rd_pre06_pub_id)"
	$(PSQL) -c "CREATE INDEX ON integratedroads_sources (og_road_segment_permit_id)"
	$(PSQL) -c "CREATE INDEX ON integratedroads_sources (og_road_area_permit_id)"
	touch $@

# create output view with required data/columns
.make/integratedroads_vw: .make/integratedroads .make/integratedroads_sources
	$(PSQL) -c "REFRESH MATERIALIZED VIEW integratedroads_vw"
	touch $@

# dump to geopackage
integratedroads.gpkg: .make/integratedroads_vw
	ogr2ogr \
    -f GPKG \
    -progress \
    -nlt LINESTRING \
    -nln integratedroads \
    -lco GEOMETRY_NULLABLE=NO \
    -sql "SELECT * FROM integratedroads_vw" \
    integratedroads.gpkg \
    "PG:$(DATABASE_URL)" \

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
	"PG:$(DATABASE_URL)"

# compress the output gpkg
integratedroads.gpkg.zip: integratedroads.gpkg
	zip -r $@ integratedroads.gpkg

# summarize outputs in a csv file
summary.csv: .make/integratedroads_vw
	$(PSQL) -c "refresh materialized view integratedroads_summary_vw"
	$(PSQL) --csv -c "select * from integratedroads_summary_vw" > summary.csv

# archive the source data
integratedroads_source_data.zip: .make/integratedroads_vw
	zip -r integratedroads_source_data.zip data