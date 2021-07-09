# build gdal docker image with fgdb support
# the build takes 40m on my machine

git clone https://github.com/OSGeo/gdal.git
cd gdal/docker/ubuntu-full
docker build --build-arg WITH_FILEGDB=yes --tag osgeo/gdal:ubuntu-full-3.3.1-fgdb .
cd ../../../../
rm -rf gdal