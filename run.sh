#!/bin/bash
# Generating RonDB clusters of variable sizes with docker compose
# Copyright (c) 2022, 2023 Hopsworks AB and/or its affiliates.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

function print_usage() {
    cat <<EOF
Usage: $0    
    [-h         --help                              ]
    [-v         --rondb-version             <string>]
    [-s         --size                      <string>]

RonDB running in Docker Compose is intended for development
purposes, not for production usage. We have a number of
setups dependent on the size of your development machine.

The mini configuration should work on a machine with 8GB of
memory and a few CPUs.
The small configuration is intended for development machines
that have at least 16 GB of memory and 4 CPU cores.
The medium configuration is intended for machines with at least
32 GB of memory and 8 CPU cores.
The large configuration is intended for machines with at least
32 GB of memory and 16 CPU cores.
The xlarge configuration is intended for machines with at
least 64 GB of memory and 32 CPU cores.
EOF
}

RONDB_SIZE=small
RONDB_VERSION=latest
REPLICATION_FACTOR=2

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -h | --help)
        print_usage
        exit 0
        ;;
    -v | --rondb-version)
        RONDB_VERSION="$2"
        shift # past argument
        shift # past value
        ;;
    -s | --size)
        RONDB_SIZE="$2"
        shift # past argument
        ;;
    *)                     # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift              # past argument
        ;;
    esac
done

if [ "$RONDB_SIZE" != "small" ] && \
   [ "$RONDB_SIZE" != "mini" ] && \
   [ "$RONDB_SIZE" != "medium" ] && \
   [ "$RONDB_SIZE" != "large" ] && \
   [ "$RONDB_SIZE" != "workstation" ]; then
    echo "size has to be one of <mini, small, medium, large, workstation>"
    exit 1
fi

if [ "$RONDB_SIZE" = "mini" ]; then
    REPLICATION_FACTOR="1"
fi
./build_run_docker.sh \
  --rondb-version $RONDB_VERSION \
  --num-mgm-nodes 1 \
  --node-groups 1 \
  --replication-factor $REPLICATION_FACTOR \
  --num-mysql-nodes 2 \
  --pull-dockerhub-image \
  --size $RONDB_SIZE \
  --num-api-nodes 1
