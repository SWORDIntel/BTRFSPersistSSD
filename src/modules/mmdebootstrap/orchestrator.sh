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

# Function to safely unmount chroot filesystems
unmount_chroot_safely() {
    local chroot_path="$1"
    local mount_points=(
        "$chroot_path/dev/pts"
        "$chroot_path/dev/shm"  
        "$chroot_path/dev"
        "$chroot_path/proc"
        "$chroot_path/sys"
        "$chroot_path/run"
        "$chroot_path/tmp"
        "$chroot_path/var/cache/apt/archives"
    )
    
    log_info "Unmounting chroot filesystems..."
    
    for mount_point in "${mount_points[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_info "Unmounting $mount_point"
            sudo umount "$mount_point" 2>/dev/null || {
                log_warning "Normal unmount failed for $mount_point, trying lazy unmount..."
                sudo umount -l "$mount_point" 2>/dev/null || log_warning "Failed to unmount $mount_point"
            }
        fi
    done
    
    # Check for any remaining mounts and handle them
    if mount | grep -q "$chroot_path"; then
        log_warning "Some mounts still active, attempting to unmount..."
        mount | grep "$chroot_path" | while IFS= read -r line; do
            mount_point=$(echo "$line" | awk '{print $3}')
            log_info "Attempting to unmount remaining mount: $mount_point"
            sudo umount "$mount_point" 2>/dev/null || sudo umount -l "$mount_point" 2>/dev/null || true
        done
    fi
    
    # Wait for unmounts to complete
    sleep 2
}

# Function to kill processes using chroot
kill_chroot_processes() {
    local chroot_path="$1"
    
    if command -v fuser >/dev/null 2>&1; then
        log_info "Checking for processes using chroot..."
        if fuser "$chroot_path" 2>/dev/null; then
            log_warning "Found processes using chroot, attempting to terminate them..."
            # First try TERM signal
            sudo fuser -TERM "$chroot_path" 2>/dev/null || true
            sleep 2
            # Then try KILL signal if needed
            if fuser "$chroot_path" 2>/dev/null; then
                log_warning "Processes still running, using KILL signal..."
                sudo fuser -KILL "$chroot_path" 2>/dev/null || true
                sleep 1
            fi
        fi
    else
        log_warning "fuser command not available, skipping process cleanup"
    fi
}

# Check if chroot already exists
if [[ -d "$CHROOT_DIR" ]]; then
    log_warning "Chroot directory already exists: $CHROOT_DIR"
    log_info "Cleaning up existing chroot safely..."
    
    # Kill any processes using the chroot
    kill_chroot_processes "$CHROOT_DIR"
    
    # Unmount any mounted filesystems in chroot
    unmount_chroot_safely "$CHROOT_DIR"
    
    # Remove the directory
    if ! rm -rf "$CHROOT_DIR" 2>/dev/null; then
        log_warning "Some files couldn't be removed normally, trying with sudo..."
        sudo rm -rf "$CHROOT_DIR" 2>/dev/null || {
            log_warning "Some readonly files remain, attempting to change permissions..."
            # Try to change permissions on readonly files
            sudo find "$CHROOT_DIR" -type f -exec chmod u+w {} + 2>/dev/null || true
            sudo find "$CHROOT_DIR" -type d -exec chmod u+w {} + 2>/dev/null || true
            # Try removal again
            sudo rm -rf "$CHROOT_DIR" 2>/dev/null || {
                log_error "Failed to completely remove existing chroot directory: $CHROOT_DIR"
            }
        }
    fi
    
    # Verify removal
    if [[ -d "$CHROOT_DIR" ]]; then
        log_error "Failed to remove existing chroot directory: $CHROOT_DIR"
    fi
fi

# Create parent directory if needed
if ! mkdir -p "$BUILD_ROOT"; then
    log_error "Failed to create build root directory: $BUILD_ROOT"
fi

# Check for mmdebstrap
if ! command -v mmdebstrap >/dev/null 2>&1; then
    log_error "mmdebstrap not found. Please install: sudo apt-get install mmdebstrap"
fi

# Check if we have sudo access
if ! sudo -n true 2>/dev/null; then
    log_error "This script requires sudo access. Please run with appropriate privileges."
fi

log_info "Creating Ubuntu Noble chroot with mmdebstrap..."
log_info "This may take 5-10 minutes..."

# Create the chroot with mmdebstrap
# Using standard variant with essential packages only (desktop packages added later)
if ! mmdebstrap \
    --variant=standard \
    --include=apt-utils,systemd,systemd-sysv,dbus,sudo,curl,wget,ca-certificates,locales \
    --components=main,universe,restricted,multiverse \
    --verbose \
    noble \
    "$CHROOT_DIR" \
    "http://archive.ubuntu.com/ubuntu"; then
    log_error "mmdebstrap failed to create chroot"
fi

log_success "Chroot created successfully at $CHROOT_DIR"

# Create marker file to indicate successful creation
if ! touch "$CHROOT_DIR/.mmdebstrap-complete"; then
    log_warning "Could not create completion marker file"
fi

if ! echo "$(date -Iseconds)" > "$CHROOT_DIR/.mmdebstrap-timestamp"; then
    log_warning "Could not create timestamp file"
fi

# Verify chroot structure
log_info "Verifying chroot structure..."
critical_dirs=("usr" "bin" "etc" "var" "opt" "home")
missing_dirs=()

for dir in "${critical_dirs[@]}"; do
    if [[ ! -d "$CHROOT_DIR/$dir" ]]; then
        missing_dirs+=("$dir")
    fi
done

if [[ ${#missing_dirs[@]} -gt 0 ]]; then
    log_error "Chroot structure verification failed - missing critical directories: ${missing_dirs[*]}"
else
    log_success "Chroot structure verified"
fi

# Show chroot size
if command -v du >/dev/null 2>&1; then
    CHROOT_SIZE=$(du -sh "$CHROOT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Chroot size: $CHROOT_SIZE"
fi

# Set appropriate permissions
if ! chmod 755 "$CHROOT_DIR"; then
    log_warning "Could not set permissions on chroot directory"
fi

log_success "=== MMDEBSTRAP MODULE COMPLETE ==="
exit 0