# Managed RonDB

The code in this directory allows users to test managed RonDB locally using Docker Compose.

The Docker Compose project consists of the following images:

* **ndb-agent**: This our database management tool that is responsible for the orchestration of RonDB. It uses `hopsworks/rondb-standalone` as a base image, so the ndb-agent of a given container can start/stop any RonDB program (management server, data node, MySQLd, etc.) inside the same container. We use supervisorctl to run multiple processes in the containers.
* **flask-server**: This is a web-server which forwards the desired state of the cluster to the leader ndb-agent and is capable of spawing new containers if the ndb-agent asks it to. It is light-weight program, which simulates a web server that can spawn VMs in the cloud. The [desired_state.jsonc](desired_state.jsonc) file is mounted into the Flask server, so that the user can change the desired state for a running cluster.
* **nginx-server**: This is a reverse proxy that hosts tarballs of different versions of the ndb-agent and RonDB. For the ndb-agent, the versions are all equivalent, but they can be used for testing a rolling software upgrade. Regarding RonDB, the nginx server just forwards the requests to https://repo.hops.works and then caches the downloads, so that we save internet bandwidth.

## Dependencies

Docker

## Quickstart

```bash
docker-compose up -d
docker logs flask-server-rondb -f
```

Now you can follow how the cluster is being created. You can change the [desired_state.jsonc](desired_state.jsonc) file both before running a cluster or whilst it is running. The leader ndb-agent will accept new desired states when its `RECONCILIATION STATE` is `AT_DESIRED_STATE` or `ERROR_STATE`. You can however change the json file whenever you want to.

## Ongoing Work

- The ndb-agent currently does not yet support leader election, nor is the leader's state replicated. This means that if the bootstrap_mgm container dies, the cluster cannot be managed anymore.
