#!/bin/bash
#
# MMDebootstrap Wrapper Module
# Creates chroot using mmdebstrap at 20% of build process
#

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

[[ -f "$REPO_ROOT/common_module_functions.sh" ]] && \
    source "$REPO_ROOT/common_module_functions.sh" || {
        echo "ERROR: Common module functions not found" >&2
        exit 1
    }

# Module configuration
MODULE_NAME="mmdebstrap-wrapper"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${BUILD_ROOT:-${1:-/tmp/build}}"
CHROOT_DIR="$BUILD_ROOT/chroot"
DEBIAN_RELEASE="${DEBIAN_RELEASE:-noble}"
ARCH="${ARCH:-amd64}"

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== MMDEBOOSTRAP CHROOT CREATION MODULE ==="
    log_info "Creating chroot at: $CHROOT_DIR"
    log_info "Release: $DEBIAN_RELEASE"
    log_info "Architecture: $ARCH"
    
    # Check if chroot already exists
    if [[ -d "$CHROOT_DIR" && -f "$CHROOT_DIR/bin/bash" ]]; then
        log_warning "Chroot already exists at $CHROOT_DIR"
        log_info "Removing old chroot for clean build..."
        rm -rf "$CHROOT_DIR"
    fi
    
    # Create parent directory
    mkdir -p "$(dirname "$CHROOT_DIR")"
    
    # Create checkpoint
    create_checkpoint "mmdebstrap_start" "$BUILD_ROOT"
    
    # Run mmdebstrap
    log_info "Running mmdebstrap (this may take 5-10 minutes)..."
    
    if mmdebstrap \
        --variant=minbase \
        --include=apt-utils,systemd,systemd-sysv,dbus,wget,curl,gnupg,ca-certificates \
        --components=main,restricted,universe,multiverse \
        --architectures="$ARCH" \
        "$DEBIAN_RELEASE" \
        "$CHROOT_DIR" \
        http://archive.ubuntu.com/ubuntu; then
        
        log_success "Chroot created successfully"
        create_checkpoint "mmdebstrap_complete" "$BUILD_ROOT"
    else
        log_error "Failed to create chroot with mmdebstrap"
        
        # Try fallback with debootstrap if mmdebstrap fails
        log_warning "Attempting fallback with debootstrap..."
        if debootstrap \
            --arch="$ARCH" \
            --variant=minbase \
            --include=systemd,systemd-sysv,dbus,apt-utils \
            "$DEBIAN_RELEASE" \
            "$CHROOT_DIR" \
            http://archive.ubuntu.com/ubuntu; then
            log_success "Chroot created with debootstrap fallback"
        else
            log_error "Both mmdebstrap and debootstrap failed"
            exit 1
        fi
    fi
    
    # Verify chroot
    if [[ -f "$CHROOT_DIR/bin/bash" ]]; then
        log_success "Chroot verification passed"
        
        # Basic setup
        echo "nameserver 8.8.8.8" > "$CHROOT_DIR/etc/resolv.conf"
        echo "nameserver 1.1.1.1" >> "$CHROOT_DIR/etc/resolv.conf"
        
        # Create required directories
        mkdir -p "$CHROOT_DIR/proc"
        mkdir -p "$CHROOT_DIR/sys"
        mkdir -p "$CHROOT_DIR/dev/pts"
        
        log_success "=== MMDEBOOSTRAP MODULE COMPLETE ==="
        log_info "Chroot ready at: $CHROOT_DIR"
    else
        log_error "Chroot verification failed - no bash found"
        exit 1
    fi
    
    exit 0
}

# Execute main function
main "$@"