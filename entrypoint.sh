#!/bin/bash
set -e

# Shared utility functions
acquire_dnf_lock() {
    local lockfile="/var/cache/dnf/.container_lock"
    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=2

    echo "[LOCK] Attempting to acquire DNF lock..."
    while [ $elapsed -lt $timeout ]; do
        if (set -C; echo $$ > "$lockfile") 2>/dev/null; then
            echo "[LOCK] DNF lock acquired by PID $$"
            return 0
        fi

        if [ -f "$lockfile" ]; then
            local lock_pid=$(cat "$lockfile" 2>/dev/null || echo "")
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                echo "[LOCK] Stale lock detected, removing..."
                rm -f "$lockfile" 2>/dev/null || true
                continue
            fi
        fi

        echo "[LOCK] Waiting for DNF lock (${elapsed}s/${timeout}s)..."
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo "[LOCK] Failed to acquire DNF lock after ${timeout}s"
    return 1
}

release_dnf_lock() {
    local lockfile="/var/cache/dnf/.container_lock"
    if [ -f "$lockfile" ]; then
        local lock_pid=$(cat "$lockfile" 2>/dev/null || echo "")
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$lockfile"
            echo "[LOCK] DNF lock released by PID $$"
        fi
    fi
}

parse_packages() {
    local packages_file="$1"
    local package_type="$2"

    if [[ "$package_type" != "rpm_packages" && "$package_type" != "python_packages" && "$package_type" != "extra_commands" ]]; then
        echo "Error: package_type must be 'rpm_packages', 'python_packages', or 'extra_commands'" >&2
        return 1
    fi

    local parse_script="
import yaml
res = yaml.safe_load(open('$packages_file'))
if res:
    items = res.get('$package_type', [])
    if '$package_type' == 'extra_commands':
        print('\n'.join(items))
    else:
        print(' '.join(items))
"
    /opt/venv/bin/python -c "$parse_script"
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
            if acquire_dnf_lock; then
                trap 'release_dnf_lock' EXIT ERR
                dnf install -y --setopt=keepcache=1 $rpm_packages
                release_dnf_lock
                trap - EXIT ERR
            else
                echo "[PACKAGE-INSTALLER] Failed to acquire lock for DNF operations"
                exit 1
            fi
        fi

        if [[ " $package_types " == *" py "* ]] && [ -n "$python_packages" ]; then
            echo "[PACKAGE-INSTALLER] Installing python packages: $python_packages"
            /opt/venv/bin/pip install $python_packages
        fi

        echo "[PACKAGE-INSTALLER] Package installation completed"
    else
        echo "[PACKAGE-INSTALLER] No packages.yml found, skipping package installation"
    fi
}

execute_extra_commands() {
    if [ -f "/packages.yml" ]; then
        extra_commands=$(parse_packages "/packages.yml" "extra_commands")
        ORIG_IFS="$IFS"
        IFS=$'\n'
        for command in $extra_commands; do
            echo "[EXTRA-COMMANDS] Executing: $command"
            eval $command
        done
        IFS="$ORIG_IFS"
    fi
}

setup_ssh() {
    echo "Starting sshd..."
    /usr/sbin/sshd
}

# Load a public key from stdin to authorized_keys for both root and user.
# Keys must be provided via stdin because the container cannot access host
# paths directly.
load_ssh_pubkey() {
    if [ -t 0 ]; then
        echo "Error: No public key provided on stdin" >&2
        echo "Usage: docker compose exec -T slurm-headnode load-ssh-pubkey < ~/.ssh/id_ed25519.pub" >&2
        exit 1
    fi

    PUBKEY=$(cat)

    if [ -z "$PUBKEY" ]; then
        echo "Error: Empty public key provided" >&2
        exit 1
    fi

    echo "Adding public key to root authorized_keys..."
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "$PUBKEY" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    echo "Adding public key to user authorized_keys..."
    mkdir -p /home/user/.ssh
    chmod 700 /home/user/.ssh
    echo "$PUBKEY" >> /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/authorized_keys
    chown -R user:user /home/user/.ssh

    echo "Public key successfully added to both root and user accounts"
}

# Output the pre-generated private key to stdout for backwards compatibility.
# Usage: docker compose exec slurm-headnode get-ssh-privkey > id_ed25519
get_ssh_privkey() {
    cat /opt/ssh-keys/id_ed25519
}

setup_munge_permissions() {
    echo "Fixing permissions..."
    chown -R munge:munge /var/log/munge /var/run/munge /etc/munge
    chmod 0700 /var/log/munge
    chmod 0755 /var/run/munge
    chmod 0700 /etc/munge
    chmod 0400 /etc/munge/munge.key
}

start_munge() {
    echo "Starting munged..."
    su -s /bin/bash munge -c "/usr/sbin/munged"

    echo "Testing munge..."
    munge -n | unmunge
}

# Headnode-specific functions
headnode_startup() {
    echo "=== HEADNODE STARTUP ==="

    install_packages rpm py
    execute_extra_commands

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

    setup_munge_permissions
    start_munge

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
    execute_extra_commands

    echo "Synchronizing users from headnode..."
    if [ -f /user-sync/passwd ]; then
        cp /user-sync/passwd /etc/passwd
        cp /user-sync/group /etc/group
        [ -f /user-sync/shadow ] && cp /user-sync/shadow /etc/shadow
    fi

    setup_ssh
    start_munge

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
    load_ssh_pubkey)
        load_ssh_pubkey
        ;;
    get_ssh_privkey)
        get_ssh_privkey
        ;;
    *)
        echo "Usage: $0 [headnode|worker|load_ssh_pubkey|get_ssh_privkey]"
        exit 1
        ;;
esac
