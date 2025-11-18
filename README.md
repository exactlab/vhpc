# Virtual HPC Cluster with SLURM + MPI + Accounting

A Docker-based virtualization of a High Performance Computing (HPC) system
running SLURM workload manager with OpenMPI support and full job accounting on
Rocky Linux 9. This project creates a lean, production-ready multi-container
environment with graceful degradation, ensuring the cluster remains operational
even if the accounting database is unavailable.

## About eXact lab

This project was open-sourced by [eXact lab S.r.l.](https://exact-lab.it), a
consultancy specializing in scientific and high-performance computing
solutions. We help organizations optimize their computational workflows,
implement scalable HPC infrastructure, and accelerate scientific research
through tailored technology solutions.

**Need HPC expertise?** [Contact us](mailto:info@exact-lab.it) for consulting
services in scientific computing, cluster optimization, and performance
engineering.

## Architecture

- **Head Node**: Runs slurmctld daemon, manages cluster, provides user
  synchronization, and conditionally runs slurmdbd
- **Worker Nodes**: Run slurmd daemon, execute submitted jobs, and sync users
  from head node
- **Database Node**: MariaDB 10.9 for SLURM job accounting (slurmdbd backend)
- **Authentication**: Munge-based authentication between all nodes
- **MPI Support**: OpenMPI 4.1.1 with container-optimized transport
  configuration
- **Shared Storage**: Persistent volumes for job data, user sync, and SLURM
  configuration
- **Graceful Degradation**: Cluster operates normally even if database is
  unavailable
- **Networking**: Bridge network for inter-container communication

## Key Features

- **Full Job Accounting**: Complete `sacct` functionality with MariaDB backend
- **Lean Architecture**: Uses packaged SLURM binaries instead of source
  compilation (87% size reduction)
- **MPI Ready**: Full OpenMPI support with intra-node and inter-node job
  execution
- **Infrastructure Resilience**: Graceful degradation when database is
  unavailable
- **User Management**: Automatic user synchronization from head node to workers
- **Shared Configuration**: All SLURM configs shared via mounted volume
- **Non-privileged Jobs**: Proper user account setup for secure job execution

## Usage

### SLURM Configuration

**Default Configuration**: The cluster comes with a pre-configured SLURM setup
that works out of the box. The default configuration is baked into the Docker
images, so you can start the cluster immediately without any additional setup.

**Custom Configuration (Optional)**: To override the default SLURM configuration:

1. Uncomment the volume mount in `docker-compose.yml`:

   ```yaml
   # - ./slurm-config:/var/slurm_config:ro # Host-provided config override (mounted to staging area)
   ```

2. Modify the configuration files in `./slurm-config/` as needed
3. Restart the cluster: `docker-compose down && docker-compose up -d`

**How it works**: The system uses a double mount strategy:

- Default config is baked into images at `/var/slurm_config/`
- Optional host override mounts to `/var/slurm_config/` (staging area)
- Headnode entrypoint copies config from staging to `/etc/slurm/`
- `/etc/slurm/` is shared via volume across all cluster nodes

### (Optional) Install Extra Packages on the Virtual Cluster

Provide a file `packages.yml` with extra packages to be installed by `pip`
and/or `dnf`, with a bind mount to both headnode and worker nodes:

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

**Caching**: RPM packages are cached in a shared volume (`rpm-cache`) to avoid
re-downloading the same packages when starting multiple containers or
restarting them. The first container downloads and caches packages; subsequent
containers reuse the cached files.

**Concurrency Control**: To prevent DNF lock contention when multiple
containers share the same cache, a file-based locking mechanism coordinates
package installation operations. The lock file (`/var/cache/dnf/.container_lock`)
ensures only one container can run DNF operations at a time. The system includes
stale lock detection and automatic cleanup for containers that exit unexpectedly.

**Note**: The entrypoint only adds packages, never removes them. If you need to
remove packages or make deeper changes, enter the container manually with
`docker exec` and use `dnf remove` or `pip uninstall` as needed.

Be mindful that:

- installing large packages can increase the startup time of your containers.
- if a package fails to install, the error will be logged, but it will not
  prevent the container from starting.
- if an extra command fails, it will cause the container startup to fail.
- packages and extra commands are executed at container startup, **before**
  core services (like SLURM) are initialized.

### Pull up the virtual cluster

At this point you can simply

```bash
docker compose up -d
```

### Accessing the Cluster

**SSH Key Authentication (Recommended)**:

- **Head Node**: `ssh -i ./ssh-keys/id_ed25519 -p 2222 root@localhost`
- **Worker1**: `ssh -i ./ssh-keys/id_ed25519 -p 2223 root@localhost`
- **Worker2**: `ssh -i ./ssh-keys/id_ed25519 -p 2224 root@localhost`
- **Non-privileged User**: `ssh -i ./ssh-keys/id_ed25519 -p 2222 user@localhost`

**Warning**: Each image version generates its own SSH keys. When upgrading to a
new image version, remove the old keys with `rm -r ssh-keys/` before starting
the new infrastructure to avoid authentication failures.

**Note for SSH Agent Users**: If you have multiple keys loaded in your SSH
agent, SSH may exhaust the server's authentication attempts before trying the
specified key file. If you encounter "Too many authentication failures", use
the `-o IdentitiesOnly=yes` option to bypass agent keys:

```bash
ssh -i ./ssh-keys/id_ed25519 -o IdentitiesOnly=yes -p 2222 root@localhost
```

**Password Authentication (Fallback)**:

- **Head Node SSH**: `ssh -p 2222 root@localhost` (password: `rootpass`)
- **Worker1 SSH**: `ssh -p 2223 root@localhost` (password: `rootpass`)
- **Worker2 SSH**: `ssh -p 2224 root@localhost` (password: `rootpass`)
- **Non-privileged User**: `user` (password: `password`) - recommended for job
  submission

**⚠️ Security Note**: SSH keys are automatically generated during container
build for testing and educational purposes only. Do not use these keys in
production environments.

In the example compose file, SSH is binded to the host localhost only.

## Building the images

The images are available on the [GitHub Container Registry](https://github.com/exactlab/vhpc/pkgs/container/vhpc-base). You can also build
the images locally by running

```bash
docker compose build
```

### Example SLURM Commands

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

```bash
# Shared storage is mounted at /shared on all nodes
# Create user directory for job files
mkdir -p /shared/user
chown user:user /shared/user

# MPI programs can be placed in shared storage
# Example: /shared/user/mpi_hello.c
```

## Configuration

### Current Cluster Setup

- **Database Node**: MariaDB 10.9 with optimized settings for containers
- **Head Node**: 1 node running slurmctld and conditionally slurmdbd
- **Worker Nodes**: 2 nodes (slurm-worker1, slurm-worker2)
- **CPU Allocation**: 4 CPUs per worker node
- **MPI Configuration**: TCP transport optimized for containers
- **Accounting**: Full job accounting with automatic cluster initialization

### Adding More Workers

You can add more slurm workers to the compose, using the existing ones as a
template. Remember to also edit the `NodeName` line in
`slurm-config/slurm.conf` accordingly.

## Technical Details

### Volumes

- **munge-key**: Shared Munge authentication key across all nodes
- **shared-storage**: Persistent storage for job files and MPI binaries
- **user-sync**: User account synchronization from head node to workers
- **slurm-db-data**: MariaDB persistent storage for job accounting
- **slurm-config**: shared SLURM configuration files
  - to override the configuration, see [SLURM Configuration](#slurm-configuration)
- **venv**: shared Python virtual environment
  - to install extra packages, see [(Optional) Install Extra Packages on the
    Virtual Cluster](#optional-install-extra-packages-on-the-virtual-cluster)
- **rpm-cache**: shared DNF package cache to avoid re-downloading packages
  across containers

### MPI

- **MPI Transport**: `OMPI_MCA_btl=tcp,self` (disables problematic fabric
  transports)

### Bind Mounts

- `./slurm-config:/var/slurm_config:ro` - Optional SLURM configuration override
  (commented by default)
- `./ssh-keys:/ssh-keys` - SSH keys for inter-node communication
- `./packages.yml:/packages.yml:ro` - Optional extra packages configuration

## Security Considerations

- Default passwords are used for demonstration purposes
- SSH root login is enabled for testing
  - this can be overridden in the compose file, in each service, by mounting an
    appropriate configuration file, e.g. in
    `/etc/ssh/sshd_config.d/10.NoRootNoPassword.conf`:

  ```plaintext
  PermitRootLogin no
  PasswordAuthentication no
  ```

- Consider using SSH keys in production environments
- Munge keys are shared via Docker volumes
- User account sync happens automatically on container startup

### Software Versions

- **Base OS**: Rocky Linux 9
- **SLURM Version**: 22.05.9 (from EPEL packages)
- **OpenMPI Version**: 4.1.1 with container-optimized configuration
- **Authentication**: Munge
- **Network**: Docker bridge network (`slurm-net`)
- **Image Sizes**: Base ~425MB (includes MariaDB client), Head/Worker ~446MB
  (87% reduction from source builds)
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
- Use `module load mpi/openmpi-x86_64` before compilation
- Submit jobs as non-root user (`user`)

### User Synchronization Issues

- Check if `/user-sync/passwd` exists on head node
- Restart worker containers if user changes don't propagate

### Graceful Degradation Behavior

- **Database Available**: Full accounting enabled, `sacct` works normally
- **Database Unavailable**: Cluster runs without accounting, `sacct` shows
  "disabled" message
- **Database Recovery**: Restart headnode after database becomes available

### Job Output Location

- Job output files are created where the job runs (usually on worker nodes)
- Use shared storage paths for consistent output location

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE)
file for details.

Copyright (c) 2025 [eXact lab S.r.l.](https://exact-lab.it)
