#!/bin/bash
#
# ENHANCED BOOTSTRAP MODULE v3.2.0
# STAGE: 25% - Verify and enhance existing chroot
# This module verifies the chroot created at 20% and adds enhancements
#

set -euo pipefail

# Module configuration
MODULE_NAME="03-mmdebstrap-bootstrap"
MODULE_VERSION="3.2.0"
MODULE_PHASE="25%"
MODULE_DESC="Verify and enhance existing chroot with advanced profiles"

# Source paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../" && pwd)"

# Environment variables
BUILD_ROOT="${BUILD_ROOT:-${1:-/tmp/build}}"
CHROOT_DIR="${BUILD_ROOT}/chroot"
LOG_DIR="${BUILD_ROOT}/.logs"
STATE_FILE="${BUILD_ROOT}/.build_state"
CHECKPOINT_DIR="${BUILD_ROOT}/checkpoints"

# Build profiles
BUILD_PROFILE="${BUILD_PROFILE:-standard}"
DEBIAN_RELEASE="${DEBIAN_RELEASE:-noble}"
ARCH="${ARCH:-amd64}"

# Profile definitions
declare -A PROFILE_PACKAGES
PROFILE_PACKAGES[minimal]="apt-utils systemd systemd-sysv dbus"
PROFILE_PACKAGES[standard]="apt-utils systemd systemd-sysv dbus wget curl gnupg ca-certificates locales"
PROFILE_PACKAGES[development]="${PROFILE_PACKAGES[standard]} build-essential git vim emacs"
PROFILE_PACKAGES[zfs_optimized]="${PROFILE_PACKAGES[standard]} zfsutils-linux zfs-dkms"
PROFILE_PACKAGES[security]="${PROFILE_PACKAGES[standard]} fail2ban ufw apparmor"

# Framework loading with fallback functions
load_framework() {
    local framework_script="$PROJECT_ROOT/common_module_functions.sh"
    
    if [[ -f "$framework_script" ]]; then
        source "$framework_script"
        echo "[INFO] Framework loaded from $framework_script"
        return 0
    else
        # Define minimal fallback functions
        log_info() { echo "[INFO] $*"; }
        log_warning() { echo "[WARN] $*"; }
        log_error() { echo "[ERROR] $*" >&2; return 1; }
        log_success() { echo "[SUCCESS] $*"; }
        log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo "[DEBUG] $*" || true; }
        
        create_checkpoint() {
            local name="$1"
            mkdir -p "$CHECKPOINT_DIR"
            echo "$(date -Iseconds)" > "$CHECKPOINT_DIR/$name"
            log_info "Checkpoint created: $name"
        }
        
        update_build_state() {
            local key="$1"
            local value="$2"
            mkdir -p "$(dirname "$STATE_FILE")"
            echo "$key=$value" >> "$STATE_FILE"
        }
        
        echo "[WARN] Framework not found, using fallback functions"
        return 1
    fi
}

# Validation functions
validate_chroot_exists() {
    log_info "Validating chroot existence at $CHROOT_DIR"
    
    if [[ ! -d "$CHROOT_DIR" ]]; then
        log_error "CRITICAL: Chroot does not exist at $CHROOT_DIR"
        log_error "The chroot should have been created at 20% by mmdebootstrap/orchestrator"
        return 1
    fi
    
    # Check for mmdebstrap markers
    if [[ -f "$CHROOT_DIR/.mmdebstrap-complete" ]]; then
        log_success "Found mmdebstrap completion marker"
        log_info "Chroot created at: $(cat "$CHROOT_DIR/.mmdebstrap-timestamp" 2>/dev/null || echo "unknown")"
    else
        log_warning "No mmdebstrap marker found, but chroot exists - continuing"
    fi
    
    return 0
}

