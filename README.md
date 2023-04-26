# RonDB with Docker

This repository creates the possibility of:

- running local RonDB clusters with docker-compose
- benchmarking RonDB with Sysbench and DBT2 on localhost
- demoing the usage of [managed RonDB](/managed_rondb)
- building multi-platform RonDB images
- developing applications towards RonDB

To learn more about RonDB, have a look at [rondb.com](https://rondb.com).

## Quickstart

Dependencies:
- Docker, docker-compose
- Docker Buildx (if you use DockerHub this dependency isn't there)

You can create a RonDB cluster in Docker Compose with two commands:

```bash
cd <path-to-repo>
./run.sh
```

This will create a default RonDB cluster using the Docker image [hopsworks/rondb-standalone](https://hub.docker.com/repository/docker/hopsworks/rondb-standalone/general).

To run the optimal cluster for your machine, `run.sh` can be run with 5 different user profiles:

- **mini**: 
  - Cluster setup: 1 MGM server, 1 data node, 1 MySQL server and 1 API node
  - Docker resource utilisation: 2.5 GB of memory and up to 4 CPUs
  - Recommended machine: 8 GB of memory

- **small** (default):
  - Cluster setup: 1 MGM server, 2 data nodes, 2 MySQL servers and 1 API node
  - Docker resource utilisation: 6 GB of memory and up to 16 CPUs
  - Recommended machine: 16 GB of memory and 16 CPUs

- **medium**:
  - Cluster setup: Same as **small**
  - Docker resource utilisation: 16 GB of memory and up to 16 CPUs
  - Recommended machine: 32 GB of memory and 16 CPUs

- **large**:
  - Cluster setup: Same as **small**
  - Docker resource utilisation: 20 GB of memory and up to 32 CPUs
  - Recommended machine: 32 GB of memory and 32 CPUs

- **xlarge**:
  - Cluster setup: Same as **small**
  - Docker resource utilisation: 30 GB of memory and up to 50 CPUs
  - Recommended machine: 64 GB of memory and 64 CPUs

Keep in mind, that you must also allow your Docker engine to use the resources that are required. To change these restrictions in Docker Desktop, do as described [here](https://stackoverflow.com/a/44533437/9068781).

To apply a user profile, run for example:

```bash
./run.sh --size medium
```

The user profiles will both affect the memory allotted to the single Docker containers and the memory that RonDB will allocate to use for storage. Check the [environment files](/environments/machine_sizes) to see all configurations the user profiles affect.

These user profiles have been tested on various machines such as:
* Docker Desktop on Mac OS X using ARM CPUs
* Docker Desktop on Windows with WSL 2 using AMD/Intel CPUs
* Linux servers, laptops, desktops and workstations

## Creating custom cluster sizes

To decide yourself on how many nodes your RonDB cluster should contain, you can use the script `./build_run_docker.sh`.

Important:
- Every container requires an amount of memory; to adjust the amount of resources that Docker allocates to each of the different containers, see the Docker section in the [environment files](/environments/machine_sizes). To check the amount actually allocated for the respective containers, run `docker stats` after having started a docker-compose instance. To adjust the allowed memory limits for Docker containers, do as described [here](https://stackoverflow.com/a/44533437/9068781). It should add up to the reserved aggregate amount of memory required by all Docker containers. As a reference, allocating around 27GB of memory in the Docker settings can support 1 mgmd, 2 mysqlds and 9 data nodes (3 node groups x 3 replicas) using [small.env](/environments/machine_sizes/small.env).
- The same can apply to disk space - Docker also defines a maximum storage that all containers & the cache can use in the settings. There is however also a chance that a previous RonDB cluster run (or entirely different Docker containers) is still occupying disk space. In this case, you can run `docker container prune`, `docker system prune`, `docker builder prune` and `docker volume prune` to clean up disk storage. Use this with care if you have important data stored (especially in volumes).
- To build the Docker image oneself, a tarball of the RonDB installation is required. Pre-built binaries can be found on [repo.hops.works](https://repo.hops.works/master). Make sure the target platform of the Docker image and the used tarball are identical.

Commands to run:
```bash
# Run docker-compose cluster with image from DockerHub
./build_run_docker.sh \
  --rondb-version latest \
  --num-mgm-nodes 1 \
  --node-groups 1 \
  --replication-factor 2 \
  --num-mysql-nodes 1 \
  --num-rest-api-nodes 1 \
  --num-benchmarking-nodes 1

# Build and run image **for local platform** in docker-compose using local RonDB tarball (download it first!)
# Beware that the local platform is linux/arm64 in this case
./build_run_docker.sh \
  --rondb-tarball-path ./rondb-21.04.12-linux-glibc2.35-arm64_v8.tar.gz \
  --rondb-version 21.04.12 \
  --num-mgm-nodes 1 \
  --node-groups 1 \
  --replication-factor 2 \
  --num-mysql-nodes 1 \
  --num-rest-api-nodes 1 \
  --num-benchmarking-nodes 1

# Build cross-platform image (linux/arm64 here)
docker buildx build . --platform=linux/arm64 -t rondb-standalone:21.04.12 \
  --build-arg RONDB_VERSION=21.04.12 \
  --build-arg RONDB_TARBALL_LOCAL_REMOTE=remote \  # alternatively "local"
  --build-arg RONDB_TARBALL_URI=https://repo.hops.works/master/rondb-21.04.12-linux-glibc2.35-arm64_v8.tar.gz # alternatively a local file path

# Explore image
docker run --rm -it --entrypoint=/bin/bash rondb-standalone:21.04.12
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

When attempting to change any of the configurations inside my.cnf or config.ini, ***do not*** change these in the autogenerated files. They will simply be overwritten with every run. Either change them in [resources/config_templates](resources/config_templates) or if they are dynamically set, you can change them in the [environment files](/environments/machine_sizes). It is however not recommended to change the latter (instead set a user profile via `--size`).

The directory [sample_files](sample_files) includes examples of autogenerated files. These can be updated by using the command:

```bash
./build_run_docker.sh <other args> --save-sample-files
```

## Running Benchmarks

***Warning***: For benchmarking, we recommend using the images on DockerHub, since not all tarballs for *ARM64* on repo.hops.works contain the benchmarking binaries/scripts.

The Docker images come with a set of benchmarks pre-installed. To run any of these benchmarks with the default configurations, run:

```bash
./run.sh --run-benchmark <sysbench_single, sysbench_multi, dbt2_single>

# Running with a custom size; The benchmarks are run on the API containers and make queries towards the mysqld containers; this means that both types are needed.
./build_run_docker.sh \
  -v latest -m 1 -g 1 -r 2 -my 2 -bn 1 \
  --run-benchmark <sysbench_single, sysbench_multi, dbt2_single>
```

To run benchmarks with custom settings, omit the `--run-benchmark` flag and open a shell in a running API container of a running cluster. See the [RonDB documentation](http://docs.rondb.com) on running benchmarks to change the benchmark configuration files. The directory structure is equivalent to the directory structure found on Hopsworks clusters.

If you use the `-lv` flag, the results of the benchmarks are mounted into the local filesystem into the `autogenerated_files/volumes/` directory. Look for "final_result.txt" in the directory of the benchmark that was run to see the results. For more information on how to read the benchmarking output, refer to the [RonDB documentation](http://docs.rondb.com) once again.

***Note***: Benchmarking RonDB with a docker-compose setup on a single machine may not bring optimal performance results. This is because both the mysqlds and the ndbmtds (multi-threaded data nodes) scale in performance with more CPUs. In a production setting, each of these programs would be deployed on their own VM, whereby mysqlds and ndbmtds will scale linearly with up to 32 cores. The possibility of benchmarking was added here to give the user an introduction of benchmarking RonDB without needing to spin up a cluster with VMs. Using larger machines and increasing the `--size` flag in `run.sh`, will however improve benchmark results significantly.

## Preliminary Notes for YCSB benchmarking

Setup:
* Change [resources/entrypoints/init_scripts/setup_ycsb.sql](resources/entrypoints/init_scripts/setup_ycsb.sql) to create different tables

Reasons for failure:
* When running `ycsb load`, all data is first loaded into memory of the benchmarking container. Check the available memory for benchmarking containers in [docker.env](docker.env) and compare it to `fieldcount * fieldlength * recordcount` in the YCSB workload file. The same amount of memory needs to be supported by the ndbmtd container.

## ***New***: Managed RonDB

Apart from using/building the Docker image `rondb-standalone`, RonDB can also be run as a managed database, using the Docker image `hopsworks/rondb-managed`. This means that the cluster becomes dynamic - one can add nodes, perform rolling software upgrades, do backups and even restore from backups. See the directory [managed_rondb](managed_rondb) for more.
