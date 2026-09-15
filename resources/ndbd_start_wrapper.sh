#!/bin/bash
# Compose-time wrapper for ndbmtd. Bind-mounted into ndbd containers by
# build_run_docker.sh and used as the container command; NOT baked into the
# image (the image is pulled, so its files are not ours to change).
#
# Not to be confused with the image's rondb_scripts/ndbd-start.sh, which is a
# VM/systemd-era script: it requires a 'mysql' user that does not exist in
# this image, takes its node id from env vars instead of argv, and in its
# NO_DAEMON mode uses --foreground, which logs to stdout -- the exact problem
# this wrapper exists to solve.
#
# Why this wrapper is needed:
# ndbmtd defaults to --daemon, and it is daemonizing that redirects fd 1 and 2
# into $DataDir/ndb_<nodeid>_out.log. The image's entrypoint (main.sh) appends
# --nodaemon to every non-rdrs command, because in daemon mode the angel
# process detaches, the foreground command returns, and the container would
# exit. The side effect is that the data node's own log -- thread and memory
# configuration at startup, and the watchdog "overslept" / "kernel thread is
# stuck" warnings that precede a node death -- goes to stdout and never
# reaches a file. None of it is in the mgmd's cluster.log, which only records
# cluster *events*.
#
# This wrapper does by hand what daemon mode does to fd 1 and 2, without
# detaching: same destination file, same name, process stays in the
# foreground so the container lives and ndbmtd keeps receiving signals.
set -e

# main.sh appends --nodaemon to our argv before exec'ing us; it is passed
# straight through to ndbmtd below, which is what keeps us in the foreground.
NODE_ID=unknown
for arg in "$@"; do
    case "$arg" in
        --ndb-nodeid=*) NODE_ID="${arg#*=}" ;;
    esac
done

LOG_FILE="${RONDB_DATA_DIR:-/srv/hops/mysql-cluster}/log/ndb_${NODE_ID}_out.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Append, not truncate: on a container restart a truncating redirect would
# erase the previous attempt's death message -- the very line being sought.
echo "[ndbd_start_wrapper.sh] logging to $LOG_FILE"
exec ndbmtd "$@" >> "$LOG_FILE" 2>&1
