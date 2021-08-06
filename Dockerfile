FROM osgeo/gdal:ubuntu-small-latest

RUN apt-get -qq install -y --no-install-recommends make
RUN apt-get -qq install -y --no-install-recommends wget
RUN apt-get -qq install -y --no-install-recommends zip
RUN apt-get -qq install -y --no-install-recommends unzip
RUN apt-get -qq install -y --no-install-recommends parallel
RUN apt-get -qq install -y --no-install-recommends python3-pip
RUN apt-get -qq install -y --no-install-recommends python3-psycopg2
RUN apt-get -qq install -y --no-install-recommends postgresql-client

COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt

WORKDIR /home/roadintegrator