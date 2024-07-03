#!/bin/bash

VERSION="$(< "$SCRIPT_DIR/VERSION" sed -e 's/^[[:space:]]*//' -e '/-SNAPSHOT$/s/.*/dev/' ./VERSION)"
RONDB_IMAGE_NAME=rondb:22.10.4
RONDB_VERSION=22.10.4
RONDB_TARBALL_URI=https://repo.hops.works/master/rondb-22.10.4-linux-glibc2.28-arm64_v8.tar.gz

docker buildx build . \
    --tag $RONDB_IMAGE_NAME \
    --build-arg RONDB_VERSION=$RONDB_VERSION-$VERSION \
    --build-arg RONDB_TARBALL_LOCAL_REMOTE=remote \
    --build-arg RONDB_ARM_TARBALL_URI=$RONDB_TARBALL_URI
