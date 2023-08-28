# Managed RonDB

The code in this directory allows users to test managed RonDB locally using Docker Compose. Managed RonDB allows the user to perform live operations on the cluster such as:

* scale data nodes/MySQLds/API nodes
* do online software up/downgrades
* create backups
* restore from backups

The [desired_state.jsonc](desired_state.jsonc) file describes the API to managed RonDB.

## Demo

This demo shows how a managed RonDB cluster is created and then reconfigured by changing the desired state JSON file.

[![Managed RonDB Demo](https://img.youtube.com/vi/ihtU9Z8SQFU/0.jpg)](https://www.youtube.com/watch?v=ihtU9Z8SQFU)

## Dependencies

* Docker

Also, make sure your Docker engine has enough resources configured. 10-16GB of memory and 6-8 CPUs should be a reasonable amount to test a number of cluster configurations and reconfigurations.

## Quickstart

```bash
docker-compose up -d
docker logs flask-server -f
```

Now you can follow how the cluster is being created. You can change the [desired_state.jsonc](desired_state.jsonc) file both before running a cluster or whilst it is running. The leader ndb-agent will accept new desired states when its `RECONCILIATION STATE` is `AT_DESIRED_STATE` or `ERROR_STATE`. You can however change the json file whenever you want to.

**_Warning_**: Recommended editors to change the [desired_state.jsonc](desired_state.jsonc) file: Nano, VS Code. **DO NOT** use Vim or Text Editor (Mac). These will [change the inode of the file when saving](https://unix.stackexchange.com/questions/36467/why-inode-value-changes-when-we-edit-in-vi-editor), breaking the mount.

## Images in Docker Compose File

The Docker Compose file consists of the following images:

### [hopsworks/rondb-managed](https://hub.docker.com/repository/docker/hopsworks/rondb-managed):

This image uses `hopsworks/rondb-standalone` as a base image and then installs the ***ndb-agent*** on top of it. The ndb-agent is our database management tool that is responsible for the orchestration of RonDB. The ndb-agent contains both the logic of the state machine (how to move to a desired state given a certain internal state) and gRPC functions. The leader ndb-agent uses the state machine to decide when to call which gRPC function on which ndb-agent (it can also call a gRPC function on itself). Example gRPC functions include functions to start/stop any RonDB program (management server, data node, MySQLd, etc.) inside the same container. In order to run both RonDB services and the ndb-agent in the containers, we use supervisorctl as a process manager.

### [hopsworks/flask-server-rondb](https://hub.docker.com/repository/docker/hopsworks/flask-server-rondb):

This is a web-server which forwards the desired state of the cluster to the leader ndb-agent and is capable of spawning new containers if the leader ndb-agent asks it to. It is light-weight program, which simulates a web server that can spawn VMs in the cloud. The [desired_state.jsonc](desired_state.jsonc) file is mounted into the Flask server, so that the user can change the desired state for a running cluster.

### [hopsworks/nginx-rondb](https://hub.docker.com/repository/docker/hopsworks/nginx-rondb):

This is a reverse proxy that hosts tarballs of different versions of the ndb-agent and RonDB. For the ndb-agent, the versions are all equivalent, but they can be used for testing a rolling software upgrade. Regarding RonDB, the nginx server just forwards the requests to https://repo.hops.works and then caches the downloads, so that we save internet bandwidth.

## Background on Ndb-Agent

The ndb-agent is a Go program, which works similar to Kubernetes. At the heart of the ndb-agent logic is the "reconciliation loop" and a `RECONCILIATION STATE`. The `RECONCILIATION STATE` can have three different values:

- `AT_DESIRED_STATE`
- `ERROR_STATE`
- `WORKING_TOWARDS_DESIRED_STATE`

Whenever the ndb-agent realises that its internal state diverges from the desired state, it will move to `WORKING_TOWARDS_DESIRED_STATE` and not ask for new desired states. The `ERROR_STATE` means that it has tried reaching the desired state n times (n is configurable) and has failed. The idea is that any (validated) desired state can be reached within one reconciliation loop.

Both at the `ERROR_STATE` and the `AT_DESIRED_STATE`, the ndb-agent will continue observing its state. If it is `AT_DESIRED_STATE` and it notices that it has diverged from its latest accepted desired state, it will change its `RECONCILIATION STATE` to `WORKING_TOWARDS_DESIRED_STATE` and run the reconciliation loop again.

All logic of the ndb-agent's state machine is run on the ndb-agent leader. This decides which actions to run to reach a desired state. Most importantly, it runs gRPC functions on the follower ndb-agents. For example, it will execute the gRPC function `StartDataNode` on the ndb-agent which is in the container/VM where the leader decides that a RonDB data node should be run. The leader is elected via the Raft consensus algorithm and we thereby also use Raft to persist the internal state of the ndb-agent. The Raft cluster is bootstrapped with the `bootstrap_agent` container, which then contains the first leader. This container can be removed (manually) once the first desired state has been reached and another container will take over leadership. There is no RonDB service running on the `bootstrap_agent`.

## How the Ndb-Agent is tested

The ndb-agent has the following test suites:

1. **Standard unit tests**: These are basic function-level unit tests.
2. **Generative unit tests**: A big challenge of the ndb-agent's state machine is to make sure that it does not navigate into state deadlocks and that it is capable of reaching any desired state it accepts. Therefore, using a state-transformation-test mode, we create dummy returns for all gRPC functions, change the internal state as we would expect it to and then run through thousands of random desired states and corresponding reconfigurations. At the end of every reconciliation loop, we can then check whether we have reached the desired state. If we don't, the tests fail.
3. **Regression unit tests**: These are tests that have been created by the generative tests and have failed. They are essentially states (desired state + internal state before reconfiguration) serialised as JSON files where the reconciliation loop failed to reach the desired state.
4. **RonDB-detached Docker tests**: This is a similar setup to the one in this repository. However, `rondb-standalone` is not used as a base image, and all system calls the ndb-agent does are replaced by dummies. We can therefore test whether the communication between the ndb-agent works by running through a number of pre-defined desired states, sent by the flask server.
5. **RonDB-attached Docker tests**: This is the setup that we have in this repository. The only difference is that we run through a number of pre-defined desired states and make sure that the communication between the ndb-agent and RonDB works.
6. **Terraform integration tests**: These are live tests in the cloud, where we have our production web server creating VMs instead of containers.

## Ongoing Work

- The ndb-agent has not been tested with error injections. Killing a container and making sure the reconciliation loop takes care of replacing it with a new VM/container has only been proven in manual tests so far.
- It is not yet recommended to run any outside applications against managed RonDB, since it is still a closed eco-system without any exposed ports. This is mostly due to the fact that the containers are dynamic and so work still has to be done for load balancing / service detection.
