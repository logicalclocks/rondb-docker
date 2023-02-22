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

## This file does the following
## i. Builds the Docker image of RonDB
## i. Generates a config.ini & my.cnf file
## i. Creates docker-compose file
## i. Runs docker-compose
## i. Optionally runs a benchmark

# shellcheck disable=SC2059

set -e

# https://stackoverflow.com/a/246128/9068781
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Repo version
VERSION="$(< "$SCRIPT_DIR/VERSION" sed -e 's/^[[:space:]]*//')"

function print_usage() {
    cat <<EOF
RonDB-Docker version: $VERSION

Usage: $0    
    [-h         --help                              ]
    [-v         --rondb-version             <string>]
    [-ruri      --rondb-tarball-uri         <string>]
    [-m         --num-mgm-nodes             <int>   ]
    [-g         --node-groups               <int>   ]
    [-r         --replication-factor        <int>   ]
    [-my        --num-mysql-nodes           <int>   ]
    [-a         --num-api-nodes             <int>   ]
    [-b         --run-benchmark             <string>
                    Options: <sysbench_single, sysbench_multi, dbt2_single>
                                                    ]
    [-pd        --pull-dockerhub-image              ]
    [-rtarl     --rondb-tarball-is-local            ]
    [-lv        --volumes-in-local-dir              ]
    [-sf        --save-sample-files                 ]
    [-d         --detached                          ]
    [-s         --size                      <string>]

    The size parameter is only intended for the wrapper
    script run.sh that makes it very easy to set up
    different sizes of the RonDB cluster resources.
EOF
}

if [ -z "$1" ]; then
    print_usage
    exit 1
fi

#######################
#### CLI Arguments ####
#######################

# Defaults
RONDB_TARBALL_LOCAL_REMOTE=remote
NUM_MGM_NODES=1
NUM_MYSQL_NODES=0
NUM_API_NODES=0
REPLICATION_FACTOR=1
NODE_GROUPS=1
RUN_BENCHMARK=
VOLUME_TYPE=docker
PULL_DOCKERHUB_IMAGE=
SAVE_SAMPLE_FILES=
DETACHED=
RONDB_SIZE=small
RONDB_VERSION=latest

POSITIONAL=()
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
    -ruri | --rondb-tarball-uri)
        RONDB_TARBALL_URI="$2"
        shift # past argument
        shift # past value
        ;;
    -m | --num-mgm-nodes)
        NUM_MGM_NODES="$2"
        shift # past argument
        shift # past value
        ;;
    -g | --node-groups)
        NODE_GROUPS="$2"
        shift # past argument
        shift # past value
        ;;
    -r | --replication-factor)
        REPLICATION_FACTOR="$2"
        shift # past argument
        shift # past value
        ;;
    -my | --num-mysql-nodes)
        NUM_MYSQL_NODES="$2"
        shift # past argument
        shift # past value
        ;;
    -a | --num-api-nodes)
        NUM_API_NODES="$2"
        shift # past argument
        shift # past value
        ;;

    -b | --run-benchmark)
        RUN_BENCHMARK="$2"
        shift # past argument
        shift # past value
        ;;

    -pd | --pull-dockerhub-image)
        PULL_DOCKERHUB_IMAGE=1
        shift # past argument
        ;;

    -rtarl | --rondb-tarball-is-local)
        RONDB_TARBALL_LOCAL_REMOTE=local
        shift # past argument
        ;;

    -d | --detached)
        DETACHED="-d"
        shift # past argument
        ;;

    -lv | --volumes-in-local-dir)
        VOLUME_TYPE=local
        shift # past argument
        ;;

    -sf | --save-sample-files)
        SAVE_SAMPLE_FILES=1
        shift # past argument
        ;;
    -s | --size)
        RONDB_SIZE="$2"
        shift # past argument
        shift # past value
        ;;

    *)                     # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift              # past argument
        ;;
    esac
done

