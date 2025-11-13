#!/bin/bash
set -e

# Shared utility functions
parse_packages() {
    local packages_file="$1"
    local package_type="$2"
    
    if [[ "$package_type" != "rpm_packages" && "$package_type" != "python_packages" ]]; then
        echo "Error: package_type must be 'rpm_packages' or 'python_packages'" >&2
        return 1
    fi
    
    local parse_script="
import yaml
res = yaml.safe_load(open('$packages_file'))
if res:
    packages = res.get('$package_type', [])
    print(' '.join(packages))
"
    python -c "$parse_script"
}

install_packages() {
    local package_types="$*"
    
    /opt/venv/bin/python -m pip install pyyaml
    echo "Installing additional packages if packages.yml is provided..."
    if [ -f "/packages.yml" ]; then
        echo "[PACKAGE-INSTALLER] Parsing package lists..."
        rpm_packages=$(parse_packages "/packages.yml" "rpm_packages")
        python_packages=$(parse_packages "/packages.yml" "python_packages")
        
        if [[ " $package_types " == *" rpm "* ]] && [ -n "$rpm_packages" ]; then
            echo "[PACKAGE-INSTALLER] Installing rpm packages: $rpm_packages"
            dnf install -y $rpm_packages || echo "[PACKAGE-INSTALLER] Some rpm packages failed to install"
        fi
        
        if [[ " $package_types " == *" py "* ]] && [ -n "$python_packages" ]; then
            echo "[PACKAGE-INSTALLER] Installing python packages: $python_packages"
            /opt/venv/bin/pip install $python_packages || echo "[PACKAGE-INSTALLER] Some python packages failed to install"
        fi
        
        echo "[PACKAGE-INSTALLER] Package installation completed"
    else
        echo "[PACKAGE-INSTALLER] No packages.yml found, skipping package installation"
    fi
}

setup_ssh() {
    echo "Copying SSH keys to shared directory..."
    cp /opt/ssh-keys/* /ssh-keys/ 2>/dev/null || true
    chmod 644 /ssh-keys/id_ed25519.pub 2>/dev/null || true
    chmod 644 /ssh-keys/id_ed25519 2>/dev/null || true

    echo "Starting sshd..."
    /usr/sbin/sshd
}

setup_munge() {
    echo "Fixing permissions..."
    chown -R munge:munge /var/log/munge /var/run/munge /etc/munge
    chmod 0700 /var/log/munge
    chmod 0755 /var/run/munge
    chmod 0700 /etc/munge
    chmod 0400 /etc/munge/munge.key

    echo "Starting munged..."
    su -s /bin/bash munge -c "/usr/sbin/munged"

    echo "Testing munge..."
    munge -n | unmunge
}

# Headnode-specific functions
headnode_startup() {
    echo "=== HEADNODE STARTUP ==="
    
    install_packages rpm py

    setup_ssh

    echo "Initializing shared slurm configuration..."
    if [ -d "/var/slurm_config" ]; then
        cp -r /var/slurm_config/. /etc/slurm/
    fi
    chown -R slurm:slurm /etc/slurm
    chmod 600 /etc/slurm/slurmdbd.conf

    echo "Syncing user information..."
    cp /etc/passwd /user-sync/passwd
    cp /etc/group /user-sync/group
    cp /etc/shadow /user-sync/shadow 2>/dev/null || true

    echo "Setting up shared storage permissions..."
    chown root:root /shared
    chmod 777 /shared

    setup_munge

    echo "Attempting to start slurmdbd..."
    DB_TIMEOUT=120
    echo "Waiting up to ${DB_TIMEOUT}s for database connection..."
    timeout $DB_TIMEOUT bash -c '
        while ! echo "SELECT 1;" | mysql -h slurm-db -u slurm -pslurmpass &>/dev/null; do
            sleep 2
        done
    ' 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Database available, enabling accounting and starting slurmdbd..."
        sed -i 's/#AccountingStorageType=/AccountingStorageType=/' /etc/slurm/slurm.conf
        sed -i 's/#AccountingStorageHost=/AccountingStorageHost=/' /etc/slurm/slurm.conf
        sed -i 's/#AccountingStoragePort=/AccountingStoragePort=/' /etc/slurm/slurm.conf
        sed -i 's/#JobAcctGatherType=/JobAcctGatherType=/' /etc/slurm/slurm.conf

        slurmdbd -D &
        sleep 10
        sacctmgr -i add cluster example-cluster 2>/dev/null || true
        echo "Starting slurmctld with accounting enabled..."
        exec slurmctld -D
    else
        echo "Database unavailable, running without accounting (sacct will not work)"
        echo "Starting slurmctld without accounting (as documented in slurm.conf)..."
        exec slurmctld -D
    fi
}

# Worker-specific functions  
worker_startup() {
    echo "=== WORKER STARTUP ==="
    
    # Only install dnf packages on workers (python packages are in shared venv)
    install_packages rpm

    echo "Synchronizing users from headnode..."
    if [ -f /user-sync/passwd ]; then
        cp /user-sync/passwd /etc/passwd
        cp /user-sync/group /etc/group
        [ -f /user-sync/shadow ] && cp /user-sync/shadow /etc/shadow
    fi

    setup_ssh
    setup_munge

    echo "Starting slurmd..."
    exec slurmd -D -f ${SLURM_CONF}
}

# Main execution logic
case "${1:-headnode}" in
    headnode)
        headnode_startup
        ;;
    worker)
        worker_startup
        ;;
    *)
        echo "Usage: $0 [headnode|worker]"
        exit 1
        ;;
esac
