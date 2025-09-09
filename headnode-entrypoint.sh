#!/bin/bash
set -e

echo "Creating a venv with 3.12 (additional packages will be installed in here, if any)"
/opt/venv/bin/python -m pip install pyyaml
/opt/venv/bin/python /opt/package-installer.py

echo "Initializing shared slurm configuration..."
# Copy any files in /var/slurm_config to /etc/slurm
# This is meant to provide a configuration source from the host (via a bind mount)
# while never writing/chowning files on the host
if [ -d "/var/slurm_config" ]; then
    cp -r /var/slurm_config/. /etc/slurm/
fi
# Set proper ownership for shared SLURM configs (mounted from ./slurm-config/)
# This is required because Docker volumes are owned by root by default
chown -R slurm:slurm /etc/slurm
# slurmdbd requires its config file to have restrictive permissions (600) for
# security
chmod 600 /etc/slurm/slurmdbd.conf

echo "Syncing user information..."
cp /etc/passwd /user-sync/passwd
cp /etc/group /user-sync/group
cp /etc/shadow /user-sync/shadow 2>/dev/null || true

echo "Setting up shared storage permissions..."
chown root:root /shared
chmod 777 /shared

echo "Fixing permissions..."
chown -R munge:munge /var/log/munge /var/run/munge /etc/munge
chmod 0700 /var/log/munge
chmod 0755 /var/run/munge
chmod 0700 /etc/munge
chmod 0400 /etc/munge/munge.key

echo "Starting sshd..."
/usr/sbin/sshd

echo "Starting munged..."
su -s /bin/bash munge -c "/usr/sbin/munged"

echo "Testing munge..."
munge -n | unmunge

# Dynamic accounting enablement for graceful degradation
# See slurm.conf for documentation on accounting configuration approach
echo "Attempting to start slurmdbd..."
DB_TIMEOUT=120
echo "Waiting up to ${DB_TIMEOUT}s for database connection..."
# Test database connectivity using mysql client with a simple SELECT query
# This approach is more reliable than TCP socket tests for MySQL/MariaDB
timeout $DB_TIMEOUT bash -c '
    while ! echo "SELECT 1;" | mysql -h slurm-db -u slurm -pslurmpass &>/dev/null; do
        sleep 2
    done
' 2>/dev/null
if [ $? -eq 0 ]; then
    echo "Database available, enabling accounting and starting slurmdbd..."
    # Uncomment accounting settings in slurm.conf - this enables dynamic accounting
    # These settings are commented out by default to allow graceful degradation
    sed -i 's/#AccountingStorageType=/AccountingStorageType=/' /etc/slurm/slurm.conf
    sed -i 's/#AccountingStorageHost=/AccountingStorageHost=/' /etc/slurm/slurm.conf
    sed -i 's/#AccountingStoragePort=/AccountingStoragePort=/' /etc/slurm/slurm.conf
    sed -i 's/#JobAcctGatherType=/JobAcctGatherType=/' /etc/slurm/slurm.conf

    # Start slurmdbd in daemon mode (background process)
    slurmdbd -D &
    sleep 10  # Wait for slurmdbd to fully initialize
    # Add cluster to accounting database (idempotent operation)
    # The -i flag makes it non-interactive, || true prevents script exit on
    # duplicate
    sacctmgr -i add cluster example-cluster 2>/dev/null || true
    echo "Starting slurmctld with accounting enabled..."
    exec slurmctld -D
else
    echo "Database unavailable, running without accounting (sacct will not work)"
    echo "Starting slurmctld without accounting (as documented in slurm.conf)..."
    exec slurmctld -D
fi