print-parsed-arguments() {
    echo "RonDB-Docker version: $VERSION"
    echo
    echo "#################"
    echo "Parsed arguments:"
    echo "#################"
    echo
    echo "RonDB version                 = ${RONDB_VERSION}"
    echo "Pull Dockerhub image          = ${PULL_DOCKERHUB_IMAGE}"
    echo "RonDB tarball local/remote    = ${RONDB_TARBALL_LOCAL_REMOTE}"
    echo "RonDB tarball URI             = ${RONDB_TARBALL_URI}"
    echo "Number of management nodes    = ${NUM_MGM_NODES}"
    echo "Node groups                   = ${NODE_GROUPS}"
    echo "Replication factor            = ${REPLICATION_FACTOR}"
    echo "Number of mysql nodes         = ${NUM_MYSQL_NODES}"
    echo "Number of api nodes           = ${NUM_API_NODES}"
    echo "Run benchmark                 = ${RUN_BENCHMARK}"
    echo "Volume type docker/local      = ${VOLUME_TYPE}"
    echo "Save sample files             = ${SAVE_SAMPLE_FILES}"
    echo "Run detached                  = ${DETACHED}"
    echo "Run with RonDB size           = ${RONDB_SIZE}"
    echo
}
print-parsed-arguments

set -- "${POSITIONAL[@]}" # restore unknown options
if [[ -n $1 ]]; then
    echo "##################" >&2
    echo "Illegal arguments: $*" >&2
    echo "##################" >&2
    echo
    print_usage
    exit 1
fi

if [ -n "$PULL_DOCKERHUB_IMAGE" ]; then
    if [ -n "$RONDB_TARBALL_URI" ]; then
        echo "Cannot specify both a tarball URI and pull from Dockerhub"
        exit 1
    fi
else
    if [ ! -n "$RONDB_TARBALL_URI" ]; then
        echo "Either a tarball URI must be specified or set the flag to pull the image from Dockerhub"
        exit 1
    fi
fi

if [ "$NUM_MGM_NODES" -lt 1 ]; then
    echo "At least 1 mgmd is required"
    exit 1
elif [ "$REPLICATION_FACTOR" -lt 1 ] || [ "$REPLICATION_FACTOR" -gt 4 ]; then
    echo "The replication factor has to be >=1 and <5; It is currently $REPLICATION_FACTOR"
    exit 1
elif [ "$NODE_GROUPS" -lt 1 ]; then
    echo "At least 1 node group is required"
    exit 1
fi

if [ "$RONDB_SIZE" != "small" ] && \
   [ "$RONDB_SIZE" != "mini" ] && \
   [ "$RONDB_SIZE" != "medium" ] && \
   [ "$RONDB_SIZE" != "large" ] && \
   [ "$RONDB_SIZE" != "xlarge" ]; then
    echo "size has to be one of <mini, small, medium, large, xlarge>"
    exit 1
fi

if [ -n "$RUN_BENCHMARK" ]; then
    if [ "$RUN_BENCHMARK" != "sysbench_single" ] && \
       [ "$RUN_BENCHMARK" != "sysbench_multi" ] && \
       [ "$RUN_BENCHMARK" != "dbt2_single" ] && \
        echo "Benchmark has to be one of <sysbench_single, sysbench_multi, dbt2_single>"
        exit 1
    elif [ "$NUM_API_NODES" -lt 1 ]; then
        echo "At least one api is required to run benchmarks"
        exit 1
    elif [ "$NUM_MYSQL_NODES" -lt 1 ]; then
        echo "At least one mysqld is required to run benchmarks"
        exit 1
    fi

    # This is not a hard requirement, but is better for benchmarking
    # One api container can however also run multiple Sysbench instances against multiple mysqld containers
    if [ "$RUN_BENCHMARK" == "sysbench_multi" ]; then
        if [ "$NUM_MYSQL_NODES" -lt "$NUM_API_NODES" ]; then
            echo "For sysbench_multi, there should be at least as many mysqld as api containers"
            exit 1
        fi
    fi

    if [ "$RUN_BENCHMARK" == "sysbench_multi" ] || [ "$RUN_BENCHMARK" == "dbt2_multi" ]; then
        if [ "$NUM_MYSQL_NODES" -lt 2 ]; then
            echo "At least two mysqlds are required to run the multi-benchmarks"
            exit 1
        fi
    fi

    if [ "$RUN_BENCHMARK" == "dbt2_single" ] || [ "$RUN_BENCHMARK" == "dbt2_multi" ]; then
        if [ "$NUM_API_NODES" -gt 1 ]; then
            echo "Can only run dbt2 benchmarks with one api container"
            exit 1
        fi
    fi

    # TODO: Make this work with BENCHMARK_SERVERS in sysbench_multi; This requires some
    #   care in synchronizing the api nodes when executing the benchmark.
    if [ "$NUM_API_NODES" -gt 1 ]; then
        echo "Running more than one api container for Sysbench benchmarks is currently not supported"
        exit 1
    fi
