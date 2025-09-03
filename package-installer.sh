#!/bin/bash
set -e

PACKAGES_FILE="/packages.yml"
LOG_PREFIX="[PACKAGE-INSTALLER]"

echo "$LOG_PREFIX Starting package installation..."

# Check if packages.yml exists
if [ ! -f "$PACKAGES_FILE" ]; then
    echo "$LOG_PREFIX No packages.yml found, skipping package installation"
    exit 0
fi

echo "$LOG_PREFIX Found packages.yml, processing..."

# Check if yq is available for YAML parsing
if ! command -v yq &> /dev/null; then
    echo "$LOG_PREFIX ERROR: yq not found, cannot parse YAML"
    exit 1
fi

install_dnf_packages() {
    local packages=$(yq eval '.dnf_packages[]?' "$PACKAGES_FILE" 2>/dev/null | tr '\n' ' ')
    
    if [ -n "$packages" ] && [ "$packages" != " " ]; then
        echo "$LOG_PREFIX Installing DNF packages: $packages"
       
        # Install packages with timeout and error handling
        timeout 300 dnf install -y $packages || {
            echo "$LOG_PREFIX ERROR: Failed to install DNF packages"
            rm -f "$lock_file"
            return 1
        }
        
        echo "$LOG_PREFIX DNF packages installed successfully"
    else
        echo "$LOG_PREFIX No DNF packages specified"
    fi
}

install_python_packages() {
    local packages=$(yq eval '.python_packages[]?' "$PACKAGES_FILE" 2>/dev/null | tr '\n' ' ')
    
    if [ -n "$packages" ] && [ "$packages" != " " ]; then
        echo "$LOG_PREFIX Installing Python packages: $packages"
        # Install packages with timeout and error handling
        timeout 300 pip3 install $packages || {
            echo "$LOG_PREFIX ERROR: Failed to install Python packages"
            return 1
        }
        
        echo "$LOG_PREFIX Python packages installed successfully"
    else
        echo "$LOG_PREFIX No Python packages specified"
    fi
}

# Main execution
main() {
    # Install DNF packages first
    install_dnf_packages
    
    # Install Python packages
    install_python_packages
    
    echo "$LOG_PREFIX Package installation completed"
}

main "$@"