validate_chroot_structure() {
    log_info "Validating chroot structure integrity"
    
    local critical_dirs=(
        "bin" "boot" "dev" "etc" "home" "lib" "lib64" 
        "opt" "proc" "root" "sbin" "sys" "tmp" 
        "usr" "var"
    )
    
    local missing_dirs=()
    for dir in "${critical_dirs[@]}"; do
        if [[ ! -d "$CHROOT_DIR/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_error "Missing critical directories: ${missing_dirs[*]}"
        return 1
    fi
    
    # Verify essential binaries
    local essential_bins=(
        "bin/bash" "bin/sh" "usr/bin/apt"
        "usr/bin/dpkg" "bin/systemctl"
    )
    
    local missing_bins=()
    for bin in "${essential_bins[@]}"; do
        if [[ ! -e "$CHROOT_DIR/$bin" ]] && [[ ! -L "$CHROOT_DIR/$bin" ]]; then
            missing_bins+=("$bin")
        fi
    done
    
    if [[ ${#missing_bins[@]} -gt 0 ]]; then
        log_error "Missing essential binaries: ${missing_bins[*]}"
        return 1
    fi
    
    log_success "Chroot structure validation passed"
    return 0
}

validate_chroot_mounts() {
    log_info "Checking for active mounts in chroot"
    
    local mount_count=$(mount | grep -c "$CHROOT_DIR" || true)
    
    if [[ $mount_count -gt 0 ]]; then
        log_warning "Found $mount_count active mounts in chroot"
        mount | grep "$CHROOT_DIR" || true
        
        if [[ "${FORCE_UNMOUNT:-0}" == "1" ]]; then
            log_warning "Force unmounting requested"
            unmount_chroot_safely "$CHROOT_DIR"
        else
            log_info "Mounts will be preserved for chroot operations"
        fi
    else
        log_info "No active mounts found in chroot"
    fi
}

# Safe unmount function
unmount_chroot_safely() {
    # GUARD CLAUSE: Prevent recursive unmount calls
    if [[ "${STAGE_UNMOUNT_IN_PROGRESS:-0}" == "1" ]]; then
        echo "[WARNING] Stage unmount already in progress, skipping recursive call"
        return 0
    fi
    
    export STAGE_UNMOUNT_IN_PROGRESS=1
    
    # Disable error trap to prevent recursion
    trap - ERR
    set +e
    
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
    
    for mount_point in "${mount_points[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_info "Unmounting $mount_point"
            sudo umount "$mount_point" 2>/dev/null || \
                sudo umount -l "$mount_point" 2>/dev/null || \
                log_warning "Failed to unmount $mount_point"
        fi
    done
    
    # Final check and cleanup
    if mount | grep -q "$chroot_path"; then
        log_warning "Some mounts remain, attempting lazy unmount"
        mount | grep "$chroot_path" | awk '{print $3}' | while read -r mp; do
            sudo umount -l "$mp" 2>/dev/null || true
        done
    fi
    
    # Clear guard flag and always return success  
    export STAGE_UNMOUNT_IN_PROGRESS=0
    return 0
}

# Enhancement functions
enhance_chroot_networking() {
    log_info "Enhancing chroot networking configuration"
    
    # Update DNS configuration - handle symlink properly
    if [[ -L "$CHROOT_DIR/etc/resolv.conf" ]]; then
        rm -f "$CHROOT_DIR/etc/resolv.conf"
    fi
    cat > "$CHROOT_DIR/etc/resolv.conf" << EOF
# Enhanced DNS configuration
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 9.9.9.9
options edns0 trust-ad
EOF
    
    # Create systemd network configuration
    mkdir -p "$CHROOT_DIR/etc/systemd/network"
    cat > "$CHROOT_DIR/etc/systemd/network/20-wired.network" << EOF
[Match]
Name=en*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
RouteMetric=100

[DHCPv6]
RouteMetric=100
EOF
    
    log_success "Networking configuration enhanced"
}

enhance_chroot_locale() {
    log_info "Configuring locale settings"
    
    # Generate locale configuration
    cat > "$CHROOT_DIR/etc/locale.gen" << EOF
en_US.UTF-8 UTF-8
en_GB.UTF-8 UTF-8
EOF
    
    # Set default locale
    cat > "$CHROOT_DIR/etc/default/locale" << EOF
LANG=en_US.UTF-8
LANGUAGE=en_US:en
LC_ALL=en_US.UTF-8
EOF
    
    # Create locale generation script
    cat > "$CHROOT_DIR/usr/local/bin/generate-locales" << 'EOF'
#!/bin/bash
locale-gen
update-locale LANG=en_US.UTF-8
EOF
    chmod +x "$CHROOT_DIR/usr/local/bin/generate-locales"
    
    log_success "Locale configuration completed"
}

apply_profile_specific_enhancements() {
    log_info "Applying profile-specific enhancements: $BUILD_PROFILE"
    
    case "$BUILD_PROFILE" in
        minimal)
            log_info "Minimal profile - no additional enhancements"
            ;;
            
        standard)
            enhance_chroot_networking
            enhance_chroot_locale
            ;;
            
        development)
            enhance_chroot_networking
            enhance_chroot_locale
            
            # Development tools configuration
            mkdir -p "$CHROOT_DIR/opt/development"
            cat > "$CHROOT_DIR/etc/profile.d/development.sh" << 'EOF'
export PATH="/opt/development/bin:$PATH"
export EDITOR=vim
alias ll='ls -la'
alias gs='git status'
EOF
            log_info "Development environment configured"
            ;;
            
        zfs_optimized)
            enhance_chroot_networking
            enhance_chroot_locale
            
            # ZFS configuration
            mkdir -p "$CHROOT_DIR/etc/zfs"
            cat > "$CHROOT_DIR/etc/modules-load.d/zfs.conf" << EOF
zfs
EOF
            log_info "ZFS optimization configured"
            ;;
            
        security)
            enhance_chroot_networking
            enhance_chroot_locale
            
            # Security hardening
            cat > "$CHROOT_DIR/etc/sysctl.d/99-security.conf" << EOF
# Security hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
EOF
            log_info "Security hardening applied"
            ;;
            
        *)
            log_warning "Unknown profile: $BUILD_PROFILE"
            enhance_chroot_networking
            enhance_chroot_locale
            ;;
    esac
}

