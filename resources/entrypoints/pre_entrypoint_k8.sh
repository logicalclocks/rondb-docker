#!/bin/bash

set -e

# https://stackoverflow.com/a/246128/9068781
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Equivalent to replication factor of pod
POD_ID=$(echo $POD_NAME | grep -o '[0-9]\+$')

echo "[Pre-entrypoint-k8] Running Pod ID: $POD_ID in Node Group: $NODE_GROUP"

NODE_ID_OFFSET=$(($NODE_GROUP*3))
NODE_ID=$(($NODE_ID_OFFSET+$POD_ID+1))

echo "[Pre-entrypoint-k8] Running Node Id: $NODE_ID"

exec $SCRIPT_DIR/entrypoint.sh "$@" --ndb-nodeid=$NODE_ID
