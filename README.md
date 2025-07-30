# Virtual HPC Cluster with SLURM + MPI

A Docker-based virtualization of a High Performance Computing (HPC) system
running SLURM workload manager with OpenMPI support on Rocky Linux 9. This project creates a
lean, production-ready multi-container environment with one head node and configurable worker nodes.

## Architecture

- **Head Node**: Runs slurmctld daemon, manages cluster, and provides user account synchronization
- **Worker Nodes**: Run slurmd daemon, execute submitted jobs, and sync users from head node
- **Authentication**: Munge-based authentication between nodes
- **MPI Support**: OpenMPI 4.1.1 with container-optimized transport configuration
- **Shared Storage**: Persistent volumes for job data and user account synchronization
- **Networking**: Bridge network for inter-container communication

## Key Features

- **Lean Architecture**: Uses packaged SLURM binaries instead of source compilation (87% size reduction)
- **MPI Ready**: Full OpenMPI support with intra-node and inter-node job execution
- **User Management**: Automatic user synchronization from head node to workers
- **Shared Storage**: Persistent volumes for job files and MPI binaries
- **Non-privileged Jobs**: Proper user account setup for secure job execution

## Files Structure

```
vhpc/
├── Containerfile.slurm-base      # Base image with SLURM and OpenMPI packages
├── Containerfile.slurm-headnode  # Head node with user sync capability
├── Containerfile.slurm-worker    # Worker node with user sync from head node
├── docker-compose.yml            # Multi-container orchestration with volumes
├── slurm.conf                    # SLURM cluster configuration (4 CPU per worker)
├── cgroup.conf                   # Cgroup configuration for resource management
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
docker build -f Containerfile.slurm-base -t slurm-base:latest .

# Build head node
docker build -f Containerfile.slurm-headnode -t slurm-headnode:latest .

# Build worker node
docker build -f Containerfile.slurm-worker -t slurm-worker:latest .
```

## Usage
```bash
docker compose up -d
```

### Accessing the Cluster
- **Head Node SSH**: `ssh root@localhost -p 2222` (password: `rootpass`)
- **Worker1 SSH**: `ssh root@localhost -p 2223` (password: `rootpass`)
- **Worker2 SSH**: `ssh root@localhost -p 2224` (password: `rootpass`)
- **Non-privileged User**: `user` (password: `password`) - recommended for job submission

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
- **Head Node**: 1 node running slurmctld
- **Worker Nodes**: 2 nodes (slurm-worker1, slurm-worker2)
- **CPU Allocation**: 4 CPUs per worker node
- **MPI Configuration**: TCP transport optimized for containers

### Adding More Workers

Uncomment and modify additional worker sections in `docker-compose.yml`, then update `slurm.conf`:
```
NodeName=slurm-worker[1-3] CPUs=4 Sockets=1 CoresPerSocket=4 ThreadsPerCore=1 State=UNKNOWN
```

### Container Optimization

The solution uses several optimizations for container environments:
- **MPI Transport**: `OMPI_MCA_btl=tcp,self` (disables problematic fabric transports)
- **User Synchronization**: Automatic `/etc/passwd` and `/etc/group` sync from head node
- **Shared Volumes**: `shared-storage` for data, `user-sync` for account information

## Volumes

- **munge-key**: Shared Munge authentication key
- **shared-storage**: Persistent storage for job files and MPI binaries
- **user-sync**: User account synchronization from head node to workers

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
- **Image Sizes**: Base ~338MB, Head/Worker ~359MB (87% reduction from source builds)

## Troubleshooting

### MPI Jobs Failing
- Ensure MPI programs are in shared storage (`/shared`)
- Use `module load mpi/openmpi-x86_64` before compilation
- Submit jobs as non-root user (`user`)

### User Synchronization Issues
- Check if `/user-sync/passwd` exists on head node
- Restart worker containers if user changes don't propagate

### Job Output Location
- Job output files are created where the job runs (usually on worker nodes)
- Use shared storage paths for consistent output location

## License

This project is for educational and testing purposes.