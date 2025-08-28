#!/bin/bash
#
# mmdebstrap Wrapper Module
# Creates chroot using mmdebstrap at 20% of build process
#
set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ -f "$REPO_ROOT/common_module_functions.sh" ]]; then
    source "$REPO_ROOT/common_module_functions.sh"
else
    echo "ERROR: Common module functions not found at $REPO_ROOT/common_module_functions.sh" >&2
    exit 1
fi

# Module configuration
MODULE_NAME="mmdebstrap-wrapper"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${BUILD_ROOT:-${1:-/tmp/build}}"
CHROOT_DIR="$BUILD_ROOT/chroot"
DEBIAN_RELEASE="${DEBIAN_RELEASE:-noble}"
ARCH="${ARCH:-amd64}"

# Validate parameters
validate_parameters() {
    # Validate architecture
    case "$ARCH" in
        amd64|arm64|armhf|i386) ;;
        *) log_error "Unsupported architecture: $ARCH. Supported: amd64, arm64, armhf, i386" ;;
    esac
    
    # Validate release
    case "$DEBIAN_RELEASE" in
        noble|jammy|focal|bionic) ;;
        *) log_warning "Unrecognized Ubuntu release: $DEBIAN_RELEASE. Proceeding anyway..." ;;
    esac
    
    # Validate BUILD_ROOT path
    if [[ ! "$BUILD_ROOT" =~ ^[[:alnum:]/_.-]+$ ]]; then
        log_error "BUILD_ROOT contains invalid characters: $BUILD_ROOT"
    fi
}

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
    )
    
    log_info "Checking for mounted filesystems in chroot..."
    
    for mount_point in "${mount_points[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_info "Unmounting $mount_point"
            sudo umount "$mount_point" 2>/dev/null || {
                log_warning "Normal unmount failed for $mount_point, trying lazy unmount..."
                sudo umount -l "$mount_point" 2>/dev/null || log_warning "Failed to unmount $mount_point"
            }
        fi
    done
    
    # Check for any remaining mounts
    if mount | grep -q "$chroot_path"; then
        log_warning "Some mounts still active in chroot, attempting cleanup..."
        mount | grep "$chroot_path" | while IFS= read -r line; do
            mount_point=$(echo "$line" | awk '{print $3}')
            log_info "Attempting to unmount: $mount_point"
            sudo umount "$mount_point" 2>/dev/null || sudo umount -l "$mount_point" 2>/dev/null || true
        done
    fi
    
    sleep 2
}

# Function to kill processes using chroot
kill_chroot_processes() {
    local chroot_path="$1"
    
    if command -v fuser >/dev/null 2>&1; then
        if fuser "$chroot_path" 2>/dev/null; then
            log_warning "Found processes using chroot, terminating them..."
            sudo fuser -TERM "$chroot_path" 2>/dev/null || true
            sleep 2
            if fuser "$chroot_path" 2>/dev/null; then
                log_warning "Processes still running, using KILL signal..."
                sudo fuser -KILL "$chroot_path" 2>/dev/null || true
                sleep 1
            fi
        fi
    fi
}

# Function to safely remove existing chroot
remove_existing_chroot() {
    local chroot_path="$1"
    
    log_info "Removing existing chroot for clean build..."
    
    # Kill processes using the chroot
    kill_chroot_processes "$chroot_path"
    
    # Unmount filesystems
    unmount_chroot_safely "$chroot_path"
    
    # Remove the directory
    if ! rm -rf "$chroot_path" 2>/dev/null; then
        log_warning "Standard removal failed, trying with sudo..."
        if ! sudo rm -rf "$chroot_path" 2>/dev/null; then
            log_warning "Some files couldn't be removed, attempting permission changes..."
            sudo find "$chroot_path" -type f -exec chmod u+w {} + 2>/dev/null || true
            sudo find "$chroot_path" -type d -exec chmod u+w {} + 2>/dev/null || true
            sudo rm -rf "$chroot_path" || log_error "Failed to remove existing chroot: $chroot_path"
        fi
    fi
    
    # Verify removal
    if [[ -d "$chroot_path" ]]; then
        log_error "Failed to completely remove existing chroot: $chroot_path"
    fi
}

# Function to create checkpoint (fallback if not in common functions)
create_checkpoint() {
    local checkpoint_name="$1"
    local build_root="$2"
    
    if command -v create_checkpoint >/dev/null 2>&1; then
        # Use the function from common_module_functions.sh if available
        command create_checkpoint "$checkpoint_name" "$build_root"
    else
        # Fallback implementation
        local checkpoint_dir="$build_root/checkpoints"
        mkdir -p "$checkpoint_dir"
        echo "$(date -Iseconds)" > "$checkpoint_dir/$checkpoint_name"
        log_info "Checkpoint created: $checkpoint_name"
    fi
}

# Function to setup basic chroot environment
setup_chroot_environment() {
    local chroot_path="$1"
    
    log_info "Setting up basic chroot environment..."
    
    # Setup DNS resolution with fallback
    local dns_servers=("8.8.8.8" "1.1.1.1" "9.9.9.9")
    {
        for dns in "${dns_servers[@]}"; do
            echo "nameserver $dns"
        done
    } > "$chroot_path/etc/resolv.conf" || {
        log_warning "Failed to setup DNS resolution"
    }
    
    # Create required directories
    local required_dirs=("proc" "sys" "dev" "dev/pts" "dev/shm" "tmp" "var/tmp" "run")
    for dir in "${required_dirs[@]}"; do
        if ! mkdir -p "$chroot_path/$dir"; then
            log_warning "Failed to create directory: $chroot_path/$dir"
        fi
    done
    
    # Set appropriate permissions
    chmod 755 "$chroot_path" 2>/dev/null || log_warning "Could not set chroot permissions"
    chmod 1777 "$chroot_path/tmp" 2>/dev/null || log_warning "Could not set /tmp permissions"
    chmod 1777 "$chroot_path/var/tmp" 2>/dev/null || log_warning "Could not set /var/tmp permissions"
}