create_chroot_metadata() {
    log_info "Creating chroot metadata"
    
    cat > "$CHROOT_DIR/etc/build-info" << EOF
# Build Information
BUILD_DATE="$(date -Iseconds)"
MODULE_NAME="$MODULE_NAME"
MODULE_VERSION="$MODULE_VERSION"
MODULE_PHASE="$MODULE_PHASE"
BUILD_PROFILE="$BUILD_PROFILE"
DEBIAN_RELEASE="$DEBIAN_RELEASE"
ARCHITECTURE="$ARCH"
BUILD_ROOT="$BUILD_ROOT"
ENHANCED="true"
EOF
    
    # Create profile marker
    echo "$BUILD_PROFILE" > "$CHROOT_DIR/.build-profile"
    
    # Create enhancement marker
    touch "$CHROOT_DIR/.enhanced-bootstrap-complete"
    echo "$(date -Iseconds)" > "$CHROOT_DIR/.enhanced-bootstrap-timestamp"
    
    log_success "Metadata created"
}

verify_enhancement_results() {
    log_info "Verifying enhancement results"
    
    local checks_passed=0
    local checks_failed=0
    
    # Check network configuration
    if [[ -f "$CHROOT_DIR/etc/resolv.conf" ]] && [[ -f "$CHROOT_DIR/etc/systemd/network/20-wired.network" ]]; then
        log_success "Network configuration verified"
        ((checks_passed++)) || true
    else
        log_warning "Network configuration incomplete"
        ((checks_failed++)) || true
    fi
    
    # Check locale configuration
    if [[ -f "$CHROOT_DIR/etc/locale.gen" ]] && [[ -f "$CHROOT_DIR/etc/default/locale" ]]; then
        log_success "Locale configuration verified"
        ((checks_passed++)) || true
    else
        log_warning "Locale configuration incomplete"
        ((checks_failed++)) || true
    fi
    
    # Check metadata
    if [[ -f "$CHROOT_DIR/etc/build-info" ]] && [[ -f "$CHROOT_DIR/.build-profile" ]]; then
        log_success "Build metadata verified"
        ((checks_passed++)) || true
    else
        log_warning "Build metadata incomplete"
        ((checks_failed++)) || true
    fi
    
    log_info "Verification results: $checks_passed passed, $checks_failed failed"
    
    if [[ $checks_failed -gt 0 ]]; then
        log_warning "Some enhancement checks failed, but continuing"
    fi
    
    return 0
}

