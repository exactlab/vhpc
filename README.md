# Virtual HPC Cluster with SLURM + MPI + Accounting

A Docker-based virtualization of a High Performance Computing (HPC) system
running SLURM workload manager with OpenMPI support and full job accounting on
Rocky Linux 9. This project creates a lean, production-ready multi-container
environment with graceful degradation, ensuring the cluster remains operational
even if the accounting database is unavailable.

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

## Files Structure

```
vhpc/
├── Containerfile.slurm-base      # Base image with SLURM, OpenMPI, and MariaDB client
├── Containerfile.slurm-headnode  # Head node with accounting and user sync
├── Containerfile.slurm-worker    # Worker node with user sync from head node
├── headnode-entrypoint.sh        # Headnode startup script with graceful degradation
├── docker-compose.yml            # Multi-container orchestration (4 services, 5 volumes)
├── slurm-config/                 # Shared SLURM configuration directory
│   ├── slurm.conf               # SLURM cluster configuration (4 CPU per worker)
│   ├── slurmdbd.conf            # SLURM database daemon configuration
│   └── cgroup.conf              # Cgroup configuration for resource management
└── makefile                      # Build automation
```

## Prerequisites

- Docker Engine
- Docker Compose
- Make (optional, for automated builds)

## Build Instructions

### Option 1: Using Make (Recommended)
```bash
make all
```

### Option 2: Manual Build
```bash
# Build base image first
docker build -f Containerfile.slurm-base -t vhpc-base:latest .

# Build head node
docker build -f Containerfile.slurm-headnode -t vhpc-headnode:latest --build-arg BASE_IMAGE=vhpc-base:latest .

# Build worker node
docker build -f Containerfile.slurm-worker -t vhpc-worker:latest --build-arg BASE_IMAGE=vhpc-base:latest .
```

## Usage

### Using Pre-built Images (Recommended)
```bash
# Pull latest images from GitHub Container Registry
docker compose pull
docker compose up -d
```

### Using Local Build
```bash
# Build images locally
make all
docker compose up -d
```

### Accessing the Cluster
- **Head Node SSH**: `ssh root@localhost -p 2222` (password: `rootpass`)
- **Worker1 SSH**: `ssh root@localhost -p 2223` (password: `rootpass`)
- **Worker2 SSH**: `ssh root@localhost -p 2224` (password: `rootpass`)
- **Non-privileged User**: `user` (password: `password`) - recommended for job
  submission

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

Uncomment and modify additional worker sections in `docker-compose.yml`, then
update `slurm.conf`:
```
NodeName=slurm-worker[1-3] CPUs=4 Sockets=1 CoresPerSocket=4 ThreadsPerCore=1 State=UNKNOWN
```

### Container Optimization

The solution uses several optimizations for container environments:
- **MPI Transport**: `OMPI_MCA_btl=tcp,self` (disables problematic fabric
  transports)
- **User Synchronization**: Automatic `/etc/passwd` and `/etc/group` sync from
  head node
- **Shared Volumes**: `shared-storage` for data, `user-sync` for account
  information

## Volumes

- **munge-key**: Shared Munge authentication key across all nodes
- **shared-storage**: Persistent storage for job files and MPI binaries
- **user-sync**: User account synchronization from head node to workers
- **slurm-db-data**: MariaDB persistent storage for job accounting
- **slurm-config**: Shared SLURM configuration files (NOTE: not used, configs
  mounted from ./slurm-config/)

## Security Considerations

- Default passwords are used for demonstration purposes
- SSH root login is enabled for testing
- Consider using SSH keys in production environments
- Munge keys are shared via Docker volumes
- User account sync happens automatically on container startup

## Technical Details

- **Base OS**: Rocky Linux 9
- **SLURM Version**: 22.05.9 (from EPEL packages)
- **OpenMPI Version**: 4.1.1 with container-optimized configuration
- **Authentication**: Munge
- **Network**: Docker bridge network (`slurm-net`)
- **Privileged Mode**: Required for cgroup access
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

### Configuration Changes
- Modify files in `./slurm-config/` directory
- Restart containers to apply changes: `docker compose restart`
- Changes are automatically shared across all nodes

### Graceful Degradation Behavior
- **Database Available**: Full accounting enabled, `sacct` works normally
- **Database Unavailable**: Cluster runs without accounting, `sacct` shows
  "disabled" message
- **Database Recovery**: Restart headnode after database becomes available

### Job Output Location
- Job output files are created where the job runs (usually on worker nodes)
- Use shared storage paths for consistent output location

## License

This project is for educational and testing purposes.