fi

# We use this for the docker-compose project name, which will not allow "."
RONDB_VERSION_NO_DOT=$(echo "$RONDB_VERSION" | tr -d '.')

## Uncomment this for quicker testing
# yes | docker container prune
# yes | docker volume prune

FILE_SUFFIX="v${RONDB_VERSION_NO_DOT}_m${NUM_MGM_NODES}_g${NODE_GROUPS}_r${REPLICATION_FACTOR}_my${NUM_MYSQL_NODES}_api${NUM_API_NODES}"

AUTOGENERATED_FILES_DIR="$SCRIPT_DIR/autogenerated_files/$FILE_SUFFIX"
rm -rf $AUTOGENERATED_FILES_DIR
mkdir -p "$AUTOGENERATED_FILES_DIR"

PARSED_ARGUMENTS_FILEPATH="$AUTOGENERATED_FILES_DIR/parsed_arguments.txt"
print-parsed-arguments > "$PARSED_ARGUMENTS_FILEPATH"

DOCKER_COMPOSE_FILEPATH="$AUTOGENERATED_FILES_DIR/docker_compose.yml"
CONFIG_INI_FILEPATH="$AUTOGENERATED_FILES_DIR/config.ini"
MY_CNF_FILEPATH="$AUTOGENERATED_FILES_DIR/my.cnf"

LOCAL_VOLUMES_DIR="$AUTOGENERATED_FILES_DIR/volumes"

# These directories will be mounted into the api containers
SYSBENCH_SINGLE_DIR="$LOCAL_VOLUMES_DIR/sysbench_single"
SYSBENCH_MULTI_DIR="$LOCAL_VOLUMES_DIR/sysbench_multi"
DBT2_SINGLE_DIR="$LOCAL_VOLUMES_DIR/dbt2_single"
DBT2_MULTI_DIR="$LOCAL_VOLUMES_DIR/dbt2_multi"

mkdir -p "$SYSBENCH_SINGLE_DIR" "$DBT2_SINGLE_DIR"
if [ "$NUM_MYSQL_NODES" -gt 1 ]; then
    mkdir -p "$SYSBENCH_MULTI_DIR" "$DBT2_MULTI_DIR"
fi

AUTOBENCH_SYS_SINGLE_FILEPATH="$SYSBENCH_SINGLE_DIR/autobench.conf"
AUTOBENCH_SYS_MULTI_FILEPATH="$SYSBENCH_MULTI_DIR/autobench.conf"
AUTOBENCH_DBT2_SINGLE_FILEPATH="$DBT2_SINGLE_DIR/autobench.conf"
AUTOBENCH_DBT2_MULTI_FILEPATH="$DBT2_MULTI_DIR/autobench.conf"

# Copy resource files dependent on size
cp ./resources/config_templates/autobench_dbt2.conf.$RONDB_SIZE ./resources/config_templates/autobench_dbt2.conf
cp ./resources/config_templates/autobench_sysbench.conf.$RONDB_SIZE ./resources/config_templates/autobench_sysbench.conf
cp ./resources/config_templates/dbt2_run_1.conf.multi.$RONDB_SIZE ./resources/config_templates/dbt2_run_1.conf.multi
cp ./resources/config_templates/dbt2_run_1.conf.single.$RONDB_SIZE ./resources/config_templates/dbt2_run_1.conf.single
cp ./resources/config_templates/config.ini.$RONDB_SIZE ./resources/config_templates/config.ini
cp $SCRIPT_DIR/docker.env.$RONDB_SIZE $SCRIPT_DIR/docker.env

# Since we are mounting the entire benchmarking directories, these files would be
# overwritten if they are added via the Dockerfile.
DBT2_CONF_SINGLE_FILEPATH="$DBT2_SINGLE_DIR/dbt2_run_1.conf"
DBT2_CONF_MULTI_FILEPATH="$DBT2_MULTI_DIR/dbt2_run_1.conf"
if [ "$NUM_MYSQL_NODES" -gt 0 ]; then
    cp "$SCRIPT_DIR/resources/config_templates/dbt2_run_1.conf.single" "$DBT2_CONF_SINGLE_FILEPATH"
    if [ "$NUM_MYSQL_NODES" -gt 1 ]; then
        cp "$SCRIPT_DIR/resources/config_templates/dbt2_run_1.conf.multi" "$DBT2_CONF_MULTI_FILEPATH"
    fi