# Function to verify chroot integrity
verify_chroot() {
    local chroot_path="$1"
    local critical_files=("bin/bash" "usr/bin/apt" "etc/passwd" "etc/group")
    local missing_files=()
    
    log_info "Verifying chroot integrity..."
    
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$chroot_path/$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Chroot verification failed - missing critical files: ${missing_files[*]}"
        return 1
    fi
    
    # Check basic directory structure
    local critical_dirs=("etc" "usr" "var" "bin" "sbin")
    local missing_dirs=()
    
    for dir in "${critical_dirs[@]}"; do
        if [[ ! -d "$chroot_path/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_error "Chroot verification failed - missing critical directories: ${missing_dirs[*]}"
        return 1
    fi
    
    log_success "Chroot verification passed"
    return 0
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================
main() {
    log_info "=== MMDEBSTRAP CHROOT CREATION MODULE ==="
    log_info "Module: $MODULE_NAME v$MODULE_VERSION"
    log_info "Creating chroot at: $CHROOT_DIR"
    log_info "Release: $DEBIAN_RELEASE"
    log_info "Architecture: $ARCH"
    
    # Validate input parameters
    validate_parameters
    
    # Check prerequisites
    if ! command -v mmdebstrap >/dev/null 2>&1; then
        log_error "mmdebstrap not found. Install with: sudo apt-get install mmdebstrap"
    fi
    
    # Check if chroot already exists
    if [[ -d "$CHROOT_DIR" ]]; then
        if [[ -f "$CHROOT_DIR/bin/bash" ]]; then
            log_warning "Chroot already exists at $CHROOT_DIR"
            remove_existing_chroot "$CHROOT_DIR"
        else
            log_info "Removing incomplete chroot directory..."
            rm -rf "$CHROOT_DIR" || {
                log_warning "Failed to remove incomplete chroot, trying with sudo..."
                sudo rm -rf "$CHROOT_DIR" || log_error "Could not remove incomplete chroot"
            }
        fi
    fi
    
    # Create parent directory
    if ! mkdir -p "$(dirname "$CHROOT_DIR")"; then
        log_error "Failed to create parent directory for chroot"
    fi
    
    # Create checkpoint
    create_checkpoint "mmdebstrap_start" "$BUILD_ROOT"
    
    # Run mmdebstrap
    log_info "Running mmdebstrap (this may take 5-10 minutes)..."
    
    local mmdebstrap_success=false
    
    if mmdebstrap \
        --variant=minbase \
        --include=apt-utils,systemd,systemd-sysv,dbus,wget,curl,gnupg,ca-certificates,locales \
        --components=main,restricted,universe,multiverse \
        --architectures="$ARCH" \
        --verbose \
        "$DEBIAN_RELEASE" \
        "$CHROOT_DIR" \
        "http://archive.ubuntu.com/ubuntu"; then
        
        log_success "Chroot created successfully with mmdebstrap"
        mmdebstrap_success=true
        create_checkpoint "mmdebstrap_complete" "$BUILD_ROOT"
    else
        log_error "Failed to create chroot with mmdebstrap"
        
        # Try fallback with debootstrap if mmdebstrap fails
        if command -v debootstrap >/dev/null 2>&1; then
            log_warning "Attempting fallback with debootstrap..."
            
            # Clean up partial mmdebstrap attempt
            [[ -d "$CHROOT_DIR" ]] && rm -rf "$CHROOT_DIR"
            
            if debootstrap \
                --arch="$ARCH" \
                --variant=minbase \
                --include=systemd,systemd-sysv,dbus,apt-utils,wget,curl,gnupg,ca-certificates \
                "$DEBIAN_RELEASE" \
                "$CHROOT_DIR" \
                "http://archive.ubuntu.com/ubuntu"; then
                log_success "Chroot created with debootstrap fallback"
                create_checkpoint "debootstrap_complete" "$BUILD_ROOT"
            else
                log_error "Both mmdebstrap and debootstrap failed"
                exit 1
            fi
        else
            log_error "debootstrap not available for fallback"
            exit 1
        fi
    fi
    
    # Verify chroot
    if verify_chroot "$CHROOT_DIR"; then
        # Basic setup
        setup_chroot_environment "$CHROOT_DIR"
        
        # Show chroot size if du is available
        if command -v du >/dev/null 2>&1; then
            local chroot_size
            chroot_size=$(du -sh "$CHROOT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
            log_info "Chroot size: $chroot_size"
        fi
        
        log_success "=== MMDEBSTRAP MODULE COMPLETE ==="
        log_info "Chroot ready at: $CHROOT_DIR"
        log_info "Next: Configure and install packages in chroot"
    else
        log_error "Chroot verification failed"
        exit 1
    fi
    
    exit 0
}

# Cleanup function for trap
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -d "$CHROOT_DIR" ]]; then
        log_warning "Script failed, cleaning up partial chroot..."
        remove_existing_chroot "$CHROOT_DIR" 2>/dev/null || true
    fi
    exit $exit_code
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT INT TERM

# Execute main function
main "$@"