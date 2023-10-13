#!/bin/bash
# Copyright (c) 2017, 2021, Oracle and/or its affiliates.
# Copyright (c) 2021, 2022, Hopsworks AB and/or its affiliates.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
set -e

# https://stackoverflow.com/a/246128/9068781
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source $SCRIPT_DIR/mysqld_configure.sh "$@"

export MYSQLD_PARENT_PID=$$

# Kubernetes only
if [ -n "$POD_NAME" ]; then
    # We use a different logic in Kubernetes because we assume containers to start/restart
    # regularly, so we don't want to initialize the databases every time.
    echo "[entrypoints/mysqld.sh] We're running inside of Kubernetes (POD_NAME is set to '$POD_NAME')"
    if [[ $POD_NAME != *"-0" ]]; then
        echo "[entrypoints/mysqld.sh] Not initializing MySQL databases because this is not the first MySQLd pod"
        MYSQL_INITIALIZE_DB=
    else
        if [ ! -f "$MYSQL_DATABASES_INIT_FILE" ]; then
            echo "[entrypoints/mysqld.sh] File $MYSQL_DATABASES_INIT_FILE does not exist; we're initializing MySQL databases"
            MYSQL_INITIALIZE_DB=1
        else
            echo "[entrypoints/mysqld.sh] File $MYSQL_DATABASES_INIT_FILE already exist; we're not initializing MySQL databases"
            MYSQL_INITIALIZE_DB=
        fi
    fi
fi

if [ ! -z "$MYSQL_INITIALIZE_DB" ]; then
    source $SCRIPT_DIR/mysqld_init_db.sh "$@"

    # Kubernetes only
    if [ -n "$POD_NAME" ]; then
        echo "[entrypoints/mysqld.sh] Creating file $MYSQL_DATABASES_INIT_FILE"
        touch $MYSQL_DATABASES_INIT_FILE
    fi

else
    echo "[entrypoints/mysqld.sh] Not initializing MySQL databases"
fi

# This is not being used anymore
if [ -n "$MYSQL_INITIALIZE_ONLY" ]; then
    echo "[entrypoints/mysqld.sh] MYSQL_INITIALIZE_ONLY is set, so we're exiting without starting the MySQLd"
    exit 0
fi

echo '[entrypoints/mysqld.sh] Ready for starting up MySQLd'
echo "[entrypoints/mysqld.sh] Running: $*"
exec "$@"