fi

DATA_DIR="/srv/hops/mysql-cluster"
BENCH_DIR="/home/mysql/benchmarks"

#######################
#######################
#######################

echo "Building RonDB Docker image for local platform"

RONDB_IMAGE_NAME="rondb-standalone:$RONDB_VERSION"
if [ -n "$PULL_DOCKERHUB_IMAGE" ]; then
    RONDB_IMAGE_NAME="hopsworks/$RONDB_IMAGE_NAME"
    docker pull $RONDB_IMAGE_NAME
else
    docker buildx build . \
        --tag $RONDB_IMAGE_NAME \
        --build-arg RONDB_VERSION=$RONDB_VERSION \
        --build-arg RONDB_TARBALL_LOCAL_REMOTE=$RONDB_TARBALL_LOCAL_REMOTE \
        --build-arg RONDB_TARBALL_URI=$RONDB_TARBALL_URI
fi

#######################
#######################
#######################

echo "Loading templates"

CONFIG_INI_TEMPLATE=$(cat ./resources/config_templates/config.ini)
CONFIG_INI_MGMD_TEMPLATE=$(cat ./resources/config_templates/config_mgmd.ini)
CONFIG_INI_NDBD_TEMPLATE=$(cat ./resources/config_templates/config_ndbd.ini)
CONFIG_INI_MYSQLD_TEMPLATE=$(cat ./resources/config_templates/config_mysqld.ini)
CONFIG_INI_API_TEMPLATE=$(cat ./resources/config_templates/config_api.ini)

MY_CNF_TEMPLATE=$(cat ./resources/config_templates/my.cnf)

AUTOBENCH_DBT2_TEMPLATE=$(cat ./resources/config_templates/autobench_dbt2.conf)
AUTOBENCH_SYSBENCH_TEMPLATE=$(cat ./resources/config_templates/autobench_sysbench.conf)

# Doing restart on-failure for the agent upgrade; we return a failure there
service-template() {
    printf "

    %s:
      image: %s
      container_name: %s
" "$SERVICE_NAME" "$RONDB_IMAGE_NAME" "$SERVICE_NAME";
}

VOLUMES_FIELD="
      volumes:"

VOLUME_TEMPLATE="
      - type: %s
        source: %s
        target: %s"

ENV_FIELD="
      environment:
      - HOST_GROUP_ID=$(id -g)"

ENV_VAR_TEMPLATE="
      - %s=%s"


COMMAND_TEMPLATE="
      command: %s"

#######################
#######################
#######################

echo "Filling out templates"

# shellcheck source=./docker.env
source "$SCRIPT_DIR/docker.env"
# shellcheck source=./misc_configs.env
source "$SCRIPT_DIR/misc_configs.env"
CONFIG_INI=$(printf "$CONFIG_INI_TEMPLATE" "$REPLICATION_FACTOR")
MGM_CONNECTION_STRING=''
MGMD_IPS=''
SINGLE_MYSQLD_IP=''
MULTI_MYSQLD_IPS=''

# TODO: Use this for BENCHMARK_SERVERS in Sysbench
SINGLE_API_IP=''
MULTI_API_IPS=''

VOLUMES=()

# Add templated volume to `template` variable. Will create & mount docker
# volumes or local dirs depending on whether CLI argument `-lv` was provided.
add_volume_to_template() {
    local VOLUME_NAME="$1"
    local TARGET_DIR_PATH="$2"
    local IS_NDBD_DATA_DIR="$3"
    if [ "$VOLUME_TYPE" == local ]; then
        local VOLUME_DIR="$LOCAL_VOLUMES_DIR/$VOLUME_NAME"
        mkdir -p "$VOLUME_DIR"
        if [ "$IS_NDBD_DATA_DIR" == yes ]; then
            # The ndbd data dir has subfolders for each node ID, that are
            # created in the Dockerfile:
            # `RUN for i in $(seq 64); do mkdir -p $NDBD_DATA_DIR/$i; done`
            # When we create and mount a local directory, it is created empty so
            # we need to create these subdirectories again.
            # TODO Why isn't this a problem when using docker volumes?
            for i in $(seq 64); do
                mkdir -p "$VOLUME_DIR/$i"
            done
        fi
        template+="$(printf "$VOLUME_TEMPLATE" bind "$VOLUME_DIR" "$TARGET_DIR_PATH")"
    else
        VOLUMES+=("$VOLUME_NAME")
        template+="$(printf "$VOLUME_TEMPLATE" volume "$VOLUME_NAME" "$TARGET_DIR_PATH")"
    fi
}

