#!/bin/bash

VERSION="$(< "./VERSION" sed -e 's/^[[:space:]]*//')"
RONDB_IMAGE_NAME=rondb-standalone:22.10.3
RONDB_VERSION=22.10.3
RONDB_TARBALL_URI=https://repo.hops.works/master/rondb-22.10.3-linux-glibc2.28-arm64_v8.tar.gz

docker buildx build . \
    --tag $RONDB_IMAGE_NAME \
    --build-arg RONDB_VERSION=$RONDB_VERSION-$VERSION \
    --build-arg RONDB_TARBALL_LOCAL_REMOTE=remote \
    --build-arg RONDB_ARM_TARBALL_URI=$RONDB_TARBALL_URI
