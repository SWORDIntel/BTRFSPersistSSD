#!/bin/bash
#
# Environment Setup Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Sets up the build environment and chroot structure
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
MODULE_NAME="environment-setup"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"
WORK_DIR="$BUILD_ROOT/work"

# Environment settings
readonly DEBIAN_RELEASE="jammy"
readonly ARCH="amd64"

#=============================================================================
# ENVIRONMENT SETUP FUNCTIONS
#=============================================================================

setup_build_directories() {
    log_info "Setting up build directory structure..."
    
    # Create directory hierarchy
    local directories=(
        "$CHROOT_DIR"
        "$WORK_DIR/iso"
        "$WORK_DIR/scratch"
        "$BUILD_ROOT/cache/packages"
        "$BUILD_ROOT/logs"
        "$BUILD_ROOT/config"
    )
    
    for dir in "${directories[@]}"; do
        safe_mkdir "$dir" 755
        log_debug "Created: $dir"
    done
    
    log_success "Build directories created"
}

setup_apt_cache() {
    log_info "Setting up APT cache..."
    
    # Configure apt caching to speed up builds
    cat > "$BUILD_ROOT/config/apt-cache.conf" <<EOF
Dir::Cache::Archives "$BUILD_ROOT/cache/packages";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Languages "none";
EOF
    
    log_success "APT cache configured"
}

# REMOVED: setup_debootstrap function 
# Chroot creation is handled by mmdebstrap module at 20%
# This module should ONLY prepare directories, not create chroot

configure_chroot_mounts() {
    log_info "Configuring chroot mount points..."
    
    # Setup essential mount points
    safe_mkdir "$CHROOT_DIR/proc" 555
    safe_mkdir "$CHROOT_DIR/sys" 555
    safe_mkdir "$CHROOT_DIR/dev" 755
    safe_mkdir "$CHROOT_DIR/dev/pts" 755
    safe_mkdir "$CHROOT_DIR/run" 755
    
    log_success "Mount points configured"
}

setup_network_configuration() {
    log_info "Setting up network configuration..."
    
    # Copy resolv.conf for network access
    cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"
    
    # Configure hostname
    echo "livecd" > "$CHROOT_DIR/etc/hostname"
    
    # Configure hosts file
    cat > "$CHROOT_DIR/etc/hosts" <<EOF
127.0.0.1       localhost
127.0.1.1       livecd
::1             localhost ip6-localhost ip6-loopback
EOF
    
    log_success "Network configuration complete"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== ENVIRONMENT SETUP MODULE ==="
    
    # Setup build environment
    setup_build_directories || exit 1
    setup_apt_cache || exit 1
    # NOTE: Chroot creation handled by mmdebstrap module
    # setup_debootstrap removed - using mmdebstrap instead
    # configure_chroot_mounts will be done after chroot exists
    setup_network_configuration || exit 1
    
    # Save environment configuration
    cat > "$BUILD_ROOT/config/environment.conf" <<EOF
# Build Environment Configuration
BUILD_DATE=$(date -Iseconds)
DEBIAN_RELEASE=$DEBIAN_RELEASE
ARCHITECTURE=$ARCH
BUILD_ROOT=$BUILD_ROOT
CHROOT_DIR=$CHROOT_DIR
WORK_DIR=$WORK_DIR
EOF
    
    log_success "=== ENVIRONMENT SETUP COMPLETE ==="
    exit 0
}

main "$@"