# Add templated volume to `template` variable. Will always bind local file
# irrespective of CLI argument `-lv`.
add_file_to_template() {
    template+="$(printf "$VOLUME_TEMPLATE" bind "$1" "$2")"
}

# Adding the repo VERSION for easier reference in the documentation
BASE_DOCKER_COMPOSE_FILE="version: '3.8'

# RonDB-Docker version: $VERSION
services:"

for CONTAINER_NUM in $(seq "$NUM_MGM_NODES"); do
    NODE_ID=$((65 + $((CONTAINER_NUM - 1))))

    SERVICE_NAME="mgmd_$CONTAINER_NUM"
    template="$(service-template)"
    command=$(printf "$COMMAND_TEMPLATE" "[\"ndb_mgmd\", \"--ndb-nodeid=$NODE_ID\", \"--initial\"]")
    template+="$command"

    template+="
      deploy:
        resources:
          limits:
            cpus: '$MGMD_CPU_LIMIT'
            memory: $MGMD_MEMORY_LIMIT
          reservations:
            memory: $MGMD_MEMORY_RESERVATION"

    template+="$VOLUMES_FIELD"
    add_file_to_template "$CONFIG_INI_FILEPATH" "$DATA_DIR/config.ini"
    add_volume_to_template "dataDir_$SERVICE_NAME" "$DATA_DIR/mgmd" no
    add_volume_to_template "logDir_$SERVICE_NAME" "$DATA_DIR/log" no

    template+="$ENV_FIELD"

    BASE_DOCKER_COMPOSE_FILE+="$template"

    # NodeId, HostName, PortNumber, NodeActive, ArbitrationRank
    SLOT=$(printf "$CONFIG_INI_MGMD_TEMPLATE" "$NODE_ID" "$SERVICE_NAME" "1186" "1" "2")
    CONFIG_INI=$(printf "%s\n\n%s" "$CONFIG_INI" "$SLOT")

    MGM_CONNECTION_STRING+="$SERVICE_NAME:1186,"
    MGMD_IPS+="$SERVICE_NAME,"
done
# Remove last comma from MGM_CONNECTION_STRING
MGM_CONNECTION_STRING=${MGM_CONNECTION_STRING%?}
MGMD_IPS=${MGMD_IPS%?}

# We're not bothering with inactive ndbds here
NUM_DATA_NODES=$((NODE_GROUPS * REPLICATION_FACTOR))
for CONTAINER_NUM in $(seq $NUM_DATA_NODES); do
    NODE_ID=$CONTAINER_NUM

    SERVICE_NAME="ndbd_$CONTAINER_NUM"
    template="$(service-template)"
    command=$(printf "$COMMAND_TEMPLATE" "[\"ndbmtd\", \"--ndb-nodeid=$NODE_ID\", \"--initial\", \"--ndb-connectstring=$MGM_CONNECTION_STRING\"]")
    template+="$command"

    template+="
      deploy:
        resources:
          limits:
            cpus: '$NDBD_CPU_LIMIT'
            memory: $NDBD_MEMORY_LIMIT
          reservations:
            memory: $NDBD_MEMORY_RESERVATION"

    template+="$VOLUMES_FIELD"
    add_volume_to_template "dataDir_$SERVICE_NAME" "$DATA_DIR/ndb_data" yes
    add_volume_to_template "logDir_$SERVICE_NAME" "$DATA_DIR/log" no

    template+="$ENV_FIELD"

    BASE_DOCKER_COMPOSE_FILE+="$template"

    NODE_GROUP=$((CONTAINER_NUM % NODE_GROUPS))
    # NodeId, NodeGroup, NodeActive, HostName, ServerPort, FileSystemPath (NodeId)
    SLOT=$(printf "$CONFIG_INI_NDBD_TEMPLATE" "$NODE_ID" "$NODE_GROUP" "1" "$SERVICE_NAME" "11860" "$NODE_ID")
    CONFIG_INI=$(printf "%s\n\n%s" "$CONFIG_INI" "$SLOT")
