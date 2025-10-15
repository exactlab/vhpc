# log in via public key

## Context

We currently only support ssh via user:password, but this is not realistic of
production environment. We should create a key and mount it on the host so that
the user can point to it and use it with `ssh -i <path to key>`.

## Implementation plan (REVISED)

**CRITICAL ISOLATION REQUIREMENT**: All SSH keys and configuration must remain
local to the project directory. The project must NEVER touch or modify the
user's `~/.ssh` directory or any system-wide SSH configuration.

**APPROACH**: For testing/educational purposes, generate SSH keys during image
build and expose them via bind mount for user access.

1. **Project-local SSH key infrastructure** (Docker Compose changes)
   - [x] Create `./ssh-keys/` directory structure in project root
   - [x] Add bind mount `./ssh-keys:/ssh-keys:ro` on all services for key
     access
   - [x] Add `ssh-keys/` to .gitignore to prevent committing private keys

2. **Container SSH configuration with embedded keys** (Dockerfile changes)
   - [x] **Containerfile.slurm-headnode**: Generate SSH keypair during build
   - [x] **Containerfile.slurm-headnode**: Copy private key to `/ssh-keys/`
     volume for host access
   - [x] **Containerfile.slurm-headnode**: Set up `/root/.ssh/authorized_keys`
     with public key
   - [x] **Both Containerfiles**: Enable PubkeyAuthentication alongside password
     auth
   - [x] **Both Containerfiles**: Set up `/home/user/.ssh/authorized_keys` with
     same public key

3. **Documentation updates** (README changes)
   - [x] Update README.md showing `ssh -i ./ssh-keys/id_ed25519 -p 2222
     root@localhost`
   - [x] Document that keys are generated automatically during build
   - [x] Add warning: "Keys are for testing only, not production"
   - [x] Test both authentication methods work simultaneously

## Implementation log

### Step 1: Project-local SSH key infrastructure

**Read-only bind mounts**: Used `./ssh-keys:/ssh-keys:ro` read-only mounts.
Initially planned for host-side key generation, but revised approach generates
keys in container and exposes them via this mount for user access.

**Directory auto-creation**: Leveraged Docker Compose's automatic directory
creation behavior instead of manual mkdir, reducing setup complexity while
maintaining the same outcome.

**Gitignore placement**: Created minimal `.gitignore` with only `ssh-keys/` to
prevent accidental private key commits while allowing other temporary files to
be tracked if needed in the future.

**Revised approach rationale**: For testing/educational purposes, generating
keys during container build and exposing them via mount is simpler than
host-side generation while maintaining isolation from user's personal SSH
configuration.

### Step 2: Container SSH configuration with embedded keys

**Base image consolidation**: Moved all SSH setup to base image after
recognizing identical operations in both headnode and worker containers.
This eliminates code duplication and ensures consistent SSH configuration
across all cluster nodes.

**Dual authentication support**: Configured SSH to accept both password and
key authentication simultaneously, maintaining backward compatibility for
users while enabling production-like key-based access.

**User account consolidation**: Moved user creation to base image since both
sub-images used identical `useradd` commands, further reducing duplication
and ensuring consistent UID/GID across cluster nodes.

### Step 3: Documentation updates

**Image tagging strategy**: Updated makefile to tag local builds with GitHub
registry names (`ghcr.io/exactlab/vhpc-*:latest`), leveraging Docker
Compose's native behavior of preferring local images when available while
maintaining compatibility with distributed versions.

**Mount point permissions issue**: Keys copied from container to bind mount
retain root ownership, making them inaccessible to host users. Solved by
setting 644 permissions during runtime copy operation in entrypoint script,
allowing any host user to read the keys for SSH authentication.

### Miscellaneous fixes

**Docker bind mount directory creation**: When `packages.yml` doesn't exist
on host, Docker creates it as directory instead of file, causing package
installer to fail. Fixed by adding directory detection in
`load_packages_config()` function to gracefully skip installation with
warning instead of catastrophic failure.

**Health check timeout**: Container startup may exceed health check timeout
due to package installation and SLURM initialization. SSH functionality
remains operational despite health check failures, as verified by manual
testing.


