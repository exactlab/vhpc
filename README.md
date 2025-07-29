# Virtual HPC Cluster with SLURM

A Docker-based virtualization of a High Performance Computing (HPC) system
running SLURM workload manager on Rocky Linux 9. This project creates a
multi-container environment with one head node and configurable worker nodes.

## Architecture

- **Head Node**: Runs slurmctld daemon and provides cluster management
- **Worker Nodes**: Run slurmd daemon and execute submitted jobs
- **Authentication**: Munge-based authentication between nodes
- **Networking**: Bridge network for inter-container communication

## Files Structure

```
vhpc/
├── Containerfile.slurm-base      # Base image with SLURM build
├── Containerfile.slurm-headnode  # Head node configuration
├── Containerfile.slurm-worker    # Worker node configuration
├── docker-compose.yml            # Multi-container orchestration
├── slurm.conf                    # SLURM cluster configuration
└── makefile                      # Build automation
```

## Current Issues

### Minor Issues

4. **Makefile Syntax**:
   - Incorrect shebang at top of makefile
   - Missing `.PHONY` declarations
   - File: `makefile:1`

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

**Note**: The cluster currently does not work due to the issues listed above.

Once issues are resolved:
```bash
docker-compose up -d
```

### Accessing the Cluster
- **Head Node SSH**: `ssh root@localhost -p 2222` (password: `rootpass`)
- **Worker1 SSH**: `ssh root@localhost -p 2223` (password: `rootpass`)

### SLURM Commands
After fixing the issues, you can:
```bash
# Check cluster status
sinfo

# Submit a test job
srun hostname

# View job queue
squeue
```

## Configuration

### Adding More Workers

Uncomment and modify the `slurm-worker2` section in `docker-compose.yml`:
```yaml
slurm-worker2:
  image: slurm-worker:latest
  container_name: slurm-worker2
  hostname: slurm-worker2
  # ... rest of configuration
```

Update `slurm.conf` to include new nodes:
```
NodeName=slurm-worker[1-3] CPUs=1 Sockets=1 CoresPerSocket=1 ThreadsPerCore=1 State=UNKNOWN
```

### Security Considerations

- Default passwords are used for demonstration purposes
- SSH root login is enabled for testing
- Consider using SSH keys in production environments
- Munge keys are shared via Docker volumes

## Required Fixes

To make this cluster functional, the following fixes are needed:

1. Fix SLURM configuration path consistency across all containers
2. Enable slurmd daemon startup in worker nodes
3. Correct CPU allocation in slurm.conf to match container resources
4. Fix makefile syntax issues

## Technical Details

- **Base OS**: Rocky Linux 9
- **SLURM Version**: 23.11.6
- **Authentication**: Munge
- **Network**: Docker bridge network (`slurm-net`)
- **Privileged Mode**: Required for cgroup access

## License

This project is for educational and testing purposes.
