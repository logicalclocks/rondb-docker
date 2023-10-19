# Note: This ignores the main.sh script; Not very important when running with volumes though
{{ define "entrypoint_mysqld" }}
#!/bin/bash

set -e

# https://stackoverflow.com/a/246128/9068781
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

###################
# SED MY.CNF FILE #
###################

# Calculate Node Ids based on Pod name & sed my.cnf file

RAW_MYCNF_FILEPATH=/srv/hops/mysql-cluster/my-raw.cnf
MYCNF_FILEPATH=/srv/hops/mysql-cluster/my.cnf

cp $RAW_MYCNF_FILEPATH $MYCNF_FILEPATH

# Equivalent to replication factor of pod
MYSQLD_NR=$(echo $POD_NAME | grep -o '[0-9]\+$')

echo "[K8s Entrypoint MySQLd] Running MySQLd nr. $MYSQLD_NR with $CONNECTIONS_PER_MYSQLD connections"

FIRST_NODE_ID=$((67+($MYSQLD_NR*$CONNECTIONS_PER_MYSQLD)))
LAST_NODE_ID=$(($FIRST_NODE_ID+$CONNECTIONS_PER_MYSQLD-1))

NODES_SEQ=$(seq -s, $FIRST_NODE_ID $LAST_NODE_ID)

echo "[K8s Entrypoint MySQLd] Running Node Ids: $NODES_SEQ"

# Replace the existing line with the new sequence in my.cnf
sed -i "/ndb-cluster-connection-pool-nodeids/c\ndb-cluster-connection-pool-nodeids=$NODES_SEQ" $MYCNF_FILEPATH

###########################################
# CONFIGURE MYSQLD & INITIALIZE DATABASES #
###########################################

source ./docker/rondb_standalone/entrypoints/mysqld_configure.sh "$@"

if [[ $POD_NAME != *"-0" ]]; then
    echo "[K8s Entrypoint MySQLd] Not initializing MySQL databases because this is not the first MySQLd pod"
    MYSQL_INITIALIZE_DB=
else
    if [ ! -f "$MYSQL_DATABASES_INIT_FILE" ]; then
        echo "[K8s Entrypoint MySQLd] File $MYSQL_DATABASES_INIT_FILE does not exist; we're initializing MySQL databases"
        MYSQL_INITIALIZE_DB=1
    else
        echo "[K8s Entrypoint MySQLd] File $MYSQL_DATABASES_INIT_FILE already exist; we're not initializing MySQL databases"
        MYSQL_INITIALIZE_DB=
    fi
fi

if [ ! -z "$MYSQL_INITIALIZE_DB" ]; then
    source ./docker/rondb_standalone/entrypoints/mysqld_init_db.sh "$@"

    echo "[K8s Entrypoint MySQLd] Creating file $MYSQL_DATABASES_INIT_FILE"
    touch $MYSQL_DATABASES_INIT_FILE
else
    echo "[K8s Entrypoint MySQLd] Not initializing MySQL databases"
fi

echo "[K8s Entrypoint MySQLd] Ready for starting up MySQLd"
echo "[K8s Entrypoint MySQLd] Running: $*"
exec "$@"

{{ end }}
