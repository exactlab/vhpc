# Implementation Plan: Runtime Package Installation

## Overview

Add capability to install Rocky Linux packages and Python dependencies at
container startup through docker-compose configuration, enabling customization
without rebuilding images.

## Implementation Steps

### 1. Docker Compose Configuration
- [x] Add volume mount for packages.yml file to all services
- [x] Define packages.yml example for dnf and python packages

### 2. Package Installation Script
NOTE: installer scripts must be self contained and already copied to the image!
The user must not have to deal with them, it should only provide packages.yml

- [x] Create package-installer.sh script that reads packages.yml
- [x] Parse YAML to extract dnf and python package lists
- [x] Add error handling and logging for package installation failures
- [?] Make scripts idempotent to handle container restarts

### 3. Entrypoint Integration
- [x] Modify headnode-entrypoint.sh to call package installers before SLURM
- [x] Create worker-entrypoint.sh that calls package installers before slurmd
- [x] Ensure package installation happens before user sync and SLURM startup

### 4. Container Modifications
- [x] Update Containerfile.slurm-headnode to include package-installer.sh
- [x] Update Containerfile.slurm-worker to include package-installer.sh
- [x] Ensure dnf, pip, and yq (YAML parser) are available in base image
- [s] Test package installation with sample configurations

### 5. Configuration Format Design
- [x] Create example packages.yml with schema documentation
- [x] Document YAML structure and validation rules

### 6. Documentation
- [ ] Update README.md with configuration examples

## Configuration Examples

### packages.yml Schema
```yaml
dnf_packages:
  - htop
  - git
  - nano
  - vim
python_packages:
  - numpy
  - pandas
  - requests
```

### Volume Mount for Packages
```yaml
volumes:
  - ./packages.yml:/packages.yml:ro
```
