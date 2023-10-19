# syntax=docker/dockerfile:1

# Explaining order of ARGS in Dockerfiles: https://stackoverflow.com/a/53683625/9068781

ARG RONDB_TARBALL_LOCAL_REMOTE

# Download all required Ubuntu dependencies
FROM --platform=$TARGETPLATFORM ubuntu:22.04 as rondb_runtime_dependencies

ARG BUILDPLATFORM
ARG TARGETPLATFORM

ARG TARGETARCH
ARG TARGETVARIANT

ARG OPEN_SSL_VERSION=1.1.1s

RUN echo "Running on $BUILDPLATFORM, building for $TARGETPLATFORM"
RUN echo "TARGETARCH: $TARGETARCH; TARGETVARIANT: $TARGETVARIANT"

RUN --mount=type=cache,target=/var/cache/apt,id=ubuntu22-apt-$TARGETPLATFORM \
    --mount=type=cache,target=/var/lib/apt/lists,id=ubuntu22-apt-lists-$TARGETPLATFORM \
    apt-get update -y \
    && apt-get install -y wget tar gzip vim \
    libaio1 libaio-dev \
    libncurses5 libnuma-dev \
    bc default-jdk maven \
    sudo iproute2 dnsutils
    # Java & Maven are required by YCSB
    # bc is required by dbt2
    # libaio is a dynamic library used by RonDB
    # libncurses5 & libnuma-dev are required for x86 only
    # sudo is required in the entrypoint
    # iproute2 is for using the command `ss`
    # dnsutils is for using the command `nslookup` in K8s

# Let PATH survive through sudo
RUN sed -ri '/secure_path/d' /etc/sudoers

# Creating a cache dir for downloads to avoid redownloading
ENV DOWNLOADS_CACHE_DIR=/tmp/downloads
RUN mkdir $DOWNLOADS_CACHE_DIR

# we need libssl.so.1.1 & libcrypto.so.1.1 for our binaries;
#   /usr/lib/aarch64-linux-gnu only contains libssl.so,
#   which is from openssl-3.x;
#   to get these libraries, we need to download openssl-1.1.1;
#   we don't need openssl-1.1.1 itself, only its shared libraries;
#   commands are from https://linuxpip.org/install-openssl-linux/
ENV OPENSSL_ROOT=/usr/local/ssl
RUN --mount=type=cache,target=$DOWNLOADS_CACHE_DIR \
    --mount=type=cache,target=/var/cache/apt,id=ubuntu22-apt-$TARGETPLATFORM \
    --mount=type=cache,target=/var/lib/apt/lists,id=ubuntu22-apt-lists-$TARGETPLATFORM \
    apt-get update -y \
    && apt-get install -y build-essential checkinstall zlib1g-dev \
    && wget -N --progress=bar:force -P $DOWNLOADS_CACHE_DIR \
        https://www.openssl.org/source/openssl-$OPEN_SSL_VERSION.tar.gz \
    && tar -xf $DOWNLOADS_CACHE_DIR/openssl-$OPEN_SSL_VERSION.tar.gz -C . \
    && cd openssl-$OPEN_SSL_VERSION \
    && ./config --prefix=$OPENSSL_ROOT --openssldir=$OPENSSL_ROOT shared zlib \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -r openssl-$OPEN_SSL_VERSION
    # Could also run `make test`
    # `make install` places shared libraries into $OPENSSL_ROOT

# Add OpenSSL to library load path
RUN echo $OPENSSL_ROOT/lib > /etc/ld.so.conf.d/openssl.conf
RUN ldconfig --verbose

# Copying bare minimum of Hopsworks cloud environment for now
FROM rondb_runtime_dependencies as cloud_preparation
ARG RONDB_VERSION=21.04.15
RUN groupadd mysql && adduser mysql --ingroup mysql
ENV HOPSWORK_DIR=/srv/hops
ENV RONDB_BIN_DIR=$HOPSWORK_DIR/mysql-$RONDB_VERSION
RUN mkdir -p $RONDB_BIN_DIR

