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

# WARNING: This file has been dumbed down to meet the simple requirements of
#          running / testing a mysql server. DO NOT use this file in a
#          production setting. Specifically do not use the MYSQL_BENCH_PASSWORD
#          in the command-line.

# Fetch value from server config
# We use mysqld --verbose --help instead of my_print_defaults because the
# latter only show values present in config files, and not server defaults
_get_config() {
    local conf="$1"
    shift
    "$@" --verbose --help 2>/dev/null | grep "^$conf" | awk '$1 == "'"$conf"'" { print $2; exit }'
}

# Check if entrypoint (and the container) is running as root
# Important: Distinguish between MYSQLD_USER and MYSQL_BENCH_USER
if [ "$(id --user)" = "0" ]; then
    echo "[entrypoints/mysqld.sh] We are running as root; setting MYSQLD_USER to 'mysql'"
    is_root=1
    install_devnull="install /dev/null -m0600 -omysql -gmysql"
    MYSQLD_USER=mysql
else
    echo "[entrypoints/mysqld.sh] Setting MYSQLD_USER to current non-root user"
    install_devnull="install /dev/null -m0600"
    MYSQLD_USER=$(id --user --name)
fi

# Make sure that "--defaults-file" is always run as second argument
# Otherwise there is a risk that it might not be read
shift
set -- mysqld --defaults-file="$RONDB_DATA_DIR/my.cnf" --user="$MYSQLD_USER" "$@"
echo "[entrypoints/mysqld.sh] \$@: $*"

# Test that the server can start. We redirect stdout to /dev/null so
# only the error messages are left.
result=0
output=$("$@" --validate-config) || result=$?
if [ ! "$result" = "0" ]; then
    echo >&2 '[entrypoints/mysqld.sh] ERROR: Unable to start MySQL. Please check your configuration.'
    echo >&2 "[entrypoints/mysqld.sh] $output"
    exit 1
fi
echo "[entrypoints/mysqld.sh] The MySQL configuration has been validated"

echo '[entrypoints/mysqld.sh] Initializing database...'

# Technically, specifying the user here is unnecessary since that is
# the default user according to the Dockerfile
"$@" \
    --log-error-verbosity=3 \
    --initialize-insecure \
    --explicit_defaults_for_timestamp

echo '[entrypoints/mysqld.sh] Database initialized'

export MYSQLD_PARENT_PID=$$
if [ -z "$MYSQL_SETUP_APP" ]; then
    echo '[entrypoints/mysqld.sh] Not setting up app here; going straight to execution of MySQLd'
    echo "[entrypoints/mysqld.sh] Running: $*"
    exec "$@"
fi

echo '[entrypoints/mysqld.sh] Executing MySQLd as daemon with no networking allowed...'

"$@" \
    --daemonize \
    --skip-networking

echo '[entrypoints/mysqld.sh] Successfully executed MySQLd with networking disabled, we can start changing users, passwords & permissions via a local socket without other clients interfering.'

# Get config
SOCKET="$(_get_config 'socket' "$@")"
echo "[entrypoints/mysqld.sh] SOCKET: $SOCKET"

echo "[entrypoints/mysqld.sh] Pinging MySQLd..."
for ping_attempt in {1..30}; do
    if mysqladmin --socket="$SOCKET" ping &>/dev/null; then
        echo "[entrypoints/mysqld.sh] Successfully pinged MySQLd on attempt $ping_attempt"
        break
    fi
    echo "[entrypoints/mysqld.sh] Failed pinging MySQLd on attempt $ping_attempt"
    sleep 1
done
if [ "$ping_attempt" = 30 ]; then
    echo >&2 '[entrypoints/mysqld.sh] Timeout during MySQL init.'
    exit 1
fi

