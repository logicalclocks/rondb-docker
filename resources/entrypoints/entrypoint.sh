#!/bin/bash

set -e

echo "[Entrypoint] RonDB Docker Image"

# The host user (which executes build_run_docker.sh) might not have the same UID
# as mysql inside the container. In order for both users to be able to read and
# write in the mounted volumes, we add mysql to a group with the same GID as the
# host user's group.
if [ "$(getent group "$HOST_GROUP_ID")" ]; then
	echo "[Entrypoint] group $HOST_GROUP_ID exists."
else
	echo "[Entrypoint] group $HOST_GROUP_ID does not exist."
	addgroup --gid "$HOST_GROUP_ID" host_group_dummy
fi

# We change mysql's initial login group to that of the host user. This is so
# that files created by mysql will belong to this group.
usermod -g "$HOST_GROUP_ID" mysql

# The original mysql group is added back as a supplementary group.
usermod -a -G mysql mysql

# Execute main.sh as mysql user with preserved environment and arguments.
sudo -E -u mysql "$(pwd)/docker/rondb_standalone/entrypoints/main.sh" "$@"
