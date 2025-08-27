#!/bin/bash
#
# Dependency Validation Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Validates all build dependencies and system requirements
#

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

[[ -f "$REPO_ROOT/common_module_functions.sh" ]] && \
    source "$REPO_ROOT/common_module_functions.sh" || {
        echo "ERROR: Common module functions not found" >&2
        exit 1
    }

# Module configuration
MODULE_NAME="dependency-validation"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"

# Dependency requirements
readonly MIN_DISK_SPACE_GB=20
readonly MIN_RAM_GB=4
readonly REQUIRED_COMMANDS=(
    "debootstrap" "systemd-nspawn" "mksquashfs" 
    "xorriso" "git" "zpool" "zfs"
    "gcc" "make" "dpkg" "apt-get"
)

readonly REQUIRED_PACKAGES=(
    "build-essential" "debootstrap" "squashfs-tools"
    "xorriso" "isolinux" "syslinux-utils" 
    "zfsutils-linux" "systemd-container"
)

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

validate_system_requirements() {
    log_info "Validating system requirements..."
    
    local validation_errors=0
    
    # Check disk space
    local available_space=$(df "$BUILD_ROOT" --output=avail -B G 2>/dev/null | tail -1 | tr -d 'G')
    if [[ ${available_space:-0} -lt $MIN_DISK_SPACE_GB ]]; then
        log_error "Insufficient disk space: ${available_space}GB (${MIN_DISK_SPACE_GB}GB required)"
        ((validation_errors++))
    else
        log_success "Disk space: ${available_space}GB available"
    fi
    
    # Check RAM
    local available_ram=$(free -g | awk '/^Mem:/{print $7}')
    if [[ ${available_ram:-0} -lt $MIN_RAM_GB ]]; then
        log_warning "Low memory: ${available_ram}GB (${MIN_RAM_GB}GB recommended)"
    else
        log_success "Memory: ${available_ram}GB available"
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    log_info "CPU cores available: $cpu_cores"
    
    return $validation_errors
}

validate_commands() {
    log_info "Validating required commands..."
    
    local missing_commands=()
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
            log_error "Missing command: $cmd"
        else
            log_debug "Found command: $cmd"
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing ${#missing_commands[@]} required commands"
        log_error "Install with: apt-get install ${missing_commands[*]}"
        return 1
    fi
    
    log_success "All required commands found"
    return 0
}

validate_kernel_support() {
    log_info "Validating kernel support..."
    
    local validation_errors=0
    
    # Check kernel version
    local kernel_version=$(uname -r)
    log_info "Kernel version: $kernel_version"
    
    # Check for required modules
    local required_modules=("zfs" "overlay" "squashfs")
    
    for module in "${required_modules[@]}"; do
        if ! modinfo "$module" &>/dev/null; then
            log_warning "Kernel module not found: $module"
            ((validation_errors++))
        else
            log_debug "Found module: $module"
        fi
    done
    
    return $validation_errors
}

validate_build_environment() {
    log_info "Validating build environment..."
    
    # Create build directory structure
    safe_mkdir "$BUILD_ROOT" 755
    safe_mkdir "$BUILD_ROOT/work" 755
    safe_mkdir "$BUILD_ROOT/logs" 755
    safe_mkdir "$BUILD_ROOT/cache" 755
    
    # Check write permissions
    if ! touch "$BUILD_ROOT/.write_test" 2>/dev/null; then
        log_error "Cannot write to build directory: $BUILD_ROOT"
        return 1
    fi
    rm -f "$BUILD_ROOT/.write_test"
    
    log_success "Build environment validated"
    return 0
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== DEPENDENCY VALIDATION MODULE ==="
    
    local total_errors=0
    
    # Run all validations
    validate_system_requirements || ((total_errors++))
    validate_commands || ((total_errors++))
    validate_kernel_support || ((total_errors++))
    validate_build_environment || ((total_errors++))
    
    if [[ $total_errors -gt 0 ]]; then
        log_error "Dependency validation failed with $total_errors errors"
        exit 1
    fi
    
    # Create validation report
    cat > "$BUILD_ROOT/validation-report.txt" <<EOF
Dependency Validation Report
Generated: $(date -Iseconds)
Status: PASSED

System Requirements:
- Disk Space: $(df -h "$BUILD_ROOT" | tail -1 | awk '{print $4}') available
- Memory: $(free -h | grep Mem | awk '{print $7}') available
- CPU Cores: $(nproc)
- Kernel: $(uname -r)

All dependencies validated successfully
EOF
    
    log_success "=== DEPENDENCY VALIDATION COMPLETE ==="
    exit 0
}

main "$@"