# If the password variable is a filename we use the contents of the file. We
# read this first to make sure that a proper error is generated for empty files.
if [ -f "$MYSQL_ROOT_PASSWORD" ]; then
    MYSQL_ROOT_PASSWORD="$(cat "$MYSQL_ROOT_PASSWORD")"
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        echo >&2 '[entrypoints/mysqld.sh] Empty MYSQL_ROOT_PASSWORD file specified.'
        exit 1
    fi
fi

if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo >&2 '[entrypoints/mysqld.sh] No password option specified for root user.'
fi

# Defining the client command used throughout the script
# Since networking is not permitted for this mysql server, we have to use a socket to connect to it
# "SET @@SESSION.SQL_LOG_BIN=0;" is required for products like group replication to work properly
DUMMY_ROOT_PASSWORD=
function mysql() { command mysql -uroot -hlocalhost --password="$DUMMY_ROOT_PASSWORD" --protocol=socket --socket="$SOCKET" --init-command="SET @@SESSION.SQL_LOG_BIN=0;"; }
echo '[entrypoints/mysqld.sh] Overwrote the mysql client command for this script'

echo '[entrypoints/mysqld.sh] Changing the root user password'
mysql <<EOF
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
    FLUSH PRIVILEGES;
EOF

DUMMY_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD

# Benchmarking table; all other tables will be created by the benchmakrs themselves
echo "CREATE DATABASE IF NOT EXISTS \`dbt2\` ;" | mysql
echo "CREATE DATABASE IF NOT EXISTS \`ycsb\` ;" | mysql

# shellcheck disable=SC2153
if [ "$MYSQL_BENCH_USER" ]; then
    echo "[entrypoints/mysqld.sh] Running this command now:"
    echo "CREATE USER '$MYSQL_BENCH_USER'@'%' IDENTIFIED BY '$MYSQL_BENCH_PASSWORD' ;"
    echo "CREATE USER '$MYSQL_BENCH_USER'@'%' IDENTIFIED BY '$MYSQL_BENCH_PASSWORD' ;" | mysql

    # TODO: Consider placing into docker-entrypoint-initdb.d
    # Grant MYSQL_BENCH_USER rights to all benchmarking databases
    echo "GRANT NDB_STORED_USER ON *.* TO '$MYSQL_BENCH_USER'@'%' ;" | mysql
    echo "GRANT ALL PRIVILEGES ON \`sysbench%\`.* TO '$MYSQL_BENCH_USER'@'%' ;" | mysql
    echo "GRANT ALL PRIVILEGES ON \`dbt%\`.* TO '$MYSQL_BENCH_USER'@'%' ;" | mysql
    echo "GRANT ALL PRIVILEGES ON \`sbtest%\`.* TO '$MYSQL_BENCH_USER'@'%' ;" | mysql
    echo "GRANT ALL PRIVILEGES ON \`ycsb%\`.* TO '$MYSQL_BENCH_USER'@'%' ;" | mysql
else
    echo '[entrypoints/mysqld.sh] Not creating custom user. MYSQL_BENCH_USER and MYSQL_BENCH_PASSWORD must be specified to do so.'
fi

for f in ./docker/rondb_standalone/entrypoints/init_scripts/*; do
    case "$f" in
    *.sh)
        echo "[entrypoints/mysqld.sh] running $f"
        . "$f"
        ;;
    *.sql)
        echo "[entrypoints/mysqld.sh] running $f"
        cat $f | mysql
        ;;
    *) echo "[entrypoints/mysqld.sh] ignoring $f" ;;
    esac
done

# When using a local socket, mysqladmin shutdown will only complete when the
# server is actually down.
echo '[entrypoints/mysqld.sh] Shutting down MySQLd via mysqladmin...'
mysqladmin -uroot --password="$MYSQL_ROOT_PASSWORD" shutdown --socket="$SOCKET"
echo "[entrypoints/mysqld.sh] Successfully shut down MySQLd"

echo '[entrypoints/mysqld.sh] MySQL init process done. Ready for start up.'
echo "[entrypoints/mysqld.sh] Running: $*"
exec "$@"
