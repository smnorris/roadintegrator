FROM osgeo/gdal:ubuntu-small-latest

RUN apt-get update && apt-get --assume-yes upgrade \
    && apt-get -qq install -y --no-install-recommends postgresql-common \
	&& apt-get -qq install -y --no-install-recommends yes \
    && apt-get -qq install -y --no-install-recommends gnupg \
    && yes '' | sh /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh \
    && apt-get -qq install -y --no-install-recommends postgresql-client-16 \
    && apt-get -qq install -y --no-install-recommends make \
    && apt-get -qq install -y --no-install-recommends g++ \
    && apt-get -qq install -y --no-install-recommends git \
    && apt-get -qq install -y --no-install-recommends wget \
    && apt-get -qq install -y --no-install-recommends zip \
    && apt-get -qq install -y --no-install-recommends unzip \
    && apt-get -qq install -y --no-install-recommends parallel \
    && apt-get -qq install -y --no-install-recommends python3-dev \
    && apt-get -qq install -y --no-install-recommends python3-pip \
    && apt-get -qq install -y --no-install-recommends python3-psycopg2 \
    && pip3 install --upgrade numpy \
    && pip3 install bcdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home/roadintegrator