done

if [ "$NUM_MYSQL_NODES" -gt 0 ]; then
    for CONTAINER_NUM in $(seq "$NUM_MYSQL_NODES"); do
        SERVICE_NAME="mysqld_$CONTAINER_NUM"
        template="$(service-template)"
        command=$(printf "$COMMAND_TEMPLATE" "[\"mysqld\"]")
        template+="$command"
        # template+="$RESOURCES_SNIPPET"

        # mysqld needs this, or will otherwise complain "mbind: Operation not permitted".
        template+="
      cap_add:
        - SYS_NICE"

        # Make sure these memory boundaries are allowed in Docker settings!
        # To check whether they are being used use `docker stats`
        template+="
      deploy:
        resources:
          limits:
            cpus: '$MYSQLD_CPU_LIMIT'
            memory: $MYSQLD_MEMORY_LIMIT
          reservations:
            memory: $MYSQLD_MEMORY_RESERVATION"

        template+="$VOLUMES_FIELD"
        add_file_to_template "$MY_CNF_FILEPATH" "$DATA_DIR/my.cnf"
        add_volume_to_template "dataDir_$SERVICE_NAME" "$DATA_DIR/mysql" no
        add_volume_to_template "mysqlFilesDir_$SERVICE_NAME" "$DATA_DIR/mysql-files" no

        # Can add the following env vars to the mysqld containers:
        # MYSQL_ROOT_PASSWORD
        # MYSQL_DATABASE

        template+="$ENV_FIELD"
        template+="$(printf "$ENV_VAR_TEMPLATE" "MYSQL_ALLOW_EMPTY_PASSWORD" "true")"
        template+="$(printf "$ENV_VAR_TEMPLATE" "MYSQL_USER" "$MYSQL_USER")"
        template+="$(printf "$ENV_VAR_TEMPLATE" "MYSQL_PASSWORD" "$MYSQL_PASSWORD")"
        if [ "$CONTAINER_NUM" -eq 1 ]; then
            # Only need one mysqld to setup databases, users, etc.
            template+="$(printf "$ENV_VAR_TEMPLATE" "MYSQL_SETUP_APP" "1")"
        fi

        BASE_DOCKER_COMPOSE_FILE+="$template"

        NODE_ID_OFFSET=$(($((CONTAINER_NUM - 1)) * MYSQLD_SLOTS_PER_CONTAINER))
        for SLOT_NUM in $(seq "$MYSQLD_SLOTS_PER_CONTAINER"); do
            NODE_ID=$((67 + NODE_ID_OFFSET + $((SLOT_NUM - 1))))
            # NodeId, NodeActive, ArbitrationRank, HostName
            SLOT=$(printf "$CONFIG_INI_MYSQLD_TEMPLATE" "$NODE_ID" "1" "1" "$SERVICE_NAME")
            CONFIG_INI=$(printf "%s\n\n%s" "$CONFIG_INI" "$SLOT")
        done

        MULTI_MYSQLD_IPS+="$SERVICE_NAME;"
        if [ "$CONTAINER_NUM" -eq 1 ]; then
            SINGLE_MYSQLD_IP+="$SERVICE_NAME"
        fi
    done
fi
# Remove last semi-colon from MULTI_MYSQLD_IPS
MULTI_MYSQLD_IPS=${MULTI_MYSQLD_IPS%?}

