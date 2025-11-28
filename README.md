# vHPC: a Virtual HPC Cluster with Slurm and MPI

A Docker-based virtualization of a High Performance Computing (HPC) system
running Slurm workload manager with OpenMPI support and optional full job
accounting on Rocky Linux 9. This project creates a lean, production-ready
multi-container environment.

## About eXact lab

This project is open-sourced by [eXact lab S.r.l.](https://exact-lab.it), a
consultancy specializing in scientific and high-performance computing
solutions. We help organizations optimize their computational workflows,
implement scalable HPC infrastructure, and accelerate scientific research
through tailored technology solutions.

**Need HPC expertise?** [Contact us](mailto:info@exact-lab.it) for consulting
services in scientific computing, cluster optimization, and performance
engineering.

## Index

- [Key Features](#key-features)
- [Usage](#usage)
  - [Quick start](#quick-start)
  - [Accessing the Cluster](#accessing-the-cluster)
  - [Example Slurm Commands](#example-slurm-commands)
  - [Working with Shared Storage](#working-with-shared-storage)
- [Configuration](#configuration)
  - [(Optional) Install Extra Packages](#optional-install-extra-packages-on-the-virtual-cluster)
  - [(Optional) Custom Slurm Configuration](#optional-custom-slurm-configuration)
  - [Adding More Workers](#adding-more-workers)
- [Building the images](#building-the-images)
- [Technical Details](#technical-details)
  - [Architecture](#architecture)
  - [Volumes](#volumes)
  - [MPI](#mpi)
- [Security Considerations](#security-considerations)
  - [Software Versions](#software-versions)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Key Features

- **MPI Ready**: Full OpenMPI support with intra-node and inter-node job
  execution
- **User Management**: User synchronization from head node to workers via
  mounted home volume
- **Shared Configuration**: All Slurm configs shared via mounted volume
- **Full Job Accounting (Optional)**: Complete `sacct` functionality with
  MariaDB backend. You can opt not to start the database container and the
  system will still work, just without accounting
- **Runtime customisation**: Install additional software onto the cluster at
  container startup without the need to rebuild the image, see [Install Extra
  Packages](#optional-install-extra-packages-on-the-virtual-cluster) below

## Usage

### Quick start

Simply

```bash
docker compose up -d
```

The virtual cluster will start up in its default configuration:

* **One login node**
* **Two worker nodes** with 4 vCPU each and 2048M of vRAM
* **Full accounting** via a database node (MariaDB)

### Accessing the Cluster

**SSH Access to Headnode**:

SSH access is available to the headnode on port 2222. You can access it using
password authentication or by loading your own SSH key.

**Password Authentication**:

```bash
ssh -p 2222 root@localhost  # password: rootpass
ssh -p 2222 user@localhost  # password: password (recommended for job submission)
```

**Using Your Own SSH Key**:

Load your public key into the headnode:

```bash
docker compose exec -T slurm-headnode load-ssh-pubkey < ~/.ssh/id_ed25519.pub
```

Then connect:

```bash
ssh -p 2222 root@localhost
```

Note: Keys must be provided via stdin because the container cannot access host
paths directly.

**Note for SSH Agent Users**: If you have multiple keys loaded in your SSH
agent, SSH may exhaust the server's allowed authentication attempts before
trying the specified key file. If you encounter "Too many authentication
failures", use the `-o IdentitiesOnly=yes` option to bypass agent keys:

```bash
ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes -p 2222 root@localhost
```

**Using Pre-generated Keys**:

For convenience and CI environments, you can extract the pre-generated private
key embedded in the image:

```bash
docker compose exec slurm-headnode get-ssh-privkey > id_ed25519
chmod 600 id_ed25519
ssh -i id_ed25519 -p 2222 root@localhost
```

**Accessing Workers**:

Workers do not expose SSH ports by default, as this reflects typical HPC
cluster configurations where SSH access is confined to the headnode. Access
workers using:

```bash
docker exec -it slurm-worker1 bash
docker exec -it slurm-worker2 bash
```

If you need SSH access to workers for specific use cases, you can uncomment the
port mappings in the workers' sections of `docker-compose.yml`.

**⚠️ Security Note**: SSH keys are automatically generated during container
build for testing and educational purposes only. Do not use these keys in
production environments.

In the example compose file, SSH is bound to the host's localhost only,
preventing remote access from different hosts.

### Example Slurm Commands

```bash
# Check cluster status
sinfo

# Submit a test job as user
su - user
srun hostname

# Submit MPI job (intra-node)
module load mpi/openmpi-x86_64
sbatch -N 1 -n 4 --wrap="mpirun -n 4 hostname"

# Submit MPI job (inter-node)
sbatch -N 2 -n 4 --wrap="mpirun -n 4 hostname"

# View job queue
squeue

# View job accounting (NEW!)
sacct                    # Show recent jobs
sacct -a                 # Show all jobs
sacct -j 1 --format=JobID,JobName,Partition,Account,AllocCPUS,State,ExitCode
```

### Working with Shared Storage

Besides the users' homes, we provide a second shared storage to emulate scratch
or work area present in several production clusters.

```bash
# Shared storage is mounted at /shared on all nodes
# Create user directory for job files
mkdir -p /shared/user
chown user:user /shared/user

# MPI programs can be placed in shared storage
# Example: /shared/user/mpi_hello.c
```

## Configuration

### (Optional) Install Extra Packages on the Virtual Cluster

You may provide a file `packages.yml` with listing extra packages to be
installed by `pip` and/or `dnf`, and additionally execute arbitrary commands
at container startup. To use this feature, you need to bind mount the
`packages.yml` file to both headnode and worker nodes:

```yaml
...
    volumes:
      ...
      # Optional: Mount packages.yml for runtime package installation
      - ./packages.yml:/packages.yml:ro
...
```

A `packages.yml.example` file is provided as a starting point.
The file is structured into three main lists:

- `rpm_packages`: for system packages (e.g., `htop`, `git`, `vim`)
- `python_packages`: for Python libraries (e.g., `pandas`, `requests`)
- `extra_commands`: for arbitrary shell commands executed as root during
  startup

Package installation and extra commands are handled directly in the shell
entrypoint script, making installation progress visible via `docker logs -f`.
Packages are persistent across container restarts and installation is
idempotent.

**Note**: The entrypoint only adds packages, never removes them. If you need to
remove packages or make deeper changes, enter the container manually with
`docker exec` and use `dnf remove` or `pip uninstall` as needed.

Be mindful that:

- installing large packages can increase the startup time of your containers;
  this is however a one-off price to pay the first time the cluster is started
- if any installation fails, it will cause the container startup to fail
- if an extra command fails, it will cause the container startup to fail
- packages and extra commands are executed at container startup, **before**
  core services (like Slurm) are initialized

**Caching**: RPM package cache is persisted and shared as a volume
(`rpm-cache`) across the cluster. This avoids re-downloading the same packages
when starting multiple containers or restarting them. The first container
downloads and caches packages; subsequent containers reuse the cached files.

**Concurrency Control**: To prevent DNF lock contention when multiple
containers share the same cache, a file-based locking mechanism coordinates
package installation operations. The lock file (`/var/cache/dnf/.container_lock`)
ensures only one container can run DNF operations at a time. The system includes
stale lock detection and automatic cleanup for containers that exit unexpectedly.

### (Optional) Custom Slurm Configuration

**Default Configuration**: The cluster comes with a pre-configured Slurm setup
that works out of the box. The default configuration is baked into the Docker
images, so you can start the cluster immediately without any additional setup.

**Custom Configuration (Optional)**: To override the default Slurm
configuration:

1. Uncomment the volume mount in `docker-compose.yml`:

   ```yaml
   # - ./slurm-config:/var/slurm_config:ro # Host-provided config override (mounted to staging area)
   ```

2. Modify the configuration files in `./slurm-config/` as needed
3. Restart the cluster: `docker-compose down && docker-compose up -d`

**How it works**: The system uses a double mount strategy:

- Default config is shipped with the images at `/var/slurm_config/`
- Optional host override mounts to `/var/slurm_config/` (staging area)
- Headnode entrypoint copies config from staging to `/etc/slurm/`
- `/etc/slurm/` is shared via volume across all cluster nodes

### Adding More Workers

You can add more slurm workers to the compose, using the existing ones as a
template. Remember to also edit the `NodeName` line in
`slurm-config/slurm.conf` accordingly.

## Building the images

The images are available on the [GitHub Container Registry](https://github.com/exactlab/vhpc/pkgs/container/vhpc-base). You can also build
the images locally by running

```bash
docker compose build
```

## Technical Details

### Architecture

With the compose file included in this project you get:

- **Head Node**: Runs slurmctld daemon, manages cluster, provides user
  synchronization, and optionally runs slurmdbd
- **Worker Nodes**: Two by default. They run slurmd daemon, execute submitted
  jobs, and sync users from head node
- **Database Node (Optional)**: MariaDB 10.9 for Slurm job accounting
- **MPI Support**: OpenMPI 4.1.1 with container-optimized transport
  configuration
- **Shared Storage**: Persistent volumes for job data, user sync and home
  directories, and Slurm configuration


### Volumes

- **munge-key**: Shared Munge authentication key across all nodes
- **shared-storage**: Persistent storage for job files and MPI binaries
- **user-sync**: User account synchronization from head node to workers
- **slurm-db-data**: MariaDB persistent storage for job accounting
- **slurm-config**: shared Slurm configuration files to override the
  configuration, see [Custom Slurm
  Configuration](#optional-custom-slurm-configuration)
- **venv**: shared Python virtual environment
  - to install extra packages, see [(Optional) Install Extra Packages on the
    Virtual Cluster](#optional-install-extra-packages-on-the-virtual-cluster)
- **rpm-cache**: shared DNF package cache to avoid re-downloading packages
  across containers

### MPI

- **MPI Transport**: `OMPI_MCA_btl=tcp,self` (disables problematic fabric
  transports)

## Security Considerations

**WARNING** This project is for educational and testing purposes. Do not use in
production!

- Default passwords are used for demonstration purposes
- SSH root login is enabled
  - this can be overridden in the compose file, in each service, by mounting an
    appropriate configuration file, e.g. in
    `/etc/ssh/sshd_config.d/10.NoRootNoPassword.conf`:

  ```plaintext
  PermitRootLogin no
  PasswordAuthentication no
  ```

### Software Versions

- **Base OS**: Rocky Linux 9
- **Slurm Version**: 22.05.9 (from EPEL packages)
- **OpenMPI Version**: 4.1.1 with container-optimized configuration
- **Database**: MariaDB 10.9 with 64MB buffer pool for container optimization

## Troubleshooting

### Job Accounting Issues

- If `sacct` shows "Slurm accounting storage is disabled": Database connection
  failed during startup
- Check database logs: `docker logs slurm-db`
- Restart headnode to retry database connection: `docker restart
  slurm-headnode0`
- Verify database connectivity: `docker exec slurm-db mysql -u slurm
  -pslurmpass -e "SELECT 1;"`

### MPI Jobs Failing

- Ensure MPI programs are in shared storage (`/shared`)
- Use `module load mpi/openmpi-x86_64` (or simply `module load mpi`) before
  compilation
- Submit jobs as non-root user (`user`)

### Job Output Location

- Job output files are created where the job runs (usually on worker nodes)
- Use shared storage or home directories for consistent output location

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE)
file for details.

Copyright (c) 2025 [eXact lab S.r.l.](https://exact-lab.it)
