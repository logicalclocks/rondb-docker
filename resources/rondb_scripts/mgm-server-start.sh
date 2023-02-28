#!/usr/bin/env sh 

USERID=$(id | sed -e 's/).*//; s/^.*(//;')
if [ "X$USERID" != "Xmysql" ]; then
   echo "You should have started the cluster as user: 'mysql'."
   echo "If you continue, you will change ownership of database files"
   echo "from 'mysql' to '$USERID'."
   exit -3
fi  

echo "Testing to see if a cluster is already running on $MGM_CONN_STRING ..." 
# /srv/hops/mysql/bin/ndb_mgm -c $MGM_CONN_STRING -e \"show\"> /dev/null
netstat -ltu | grep "1186"

if [ $? -eq 0 ] ; then
    echo "A management server is already running on $MGM_CONN_STRING" 
    exit 2
else
    echo "No management server is running on $MGM_CONN_STRING; we're good to go"
fi


if [ ! -e /srv/hops/mysql/bin/ndb_mgmd ] ; then
    echo "Error: could not find file: /srv/hops/mysql/bin/ndb_mgmd"
    exit 3
fi

mgmd_command="/srv/hops/mysql/bin/ndb_mgmd --ndb-nodeid=$NDB_MGMD_NODE_ID -f /srv/hops/mysql-cluster/config.ini  --configdir=/srv/hops/mysql-cluster/mgmd --reload --initial"

# This is not in the original cloud setup;
# It is used for alternative process managers such as supervsisord
# that cannot daemonize processes.
if [ -n "$NO_DAEMON" ]; then
    echo "Starting the MySQL Management as a foreground process"
    mgmd_command="$mgmd_command --nodaemon"
    echo "Running command '$mgmd_command'"
    exec $mgmd_command
fi

$mgmd_command




RES=$(echo $?)
if [ "$RES" -ne 0 ] ; then
    echo ""
    echo "Error when starting the management server: $?."
    echo ""
    exit 1
fi
echo "Started the MySQL Management server - ndb_mgmd." 
exit "$RES"
