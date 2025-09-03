# packages.yml Schema Documentation

## Overview

The `packages.yml` file defines additional packages to install at container startup. This file is optional and mounted as a read-only volume.

## Schema Structure

```yaml
dnf_packages:          # Optional: List of Rocky Linux packages
  - string             # Package name (e.g., "htop", "git")
  
python_packages:       # Optional: List of Python packages  
  - string             # Package name (e.g., "numpy", "pandas")
```

## Validation Rules

### General Rules
- File must be valid YAML format
- Both `dnf_packages` and `python_packages` are optional
- Empty file is valid (no packages will be installed)
- Missing sections are treated as empty lists

### dnf_packages Section
- **Type**: Array of strings
- **Required**: No
- **Description**: Rocky Linux packages installed via `dnf install -y`
- **Examples**: `htop`, `git`, `vim`, `gcc-c++`
- **Validation**: Package names are not pre-validated; invalid names cause installation failure

### python_packages Section  
- **Type**: Array of strings
- **Required**: No
- **Description**: Python packages installed via `pip3 install`
- **Examples**: `numpy`, `pandas`, `requests==2.28.0`
- **Validation**: Package names are not pre-validated; invalid names cause installation failure
- **Note**: Supports pip package specifications (version constraints, URLs, etc.)

## Example Files

### Complete Example
```yaml
dnf_packages:
  - htop
  - git
  - nano
  - gcc-c++

python_packages:
  - numpy
  - pandas>=1.5.0
  - requests
  - matplotlib
```

### Minimal Example
```yaml
dnf_packages:
  - git

python_packages:
  - numpy
```

### DNF Only
```yaml
dnf_packages:
  - htop
  - vim
```

### Python Only  
```yaml
python_packages:
  - numpy
  - pandas
```

### Empty (No Additional Packages)
```yaml
# No packages - valid but unnecessary
```

## Error Handling

### Invalid YAML
- **Behavior**: Container startup fails with parsing error
- **Solution**: Validate YAML syntax before mounting

### Invalid Package Names
- **Behavior**: Installation fails, logged as error, container continues
- **Impact**: Other packages in the same section are skipped
- **Solution**: Check package availability in Rocky Linux repos or PyPI

### Network Issues
- **Behavior**: Installation times out after 5 minutes, container continues
- **Impact**: Packages not installed, SLURM cluster remains functional
- **Solution**: Check network connectivity and repository accessibility

## Best Practices

1. **Start Small**: Begin with minimal package sets, add incrementally
2. **Test Locally**: Validate package names before deployment
3. **Version Pinning**: Consider pinning Python package versions for reproducibility
4. **Documentation**: Comment package purposes in your packages.yml
5. **Startup Time**: Large package lists increase container startup time

## Integration

### Docker Compose Setup
```yaml
services:
  slurm-headnode:
    volumes:
      - ./packages.yml:/packages.yml:ro  # Uncomment to enable
```

### Installation Timing
1. Container starts
2. Package installer runs (`/opt/package-installer.sh`)
3. DNF packages installed first
4. Python packages installed second  
5. SLURM services start
6. Container ready for use