if [ "$NUM_API_NODES" -gt 0 ]; then
    for CONTAINER_NUM in $(seq "$NUM_API_NODES"); do
        SERVICE_NAME="api_$CONTAINER_NUM"
        template="$(service-template)"

        if [ -z "$RUN_BENCHMARK" ]; then
            # Simply keep the API container running, so we can run benchmarks manually
            command=$(printf "$COMMAND_TEMPLATE" "bash -c \"tail -F anything\"")
        else
            GENERATE_DBT2_DATA_FLAG=""
            if [ "$RUN_BENCHMARK" == "dbt2_single" ] || [ "$RUN_BENCHMARK" == "dbt2_multi" ]; then
                GENERATE_DBT2_DATA_FLAG="--generate-dbt2-data"
            fi

            # Use the ndb_waiter to wait until RonDB has started before running benchmark
            # Added extra sleep for mysqlds; may have to increase this
            command=$(printf "$COMMAND_TEMPLATE" ">
          bash -c \"ndb_waiter --ndb-connectstring=$MGM_CONNECTION_STRING &&
                    sleep 35 &&
                    bench_run.sh --verbose --default-directory $BENCH_DIR/$RUN_BENCHMARK $GENERATE_DBT2_DATA_FLAG\"")
        fi

        template+="$command"

        # Make sure these memory boundaries are allowed in Docker settings!
        # To check whether they are being used use `docker stats`
        template+="
      deploy:
        resources:
          limits:
            cpus: '$API_CPU_LIMIT'
            memory: $API_MEMORY_LIMIT
          reservations:
            memory: $API_MEMORY_RESERVATION"

        template+="$VOLUMES_FIELD"
        if [ "$NUM_MYSQL_NODES" -gt 0 ]; then
            add_volume_to_template "sysbench_single" "$BENCH_DIR/sysbench_single" no
            add_volume_to_template "dbt2_single" "$BENCH_DIR/dbt2_single" no
            if [ "$NUM_MYSQL_NODES" -gt 1 ]; then
                add_volume_to_template "sysbench_multi" "$BENCH_DIR/sysbench_multi" no
                add_volume_to_template "dbt2_multi" "$BENCH_DIR/dbt2_multi" no
            fi
        fi

        # If we are using volumes for the benchmarking directories, we have to mount these files single-handedly.
        # They will then also be available inside the volumes.
        if [ "$VOLUME_TYPE" == "docker" ]; then
            if [ "$NUM_MYSQL_NODES" -gt 0 ]; then
                add_file_to_template "$DBT2_CONF_SINGLE_FILEPATH" "$BENCH_DIR/dbt2_single/dbt2_run_1.conf"
                add_file_to_template "$AUTOBENCH_SYS_SINGLE_FILEPATH" "$BENCH_DIR/sysbench_single/autobench.conf"
                add_file_to_template "$AUTOBENCH_DBT2_SINGLE_FILEPATH" "$BENCH_DIR/dbt2_single/autobench.conf"
            fi
            if [ "$NUM_MYSQL_NODES" -gt 1 ]; then
                add_file_to_template "$DBT2_CONF_MULTI_FILEPATH" "$BENCH_DIR/dbt2_multi/dbt2_run_1.conf"
                add_file_to_template "$AUTOBENCH_SYS_MULTI_FILEPATH" "$BENCH_DIR/sysbench_multi/autobench.conf"
                add_file_to_template "$AUTOBENCH_DBT2_MULTI_FILEPATH" "$BENCH_DIR/dbt2_multi/autobench.conf"
            fi
        fi

        template+="$ENV_FIELD"
        template+="$(printf "$ENV_VAR_TEMPLATE" "MYSQL_PASSWORD" "$MYSQL_PASSWORD")"

        BASE_DOCKER_COMPOSE_FILE+="$template"

        NODE_ID_OFFSET=$(($((CONTAINER_NUM - 1)) * API_SLOTS_PER_CONTAINER))
        for SLOT_NUM in $(seq "$API_SLOTS_PER_CONTAINER"); do
            NODE_ID=$((195 + NODE_ID_OFFSET + $((SLOT_NUM - 1))))
            # NodeId, NodeActive, ArbitrationRank, HostName
            SLOT=$(printf "$CONFIG_INI_API_TEMPLATE" "$NODE_ID" "1" "1" "$SERVICE_NAME")
            CONFIG_INI=$(printf "%s\n\n%s" "$CONFIG_INI" "$SLOT")
        done

        MULTI_API_IPS+="$SERVICE_NAME;"
        if [ "$CONTAINER_NUM" -eq 1 ]; then
            SINGLE_API_IP+="$SERVICE_NAME"
        fi
    done
fi
# Remove last semi-colon from MULTI_API_IPS
MULTI_API_IPS=${MULTI_API_IPS%?}

# Append volumes to end of file if docker volumes are used
if [ "$VOLUME_TYPE" == docker ]; then
    BASE_DOCKER_COMPOSE_FILE+="

volumes:"
    for VOLUME in "${VOLUMES[@]}"; do
        BASE_DOCKER_COMPOSE_FILE+="
    $VOLUME:"
    done

    BASE_DOCKER_COMPOSE_FILE+="
