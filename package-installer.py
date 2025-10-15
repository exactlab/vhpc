#!/usr/bin/env python3
"""Package installer for VHPC containers."""

import os
import subprocess
import sys
from pathlib import Path
import argparse

import yaml


PACKAGES_FILE = "/packages.yml"
LOG_PREFIX = "[PACKAGE-INSTALLER]"
INSTALL_TIMEOUT = 300


def log(message):
    """Print log message with consistent prefix."""
    print(f"{LOG_PREFIX} {message}")


def run_command(command, timeout=INSTALL_TIMEOUT):
    """Run shell command with timeout and error handling."""
    try:
        result = subprocess.run(
            command, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        log(f"ERROR: Command timed out after {timeout}s: {command}")
        return False, "", "Timeout"


def install_dnf_packages(packages):
    """Install dnf packages."""
    if not packages:
        log("No dnf packages specified")
        return True

    packages = sorted(packages)
    packages_str = " ".join(packages)

    extra_dnf_packages_lock = Path("/extra_python_packages.lock")
    if extra_dnf_packages_lock.exists():
        old_packages_str = extra_dnf_packages_lock.read_text()
        if old_packages_str == packages_str:
            log("Extra dnf packages already installed.")
            return True
        else:
            log("Removing stale extra dnf packages.")
            run_command(f"dnf remove {packages_str}")

    success, stdout, stderr = run_command(f"dnf -y install {packages_str}")
    if success:
        log("Dnf packages installed successfully")
        extra_dnf_packages_lock.write_text(packages_str)
        return True
    else:
        log("ERROR: Failed to install dnf packages")
        log(f"STDERR: {stderr}")
        return False


def install_python_packages(packages):
    """Install Python packages via pip."""
    if not packages:
        log("No Python packages specified")
        return True

    from sys import executable as sys_executable

    PIP = f"{sys_executable} -m pip"

    packages = sorted(packages)
    packages_str = " ".join(packages)

    extra_python_packages_lock = Path("/extra_python_packages.lock")
    if extra_python_packages_lock.exists():
        old_packages_str = extra_python_packages_lock.read_text()
        if old_packages_str == packages_str:
            log("Extra python packages already installed.")
            return True
        else:
            log("Removing stale extra Python packages.")
            run_command(f"{PIP} uninstall {packages_str}")

    success, stdout, stderr = run_command(f"{PIP} install {packages_str}")
    if success:
        log("Python packages installed successfully")
        extra_python_packages_lock.write_text(packages_str)
        return True
    else:
        log("ERROR: Failed to install Python packages")
        log(f"STDERR: {stderr}")
        return False


def load_packages_config():
    """Load and parse packages.yml configuration."""
    if not os.path.exists(PACKAGES_FILE):
        log("No packages.yml found, skipping package installation")
        return None, None

    if os.path.isdir(PACKAGES_FILE):
        log(
            "WARNING: packages.yml is a directory (likely created by Docker "
            "bind mount). Skipping package installation"
        )
        return None, None

    try:
        with open(PACKAGES_FILE) as f:
            config = yaml.safe_load(f)

        if config is None:
            config = {}

        dnf_packages = config.get("dnf_packages", [])
        python_packages = config.get("python_packages", [])

        if not isinstance(dnf_packages, list):
            log("ERROR: dnf_packages must be a list")
            return None, None

        if not isinstance(python_packages, list):
            log("ERROR: python_packages must be a list")
            return None, None

        return dnf_packages, python_packages

    except yaml.YAMLError as e:
        log(f"ERROR: Failed to parse packages.yml: {e}")
        return None, None
    except Exception as e:
        log(f"ERROR: Failed to read packages.yml: {e}")
        return None, None


def parse_args():
    """Argument parser"""
    parser = argparse.ArgumentParser(
        description="Package installer (pip, dnf) for VHPC containers."
    )
    parser.add_argument(
        "--no-pip",
        action="store_true",
        default=False,
        help="Skip installing pip packages",
    )
    return parser.parse_args()


def main():
    """Main package installation routine."""

    log("Starting package installation...")

    args = parse_args()

    dnf_packages, python_packages = load_packages_config()

    if dnf_packages is None and python_packages is None:
        log("Skipping package installation: no packages set to be installed")
        sys.exit(1)

    success = True

    if dnf_packages:
        if not install_dnf_packages(dnf_packages):
            success = False
    if python_packages and not args.no_pip:
        if not install_python_packages(python_packages):
            success = False

    if success:
        log("Package installation completed successfully")
    else:
        log("Package installation completed with errors")

    log("Continuing with container startup...")


if __name__ == "__main__":
    main()