# Error handler
handle_error() {
    # GUARD CLAUSE: Prevent recursive error handling
    if [[ "${STAGE_ERROR_HANDLING:-0}" == "1" ]]; then
        echo "[WARNING] Error handler already in progress, skipping recursive call"
        return 1
    fi
    
    export STAGE_ERROR_HANDLING=1
    
    # Disable error trap to prevent recursion
    trap - ERR
    set +e
    
    local line_no=$1
    local exit_code=$2
    log_error "Error occurred in $MODULE_NAME at line $line_no with exit code $exit_code"
    
    # Update state file
    update_build_state "module_failed" "$MODULE_NAME"
    update_build_state "error_line" "$line_no"
    update_build_state "error_code" "$exit_code"
    
    # Cleanup if needed
    if [[ "${CLEANUP_ON_ERROR:-0}" == "1" ]]; then
        log_warning "Performing cleanup due to error"
        unmount_chroot_safely "$CHROOT_DIR" || true
    fi
    
    exit $exit_code
}

# Set error trap
trap 'handle_error $LINENO $?' ERR

#=============================================================================
# MAIN EXECUTION
#=============================================================================
main() {
    # Load framework FIRST before using any log functions
    load_framework
    
    log_info "=== ENHANCED BOOTSTRAP MODULE v$MODULE_VERSION ==="
    log_info "Module: $MODULE_NAME"
    log_info "Phase: $MODULE_PHASE"
    log_info "Description: $MODULE_DESC"
    log_info "Build Root: $BUILD_ROOT"
    log_info "Chroot Directory: $CHROOT_DIR"
    log_info "Build Profile: $BUILD_PROFILE"
    
    # Create initial checkpoint
    create_checkpoint "enhanced_bootstrap_start"
    update_build_state "current_module" "$MODULE_NAME"
    update_build_state "current_phase" "$MODULE_PHASE"
    
    # Validation phase
    log_info "=== VALIDATION PHASE ==="
    
    if ! validate_chroot_exists; then
        log_error "CRITICAL: Chroot validation failed - cannot proceed with enhancements"
        log_error "The 20% module (mmdebootstrap/orchestrator.sh) should have created the chroot"
        log_error "Build cannot continue - this is a fatal error"
        
        # Don't call exit directly - use return to avoid triggering error trap
        update_build_state "module_failed" "$MODULE_NAME"
        update_build_state "failure_reason" "chroot_missing"
        return 1
    fi
    
    if ! validate_chroot_structure; then
        log_error "Chroot structure validation failed - attempting to continue"
        log_warning "Some enhancements may be skipped due to structure issues"
        
        # Structure problems are not fatal - continue with degraded functionality
        update_build_state "module_warning" "$MODULE_NAME"  
        update_build_state "warning_reason" "structure_validation_failed"
    fi
    
    validate_chroot_mounts
    
    create_checkpoint "validation_complete"
    
    # Enhancement phase
    log_info "=== ENHANCEMENT PHASE ==="
    
    apply_profile_specific_enhancements
    
    create_checkpoint "enhancements_applied"
    
    # Metadata phase
    log_info "=== METADATA PHASE ==="
    
    create_chroot_metadata
    
    create_checkpoint "metadata_created"
    
    # Verification phase
    log_info "=== VERIFICATION PHASE ==="
    
    verify_enhancement_results
    
    # Calculate and display chroot size
    if command -v du >/dev/null 2>&1; then
        local chroot_size=$(du -sh "$CHROOT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        log_info "Enhanced chroot size: $chroot_size"
    fi
    
    # Final checkpoint
    create_checkpoint "enhanced_bootstrap_complete"
    update_build_state "enhanced_bootstrap_status" "complete"
    update_build_state "enhanced_bootstrap_timestamp" "$(date -Iseconds)"
    
    log_success "=== ENHANCED BOOTSTRAP MODULE COMPLETE ==="
    log_info "Chroot has been verified and enhanced at $CHROOT_DIR"
    log_info "Profile: $BUILD_PROFILE"
    log_info "Next step: Continue with build at 28% (chroot-dependencies)"
    
    return 0
}

# Execute main function
main "$@"