"
fi

#######################
#######################
#######################

echo "Writing data to files"

if [ "$NUM_MYSQL_NODES" -gt 0 ]; then
    echo "Writing my.cnf"
    MY_CNF=$(printf "$MY_CNF_TEMPLATE" "$MYSQLD_SLOTS_PER_CONTAINER" "$MGM_CONNECTION_STRING")
    echo "$MY_CNF" > "$MY_CNF_FILEPATH"

    if [ "$NUM_API_NODES" -gt 0 ]; then
        echo "Writing benchmarking files for single mysqlds"

        # This will always have 1 api and 1 mysqld container, and 1 Sysbench instance
        AUTOBENCH_SYSBENCH_SINGLE=$(printf "$AUTOBENCH_SYSBENCH_TEMPLATE" \
            "$SINGLE_MYSQLD_IP" "$MYSQL_USER" "$MYSQL_PASSWORD" \
            "$MYSQLD_SLOTS_PER_CONTAINER" "$MGMD_IPS" \
            "1")
        echo "$AUTOBENCH_SYSBENCH_SINGLE" > "$AUTOBENCH_SYS_SINGLE_FILEPATH"

        AUTOBENCH_DBT2_SINGLE=$(printf "$AUTOBENCH_DBT2_TEMPLATE" \
            "$SINGLE_MYSQLD_IP" "$MYSQL_USER" "$MYSQL_PASSWORD" \
            "$MYSQLD_SLOTS_PER_CONTAINER" "$MGMD_IPS")
        echo "$AUTOBENCH_DBT2_SINGLE" > "$AUTOBENCH_DBT2_SINGLE_FILEPATH"

        if [ "$NUM_MYSQL_NODES" -gt 1 ]; then
            echo "Writing benchmarking files for multiple mysqlds"

            AUTOBENCH_SYSBENCH_MULTI=$(printf "$AUTOBENCH_SYSBENCH_TEMPLATE" \
                "$MULTI_MYSQLD_IPS" "$MYSQL_USER" "$MYSQL_PASSWORD" \
                "$MYSQLD_SLOTS_PER_CONTAINER" "$MGMD_IPS" \
                "$NUM_MYSQL_NODES")
            echo "$AUTOBENCH_SYSBENCH_MULTI" > "$AUTOBENCH_SYS_MULTI_FILEPATH"

            AUTOBENCH_DBT2_MULTI=$(printf "$AUTOBENCH_DBT2_TEMPLATE" \
                "$MULTI_MYSQLD_IPS" "$MYSQL_USER" "$MYSQL_PASSWORD" \
                "$MYSQLD_SLOTS_PER_CONTAINER" "$MGMD_IPS")
            echo "$AUTOBENCH_DBT2_MULTI" > "$AUTOBENCH_DBT2_MULTI_FILEPATH"
        fi
    fi
fi

echo "$BASE_DOCKER_COMPOSE_FILE" > "$DOCKER_COMPOSE_FILEPATH"
echo "$CONFIG_INI" > "$CONFIG_INI_FILEPATH"

# Save files for documentation
if [ -n "$SAVE_SAMPLE_FILES" ]; then
    cp "$PARSED_ARGUMENTS_FILEPATH" "$SCRIPT_DIR/sample_files/parsed_arguments.txt"
    cp "$CONFIG_INI_FILEPATH" "$SCRIPT_DIR/sample_files/config.ini"
    cp "$DOCKER_COMPOSE_FILEPATH" "$SCRIPT_DIR/sample_files/docker_compose.yml"
    if [ "$NUM_MYSQL_NODES" -gt 0 ]; then
        echo "$MY_CNF" > "$MY_CNF_FILEPATH"
        cp "$MY_CNF_FILEPATH" "$SCRIPT_DIR/sample_files/my.cnf"
    fi
fi

if which docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE=docker-compose
elif docker compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    echo "docker compose not installed."
    exit 1
fi

# Make directories accessible by group members. This is used as a workaround
# since the local (host) user likely has a different UID from the user in the
# docker container.
chmod -R g=u "$AUTOGENERATED_FILES_DIR"

# Remove previous volumes
$DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILEPATH" -p "rondb_$FILE_SUFFIX" down -v
# Run fresh setup
$DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILEPATH" -p "rondb_$FILE_SUFFIX" up $DETACHED
