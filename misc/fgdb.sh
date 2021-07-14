# build gdal docker image with fgdb support
# the build takes 40m on my machine

git clone https://github.com/OSGeo/gdal.git
cd gdal/docker/ubuntu-full
docker build --build-arg WITH_FILEGDB=yes --tag osgeo/gdal:ubuntu-full-3.3.1-fgdb .
cd ../../../../
rm -rf gdal

# Dump output to .gdb
docker run --rm \
  -v ${PWD}:/output \
  osgeo/gdal:ubuntu-full-3.3.1-fgdb \
  ogr2ogr \
    -f FileGDB \
    -progress \
    -nlt LINESTRING \
    -nln integrated_roads \
    -lco GEOMETRY_NULLABLE=NO \
    -lco GEOMETRY_NAME=Shape \
    -sql "SELECT * FROM integratedroads_vw" \
    integrated_roads.gdb \
    "PG:host=$PGHOST user=$PGUSER dbname=$PGDATABASE port=$PGPORT"
