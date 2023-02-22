# RonDB with Docker

This repository creates the possibility of:
- building cross-platform RonDB images
- running local (non-production) RonDB clusters with docker-compose
- benchmarking RonDB with Sysbench and DBT2 on localhost
- demo the usage of managed RonDB (upcoming)

To learn more about RonDB, have a look at [rondb.com](https://rondb.com).

## Quickstart

Dependencies:
- Docker, docker-compose, Docker Buildx (if you use DockerHub this dependency isn't there)

The run.sh script makes it very easy to start a RonDB cluster in Docker Compose using 3 commands:
1. git clone https://github.com/logicalclocks/rondb-docker rondb-docker
2. cd rondb-docker
3. ./run.sh

The run.sh makes it very easy to run with 5 different user profiles.
1. mini This profile starts a RonDB cluster with 1 data node, 1 MGM Server, 1 MySQL Server and
        1 API node. It uses around 2.5 GB of memory and up to 4 CPUs.
        This profile is intended for busy development machines and machines with down to 8 GB of
        memory.

2. small This is the default setup. It uses about 6 GB of memory and up to 16 CPUs. This setup
         and all larger setups have 1 MGM server, 2 data nodes, 2 MySQL Server and 1 API node.
         This profile is intended for development machines with at least 16 GB of memory and
         up to 16 CPUs.

3. medium This profile is intended for development machines with 32 GB of memory and up to 16
          CPUs. It uses about 16 GB of memory and up to 16 CPUs.

4. large This profile is intended for development machines with up to 32 CPUs and at least 32 GB
         of memory. It will use up to 20 GB of memory and up to 32 CPUs.

5. xlarge This profile is intended for workstations with at least 64 GB of memory and up to
          64 CPUs. It will use up to 30 GB of memory and up to 50 CPUs.

This Docker environment is intended for developers wanting to develop applications towards RonDB.
It is used also for development of RonDB and its REST API server functionality. This means that
it is frequently used with Docker Desktop on Mac OS X using ARM CPUs, on Windows laptops using
Docker Desktop in combination with WSL 2 and on Linux laptops and desktops and workstations.
It can also be used in Cloud VMs.

A simple command to run this is:
./run.sh --size medium

This will create a RonDB cluster with the above characteristics using Docker images from DockerHub.
It uses the Docker images hopsworks/rondb-standalone. You can naturally create your own environment
either based on this work or write something new from scratch using Docker commands.

The rest of this README file describes the base script build_run_docker.sh that is more flexible,
however using this one need to ensure that the development machine has sufficient memory to house
the desired configuration. See resources/config_templates for configuration templates used by
run.sh.

Important:
- Every container requires an amount of memory; to adjust the amount of resources that Docker allocates to each of the different containers, see the [docker.env](docker.env) file. To check the amount actually allocated for the respective containers, run `docker stats` after having started a docker-compose instance. To adjust the allowed memory limits for Docker containers, do as described [here](https://stackoverflow.com/a/44533437/9068781). It should add up to the reserved aggregate amount of memory required by all Docker containers. As a reference, allocating around 27GB of memory in the Docker settings can support 1 mgmd, 2 mysqlds and 9 data nodes (3 node groups x 3 replicas).
- The same can apply to disk space - Docker also defines a maximum storage that all containers & the cache can use in the settings. There is however also a chance that a previous RonDB cluster run (or entirely different Docker containers) are still occupying disk space. In this case, you can run `docker container prune`, `docker system prune`, `docker builder prune` and `docker volume prune` to clean up disk storage. Use this with care if you have important data stored (especially in volumes).
- To build the Docker image oneself, a tarball of the RonDB installation is required. Pre-built binaries can be found on [repo.hops.works](https://repo.hops.works/master). Make sure the target platform of the Docker image and the used tarball are identical.

Commands to run:
```bash
# Run docker-compose cluster with image from Dockerhub
./build_run_docker.sh \
  --pull-dockerhub-image \
  --rondb-version latest \
  --num-mgm-nodes 1 \
  --node-groups 1 \
  --replication-factor 2 \
  --num-mysql-nodes 1 \
  --num-api-nodes 1

# Build and run image **for local platform** in docker-compose using local RonDB tarball (download it first!)
# Beware that the local platform is linux/arm64 in this case
./build_run_docker.sh \
  --rondb-tarball-is-local \
  --rondb-tarball-uri ./rondb-21.04.10-linux-glibc2.35-arm64_v8.tar.gz \
  --rondb-version 21.04.10 \
  --num-mgm-nodes 1 \
  --node-groups 1 \
  --replication-factor 2 \
  --num-mysql-nodes 1 \
  --num-api-nodes 1

# Build cross-platform image (linux/arm64 here)
docker buildx build . --platform=linux/arm64 -t rondb-standalone:21.04.10 \
  --build-arg RONDB_VERSION=21.04.10 \
  --build-arg RONDB_TARBALL_LOCAL_REMOTE=remote \  # alternatively "local"
  --build-arg RONDB_TARBALL_URI=https://repo.hops.works/master/rondb-21.04.10-linux-glibc2.35-arm64_v8.tar.gz # alternatively a local file path

# Explore image
docker run --rm -it --entrypoint=/bin/bash rondb-standalone:21.04.10
```

Exemplatory commands to run with running docker-compose cluster:
```bash
# Check current ongoing memory consumption of running cluster
docker stats

# Open shell inside a running container
docker exec -it <container-id> /bin/bash

# If inside mgmd container; check the live cluster configuration:
ndb_mgm -e show

# If inside mysqld container; open mysql client:
mysql -uroot
```

## Making configuration changes

For each run of `./build_run_docker.sh`, we generate a fresh
- docker-compose file
- MySQL-server configuration file (my.cnf)
- RonDB configuration file (config.ini)
- (Multiple) benchmarking configuration files for Sysbench & DBT2

When attempting to change any of the configurations inside my.cnf or config.ini, ***do not*** change these in the autogenerated files. They will simply be overwritten with every run. Change them in [resources/config_templates](resources/config_templates).

The directory [sample_files](sample_files) includes examples of autogenerated files. These can be updated by using the command:

```bash
./build_run_docker.sh <other args> --save-sample-files
```

## Running Benchmarks

***Warning***: Not all RonDB tarballs for *ARM64* on repo.hops.works contain the benchmarking binaries/scripts. This will however change in the near future. It is on the other hand also possible to build the RonDB tarball from source, including the benchmarking files. Or one simply uses the image from Dockerhub.

The Docker images come with a set of benchmarks pre-installed. To run any of these benchmarks with the default configurations, run:

```bash
# The benchmarks are run on the API containers and make queries towards the mysqld containers; this means that both types are needed.
./build_run_docker.sh \
  -pd -v latest -m 1 -g 1 -r 2 -my 1 -a 1 \
  --run-benchmark <sysbench_single, sysbench_multi, dbt2_single, dbt2_multi>
```

To run benchmarks with custom settings, omit the `--run-benchmark` flag and open a shell in a running API container of a running cluster. See the [RonDB documentation](http://docs.rondb.com) on running benchmarks to change the benchmark configuration files. The directory structure is equivalent to the directory structure found on Hopsworks clusters.

If you use the `-lv` flag, the results of the benchmarks are mounted into the local filesystem into the `autogenerated_files/volumes/` directory. Look for "final_result.txt" in the directory of the benchmark that was run to see the results. For more information on how to read the benchmarking output, refer to the [RonDB documentation](http://docs.rondb.com) once again.

It may be the case that the benchmarks require more resources than are configured. Here are a couple of quick fixes for this:
- Increase the DataMemory in the data nodes by increasing `TotalMemoryConfig` in the config.ini. This also requires the memory limits for ndbds to be increased in the [docker.env](docker.env) file.
- Increase the `NoOfFragmentLogFiles` when the amount of testing data is high; also increase the memory limits for apis in the [docker.env](docker.env) file to be able to load the data.
- Decrease the amount of testing data:
  - For Sysbench, decrease `SYSBENCH_ROWS` in autobench.conf
  - For DBT2, decrease the number of warehouses in autobench.conf and the dbt2_run_1.conf. One warehouse requires around 100MB of DataMemory in the data nodes.
- Run with a minimal setup:
  - mgmds = 1
  - replication factor = 1
  - node groups = 1
  - mysqlds = 1 (or 2 for multi-benchmarks)
  - apis = 1
- Lastly, one can always be unlucky and run into a timing issue at cluster startup; simply retrying this can sometimes help

***Note***: Benchmarking RonDB with a docker-compose setup on a single machine may not bring optimal performance results. This is because both the mysqlds and the ndbmtds (multi-threaded data nodes) scale in performance with more CPUs. In a production setting, each of these programs would be deployed on their own VM, whereby mysqlds and ndbmtds will scale linearly with up to 32 cores. The possibility of benchmarking was added here to give the user an introduction of benchmarking RonDB without needing to spin up a cluster with VMs.

To execute a benchmark on a bigger machine to get better numbers one needs to increase the settings
in docker.env and resources/config_templates/config.ini.

## Goals of this repository

1. Create an image with RonDB installed "hopsworks/rondb-standalone:21.04.10"
   - Purpose: basic local testing & building stone for other images
   - No building of RonDB itself
   - Supporting multiple CPU architectures
   - No ndb-agent; no reconfiguration / online software upgrades / backups, etc.
   - Push image to hopsworks/mronstro registry
   - Has all directories setup for RonDB; setup like in Hopsworks
   - Is the base-image from which other binaries can be copied into
   - Useable for quick-start of RonDB
   - Need:
     - all RonDB scripts
     - dynamic setup of config.ini/my.cnf
     - dynamic setup of docker-compose file
     - standalone entrypoints

2. Create an image with ndb-agent installed "hopsworks/rondb-managed:21.04.10-1.0"
   - use "rondb-standalone" as base image
   - use this for demos of how upgrades/scaling/backups of RonDB can be used in the cloud
   - use this for testing managed RonDB to avoid the necessity of a Hopsworks cluster
   - install other required software there such as systemctl

3. Reference in ePipe as base image
    - create builder image to build ePipe itself
    - copy over ePipe binary into hopsworks/rondb