# Get RonDB tarball from local path & unpack it
FROM cloud_preparation as local_tarball
ARG RONDB_TARBALL_URI
RUN --mount=type=bind,source=$RONDB_TARBALL_URI,target=$RONDB_TARBALL_URI \
    tar xfz $RONDB_TARBALL_URI -C $RONDB_BIN_DIR --strip-components=1 \
    && chown mysql:mysql -R $RONDB_BIN_DIR

# Get RonDB tarball from remote url & unpack it
FROM cloud_preparation as remote_tarball
ARG RONDB_TARBALL_URI
RUN wget $RONDB_TARBALL_URI -O ./temp_tarball.tar.gz \
    && tar xfz ./temp_tarball.tar.gz -C $RONDB_BIN_DIR --strip-components=1 \
    && rm ./temp_tarball.tar.gz \
    && chown mysql:mysql -R $RONDB_BIN_DIR

FROM ${RONDB_TARBALL_LOCAL_REMOTE}_tarball

WORKDIR $HOPSWORK_DIR

# We use symlinks in case we want to exchange binaries
ENV RONDB_BIN_DIR_SYMLINK=$HOPSWORK_DIR/mysql
RUN ln -s $RONDB_BIN_DIR $RONDB_BIN_DIR_SYMLINK

ENV PATH=$RONDB_BIN_DIR_SYMLINK/bin:$PATH

# Add RonDB to library load path
RUN echo $RONDB_BIN_DIR_SYMLINK/lib > /etc/ld.so.conf.d/rondb.conf
RUN ldconfig --verbose

ENV RONDB_DATA_DIR=$HOPSWORK_DIR/mysql-cluster
ENV MGMD_DATA_DIR=$RONDB_DATA_DIR/mgmd
ENV MYSQLD_DATA_DIR=$RONDB_DATA_DIR/mysql
ENV NDBD_DATA_DIR=$RONDB_DATA_DIR/ndb_data

RUN mkdir -p $MGMD_DATA_DIR $NDBD_DATA_DIR $MYSQLD_DATA_DIR

ENV MYSQL_FILES_DIR=$RONDB_DATA_DIR/mysql-files
RUN mkdir -p $MYSQL_FILES_DIR

ENV LOG_DIR=$RONDB_DATA_DIR/log
ENV RONDB_SCRIPTS_DIR=$RONDB_DATA_DIR/ndb/scripts
ENV BACKUP_DATA_DIR=$RONDB_DATA_DIR/ndb/backups
ENV DISK_COLUMNS_DIR=$RONDB_DATA_DIR/ndb_disk_columns
ENV MYSQL_UNIX_PORT=$RONDB_DATA_DIR/mysql.sock

RUN mkdir -p $LOG_DIR $RONDB_SCRIPTS_DIR $BACKUP_DATA_DIR $DISK_COLUMNS_DIR

COPY --chown=mysql:mysql ./resources/rondb_scripts $RONDB_SCRIPTS_DIR
ENV PATH=$RONDB_SCRIPTS_DIR:$PATH

# So the path survives changing user to mysql
RUN echo "export PATH=$PATH" >> /home/mysql/.profile

RUN touch $MYSQL_UNIX_PORT

# We expect this image to be used as base image to other
# images with additional files specific to Docker
COPY --chown=mysql:mysql ./resources/entrypoints ./docker/rondb_standalone/entrypoints
COPY --chown=mysql:mysql ./resources/healthcheck.sh ./docker/rondb_standalone/healthcheck.sh

# Can be used to mount SQL init scripts
RUN mkdir ./docker/rondb_standalone/sql_init_scripts

# Creating benchmarking files/directories
ENV BENCHMARKS_DIR=/home/mysql/benchmarks
RUN mkdir $BENCHMARKS_DIR && cd $BENCHMARKS_DIR \
    && mkdir -p sysbench_single sysbench_multi dbt2_single dbt2_multi dbt2_data

# Avoid changing files if they are already owned by mysql; otherwise image size doubles
RUN chown mysql:mysql --from=root:root -R $HOPSWORK_DIR /home/mysql

ENTRYPOINT ["./docker/rondb_standalone/entrypoints/entrypoint.sh"]
EXPOSE 3306 33060 11860 1186 4406 5406
CMD ["mysqld"]
