ARG nominatim_version=3.5.2

FROM ubuntu:focal as builder

ARG nominatim_version

# Let the container know that there is no TTY
ARG DEBIAN_FRONTEND=noninteractive

# Install packages
RUN apt-get -y update \
 && apt-get install -y -qq --no-install-recommends \
    build-essential \
    cmake \
    g++ \
    libboost-dev \
    libboost-system-dev \
    libboost-filesystem-dev \
    libexpat1-dev \
    zlib1g-dev \
    libxml2-dev \
    libbz2-dev \
    libpq-dev \
    libgeos-dev \
    libgeos++-dev \
    libproj-dev \
    php \
    curl \
    ca-certificates \
    gnupg \
    lsb-release

# Install postgres
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
  && sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
  && apt-get update \
  && apt-get install -y -qq postgresql-13 postgresql-13-postgis-3 postgresql-server-dev-13

# Build Nominatim
RUN cd /srv \
 && curl --silent -L http://www.nominatim.org/release/Nominatim-${nominatim_version}.tar.bz2 -o v${nominatim_version}.tar.bz2 \
 && tar xf v${nominatim_version}.tar.bz2 \
 && rm v${nominatim_version}.tar.bz2 \
 && mv Nominatim-${nominatim_version} nominatim \
 && cd nominatim \
 && mkdir build \
 && cd build \
 && cmake .. \
 && make


FROM ubuntu:focal

ARG nominatim_version

LABEL \
  maintainer="Peter Evans <mail@peterevans.dev>" \
  org.opencontainers.image.title="nominatim-k8s" \
  org.opencontainers.image.description="Nominatim for Kubernetes on Google Container Engine (GKE)." \
  org.opencontainers.image.authors="Peter Evans <mail@peterevans.dev>" \
  org.opencontainers.image.url="https://github.com/peter-evans/nominatim-k8s" \
  org.opencontainers.image.vendor="https://peterevans.dev" \
  org.opencontainers.image.licenses="MIT" \
  app.tag="nominatim${nominatim_version}"

# Let the container know that there is no TTY
ARG DEBIAN_FRONTEND=noninteractive

# Set locale and install packages
ENV LANG C.UTF-8
RUN apt-get -y update \
  && apt-get install -y -qq --no-install-recommends locales \
  && locale-gen en_US.UTF-8 \
  && update-locale LANG=en_US.UTF-8 \
  && apt-get install -y -qq --no-install-recommends \
    apache2 \
    php \
    php-pgsql \
    libapache2-mod-php \
    php-pear \
    php-db \
    php-intl \
    python3-dev \
    python3-psycopg2 \
    curl \
    ca-certificates \
    sudo \
    gnupg \
    lsb-release \
    less \
    libboost-dev \
    libboost-system-dev \
    libboost-filesystem-dev \
    supervisor \
    osmium-tool \
    wget \
    python3-pip \
    tree

# Install postgres
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
  && sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
  && apt-get update \
  && apt-get install -y -qq postgresql-13 postgresql-13-postgis-3 postgresql-server-dev-13

RUN pip3 install osmium

RUN apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /tmp/* /var/tmp/* \
  && mkdir -p /var/log/supervisor

# Setup user
RUN useradd -ms /bin/bash nominatim

# Setup supervisord
COPY assets/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy the application from the builder image
COPY --from=builder /srv/nominatim /srv/nominatim

# Configure Nominatim
COPY assets/local.php /srv/nominatim/build/settings/local.php
COPY assets/import_multiple_regions.sh /srv/nominatim/build/utils/import_multiple_regions.sh
COPY assets/update_multiple_regions.sh /srv/nominatim/build/utils/update_multiple_regions.sh

# Configure Apache
COPY assets/nominatim.conf /etc/apache2/sites-enabled/000-default.conf

# Allow remote connections to PostgreSQL
RUN echo "host    all             all             127.0.0.1/32            trust" >> /etc/postgresql/13/main/pg_hba.conf \
  && echo "host    all             all             0.0.0.0/0            md5" >> /etc/postgresql/13/main/pg_hba.conf \
  && echo "listen_addresses = '*'" >> /etc/postgresql/13/main/postgresql.conf \
  && echo "log_destination = 'stderr'" >> /etc/postgresql/13/main/postgresql.conf \
  && echo "log_checkpoints = on" >> /etc/postgresql/13/main/postgresql.conf \
  && echo "include_dir = '/postgresql_conf.d/'" >> /etc/postgresql/13/main/postgresql.conf

# Set the entrypoint
COPY docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 5432
EXPOSE 8080
