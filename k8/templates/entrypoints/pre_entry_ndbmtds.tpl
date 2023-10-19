# Calculate Node Id based on Pod name and Node Group

{{ define "pre_entrypoint_ndbmtds" }}
#!/bin/bash

set -e

# Equivalent to replication factor of pod
POD_ID=$(echo $POD_NAME | grep -o '[0-9]\+$')

echo "[K8s Entrypoint ndbmtd] Running Pod ID: $POD_ID in Node Group: $NODE_GROUP"

NODE_ID_OFFSET=$(($NODE_GROUP*3))
NODE_ID=$(($NODE_ID_OFFSET+$POD_ID+1))

echo "[K8s Entrypoint ndbmtd] Running Node Id: $NODE_ID"

# Original entrypoint
source ./docker/rondb_standalone/entrypoints/entrypoint.sh "$@" --ndb-nodeid=$NODE_ID
{{ end }}
