#!/bin/bash
#
# MMDEBSTRAP MODULE - CHROOT CREATION AT 20%
# This module creates the chroot using mmdebstrap
#

set -euo pipefail

# Get build root from argument or environment
BUILD_ROOT="${1:-${BUILD_ROOT:-/tmp/build}}"
CHROOT_DIR="$BUILD_ROOT/chroot"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source common functions
if [[ -f "$REPO_ROOT/common_module_functions.sh" ]]; then
    source "$REPO_ROOT/common_module_functions.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; exit 1; }
    log_warning() { echo "[WARN] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

log_info "=== MMDEBSTRAP MODULE: Creating chroot at 20% ==="
log_info "Build root: $BUILD_ROOT"
log_info "Chroot directory: $CHROOT_DIR"

# Check if chroot already exists
if [[ -d "$CHROOT_DIR" ]]; then
    log_warning "Chroot directory already exists: $CHROOT_DIR"
    log_info "Cleaning up existing chroot safely..."
    
    # Kill any processes using the chroot
    sudo fuser -k "$CHROOT_DIR" 2>/dev/null || true
    
    # Unmount any mounted filesystems in chroot (in proper order)
    sudo umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    sudo umount "$CHROOT_DIR/dev/shm" 2>/dev/null || true  
    sudo umount "$CHROOT_DIR/dev" 2>/dev/null || true
    sudo umount "$CHROOT_DIR/proc" 2>/dev/null || true
    sudo umount "$CHROOT_DIR/sys" 2>/dev/null || true
    sudo umount "$CHROOT_DIR/run" 2>/dev/null || true
    
    # Verify no mounts remain
    if mount | grep -q "$CHROOT_DIR"; then
        log_warning "Some mounts still active, forcing lazy unmount..."
        mount | grep "$CHROOT_DIR" | awk '{print $3}' | xargs -r sudo umount -l 2>/dev/null || true
    fi
    
    # Wait a moment for unmounts to complete
    sleep 2
    
    # Remove the directory
    rm -rf "$CHROOT_DIR" || {
        log_warning "Some readonly files remain, but continuing..."
        # Force remove what we can
        find "$CHROOT_DIR" -type f -exec rm -f {} + 2>/dev/null || true
        find "$CHROOT_DIR" -type d -exec rmdir {} + 2>/dev/null || true
    }
fi

# Create parent directory if needed
mkdir -p "$BUILD_ROOT"

# Check for mmdebstrap
if ! command -v mmdebstrap >/dev/null 2>&1; then
    log_error "mmdebstrap not found. Please install: sudo apt-get install mmdebstrap"
fi

log_info "Creating Ubuntu Noble chroot with mmdebstrap..."
log_info "This may take 5-10 minutes..."

# Create the chroot with mmdebstrap
# Using standard variant with full GNOME desktop environment
if mmdebstrap \
    --variant=standard \
    --include=apt-utils,systemd,systemd-sysv,dbus,sudo,curl,wget,ca-certificates,ubuntu-desktop-minimal,gnome-shell,gdm3,network-manager,firefox,nautilus,gedit,gnome-terminal \
    --components=main,universe,restricted,multiverse \
    --verbose \
    noble \
    "$CHROOT_DIR" \
    http://archive.ubuntu.com/ubuntu; then
    
    log_success "Chroot created successfully at $CHROOT_DIR"
    
    # Create marker file to indicate successful creation
    touch "$CHROOT_DIR/.mmdebstrap-complete"
    echo "$(date -Iseconds)" > "$CHROOT_DIR/.mmdebstrap-timestamp"
    
    # Verify chroot structure
    if [[ -d "$CHROOT_DIR/usr" ]] && [[ -d "$CHROOT_DIR/bin" ]] && [[ -d "$CHROOT_DIR/etc" ]]; then
        log_success "Chroot structure verified"
        
        # Show chroot size
        CHROOT_SIZE=$(du -sh "$CHROOT_DIR" 2>/dev/null | cut -f1)
        log_info "Chroot size: $CHROOT_SIZE"
    else
        log_error "Chroot structure verification failed - missing critical directories"
    fi
    
else
    log_error "mmdebstrap failed to create chroot"
fi

log_success "=== MMDEBSTRAP MODULE COMPLETE ==="
exit 0