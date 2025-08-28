#!/bin/bash
#
# ENHANCED BOOTSTRAP STAGE - 03-mmdebstrap-bootstrap.sh
# mmdebstrap-powered bootstrap stage for the build orchestrator system
#
# Features:
# - mmdebstrap bootstrap with multiple mirrors
# - Automatic fallback to debootstrap
# - Orchestrator checkpoint integration
# - Build state tracking
# - Multiple build profiles
# - ZFS and security module integration
#
# Version: 3.1.0
# Author: Build Orchestrator Integration Team
#

set -euo pipefail

# Stage configuration
STAGE_NAME="03-mmdebstrap-bootstrap"
STAGE_VERSION="3.1.0"
STAGE_DESCRIPTION="Enhanced Bootstrap with mmdebstrap"

# Environment validation
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)}"

# Logging functions
log_stage_info() {
    echo -e "\033[0;34m[STAGE-$STAGE_NAME]\033[0m $*"
}

log_stage_error() {
    echo -e "\033[0;31m[STAGE-$STAGE_NAME ERROR]\033[0m $*" >&2
}

log_stage_success() {
    echo -e "\033[0;32m[STAGE-$STAGE_NAME SUCCESS]\033[0m $*"
}

log_stage_warn() {
    echo -e "\033[1;33m[STAGE-$STAGE_NAME WARN]\033[0m $*"
}

log_stage_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "\033[0;36m[STAGE-$STAGE_NAME DEBUG]\033[0m $*"
    fi
}

# Load orchestrator framework
load_orchestrator_framework() {
    local framework_script="${PROJECT_ROOT}/common_module_functions.sh"
    
    if [[ -f "$framework_script" ]]; then
        source "$framework_script"
        log_stage_info "✓ Orchestrator framework loaded"
        export ORCHESTRATOR_FRAMEWORK_LOADED=1
        return 0
    else
        log_stage_warn "Orchestrator framework not found at: $framework_script"
        log_stage_warn "Running in standalone mode with limited functionality"
        export ORCHESTRATOR_FRAMEWORK_LOADED=0
        return 1
    fi
}

# Load mmdebstrap orchestrator module
load_mmdebstrap_module() {
    local module_script="${PROJECT_ROOT}/src/modules/mmdebstrap/orchestrator.sh"
    
    if [[ -f "$module_script" ]]; then
        source "$module_script"
        log_stage_info "✓ mmdebstrap orchestrator module loaded"
        export MMDEBSTRAP_MODULE_LOADED=1
        return 0
    else
        log_stage_error "mmdebstrap orchestrator module not found at: $module_script"
        log_stage_error "Please run the integration setup script first"
        log_stage_error "Expected file: $module_script"
        return 1
    fi
}

# Validate stage environment
validate_stage_environment() {
    log_stage_info "Validating stage environment"
    
    # Required environment variables
    local required_vars=(
        "CHROOT_DIR"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_stage_error "Required environment variables not set:"
        printf '  %s\n' "${missing_vars[@]}"
        log_stage_error "Set these variables before running this stage"
        return 1
    fi
    
    # Validate chroot directory parent exists
    if [[ ! -d "$(dirname "$CHROOT_DIR")" ]]; then
        log_stage_error "Chroot parent directory does not exist: $(dirname "$CHROOT_DIR")"
        return 1
    fi
    
    # Set defaults for optional variables
    export BUILD_SUITE="${BUILD_SUITE:-noble}"
    export BUILD_ARCH="${BUILD_ARCH:-amd64}"
    export BUILD_PROFILE="${BUILD_PROFILE:-standard}"
    
    log_stage_info "Environment validation completed"
    log_stage_info "Target: $CHROOT_DIR"
    log_stage_info "Suite: $BUILD_SUITE"
    log_stage_info "Architecture: $BUILD_ARCH"
    log_stage_info "Profile: $BUILD_PROFILE"
    
    return 0
}

# Create orchestrator checkpoint
create_stage_checkpoint() {
    local checkpoint_name="$1"
    local description="$2"
    
    if [[ "$ORCHESTRATOR_FRAMEWORK_LOADED" == "1" ]] && command -v create_checkpoint >/dev/null 2>&1; then
        create_checkpoint "$checkpoint_name" "$CHROOT_DIR" "$description"
        log_stage_debug "Checkpoint created: $checkpoint_name"
    else
        log_stage_debug "Checkpoint skipped (framework not loaded): $checkpoint_name"
    fi
}

# Enhanced bootstrap execution
execute_enhanced_bootstrap() {
    log_stage_info "Starting enhanced bootstrap execution"
    
    # Pre-bootstrap checkpoint
    create_stage_checkpoint "bootstrap_start" "Enhanced bootstrap stage started"
    
    # CHROOT SHOULD ALREADY EXIST - Created at 20% by mmdebootstrap/orchestrator
    if [[ ! -d "$CHROOT_DIR" ]]; then
        log_stage_error "Chroot directory does not exist: $CHROOT_DIR"
        log_stage_error "The chroot should have been created at 20% by mmdebootstrap/orchestrator module"
        create_stage_checkpoint "chroot_missing" "Chroot directory not found"
        return 1
    fi
    
    # Verify chroot structure
    log_stage_info "Verifying existing chroot structure at $CHROOT_DIR"
    
    if [[ ! -d "$CHROOT_DIR/usr" ]] || [[ ! -d "$CHROOT_DIR/bin" ]] || [[ ! -d "$CHROOT_DIR/etc" ]]; then
        log_stage_error "Chroot structure incomplete - missing critical directories"
        create_stage_checkpoint "chroot_invalid" "Chroot structure incomplete"
        return 1
    fi
    
    # Check for mmdebstrap marker
    if [[ -f "$CHROOT_DIR/.mmdebstrap-complete" ]]; then
        log_stage_success "Found mmdebstrap completion marker"
        log_stage_info "Chroot was created at: $(cat "$CHROOT_DIR/.mmdebstrap-timestamp" 2>/dev/null || echo "unknown")"
    else
        log_stage_warn "No mmdebstrap completion marker found, but chroot exists"
    fi
    
    log_stage_success "Chroot verification passed - proceeding with enhancements"
    create_stage_checkpoint "chroot_verified" "Existing chroot verified"
    
    # Post-bootstrap validation
    log_stage_info "Validating bootstrap result"
    
    if validate_bootstrap "$CHROOT_DIR"; then
        log_stage_success "Bootstrap validation passed"
        create_stage_checkpoint "bootstrap_validated" "Bootstrap validation completed"
    else
        log_stage_error "Bootstrap validation failed"
        return 1
    fi
    
    # Stage-specific post-processing
    execute_stage_post_processing
    
    # Final checkpoint
    create_stage_checkpoint "stage_complete" "Enhanced bootstrap stage completed successfully"
    
    log_stage_success "Enhanced bootstrap stage completed successfully"
    return 0
}

# Stage-specific post-processing
execute_stage_post_processing() {
    log_stage_info "Executing stage-specific post-processing"
    
    # Profile-specific configurations
    case "$BUILD_PROFILE" in
        "development")
            configure_development_profile
            ;;
        "zfs_optimized")
            configure_zfs_profile
            ;;
        "security")
            configure_security_profile
            ;;
        "minimal")
            configure_minimal_profile
            ;;
        *)
            log_stage_debug "No specific post-processing for profile: $BUILD_PROFILE"
            ;;
    esac
    
    # Generic post-processing
    configure_generic_system
    
    log_stage_info "Stage-specific post-processing completed"
}

# Development profile configuration
configure_development_profile() {
    log_stage_debug "Configuring development profile"
    
    # Create development directories
    mkdir -p "$CHROOT_DIR"/{home/developer,opt/development,var/log/development}
    
    # Set up development environment variables
    cat > "$CHROOT_DIR/etc/environment" << EOF
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/development/bin"
EDITOR="nano"
DEVELOPMENT_MODE="true"
EOF
    
    # Create development user setup script
    cat > "$CHROOT_DIR/usr/local/bin/setup-developer" << 'DEVELOPER_SETUP_EOF'
#!/bin/bash
# Development environment setup script
if ! id -u developer >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo developer
    echo "developer:developer" | chpasswd
    echo "Developer user created with password 'developer'"
fi
DEVELOPER_SETUP_EOF
    
    chmod +x "$CHROOT_DIR/usr/local/bin/setup-developer"
    
    log_stage_debug "Development profile configuration completed"
}

# ZFS profile configuration
configure_zfs_profile() {
    log_stage_debug "Configuring ZFS optimized profile"
    
    # Create ZFS configuration directory
    mkdir -p "$CHROOT_DIR/etc/zfs"
    
    # Basic ZFS module configuration
    cat > "$CHROOT_DIR/etc/modules-load.d/zfs.conf" << EOF
# ZFS modules
zfs
EOF
    
    # ZFS service enablement script
    cat > "$CHROOT_DIR/usr/local/bin/enable-zfs-services" << 'ZFS_SERVICES_EOF'
#!/bin/bash
# Enable ZFS services
systemctl enable zfs-import-cache.service
systemctl enable zfs-mount.service
systemctl enable zfs-share.service
systemctl enable zfs.target
echo "ZFS services enabled"
ZFS_SERVICES_EOF
    
    chmod +x "$CHROOT_DIR/usr/local/bin/enable-zfs-services"
    
    # Create ZFS monitoring directory
    mkdir -p "$CHROOT_DIR/var/log/zfs"
    
    log_stage_debug "ZFS optimized profile configuration completed"
}

# Security profile configuration
configure_security_profile() {
    log_stage_debug "Configuring security profile"
    
    # Create security configuration directories
    mkdir -p "$CHROOT_DIR"/{etc/security,var/log/security}
    
    # Basic security limits
    cat > "$CHROOT_DIR/etc/security/limits.conf" << EOF
# Security limits configuration
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
root soft nofile 65536
root hard nofile 65536
EOF
    
    # SSH hardening configuration
    if [[ -d "$CHROOT_DIR/etc/ssh" ]]; then
        cat >> "$CHROOT_DIR/etc/ssh/sshd_config" << EOF

# Security hardening
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
MaxAuthTries 3
LoginGraceTime 60
MaxStartups 10:30:60
EOF
    fi
    
    # Security setup script
    cat > "$CHROOT_DIR/usr/local/bin/configure-security" << 'SECURITY_SETUP_EOF'
#!/bin/bash
# Security configuration script
echo "Configuring firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh

echo "Configuring fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

echo "Security configuration completed"
SECURITY_SETUP_EOF
    
    chmod +x "$CHROOT_DIR/usr/local/bin/configure-security"
    
    log_stage_debug "Security profile configuration completed"
}

# Minimal profile configuration
configure_minimal_profile() {
    log_stage_debug "Configuring minimal profile"
    
    # Clean up unnecessary files for minimal system
    rm -rf "$CHROOT_DIR"/{usr/share/doc,usr/share/man,var/cache/apt/archives} 2>/dev/null || true
    
    # Create minimal system marker
    echo "MINIMAL_SYSTEM=true" > "$CHROOT_DIR/etc/system-profile"
    
    log_stage_debug "Minimal profile configuration completed"
}

# Generic system configuration
configure_generic_system() {
    log_stage_debug "Applying generic system configuration"
    
    # Set system timezone
    if [[ -f "/etc/timezone" ]] && [[ -f "/usr/share/zoneinfo/$(cat /etc/timezone)" ]]; then
        cp "/etc/timezone" "$CHROOT_DIR/etc/timezone"
        ln -sf "/usr/share/zoneinfo/$(cat /etc/timezone)" "$CHROOT_DIR/etc/localtime"
        log_stage_debug "Timezone configured from host system"
    fi
    
    # Configure DNS
    cat > "$CHROOT_DIR/etc/resolv.conf" << EOF
# DNS configuration
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    
    # Set up basic networking
    cat > "$CHROOT_DIR/etc/systemd/network/20-wired.network" << EOF
[Match]
Name=en*

[Network]
DHCP=yes
EOF
    
    # Create system information file
    cat > "$CHROOT_DIR/etc/build-info" << EOF
# Build Information
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
BUILD_STAGE=$STAGE_NAME
BUILD_VERSION=$STAGE_VERSION
BUILD_SUITE=$BUILD_SUITE
BUILD_ARCH=$BUILD_ARCH
BUILD_PROFILE=$BUILD_PROFILE
BOOTSTRAP_METHOD=mmdebstrap
PROJECT_ROOT=$PROJECT_ROOT
EOF
    
    log_stage_debug "Generic system configuration completed"
}

# Error handling
handle_stage_error() {
    local exit_code=$?
    log_stage_error "Stage failed with exit code: $exit_code"
    create_stage_checkpoint "stage_failed" "Enhanced bootstrap stage failed"
    
    # Cleanup on failure if requested
    if [[ "${CLEANUP_ON_FAILURE:-1}" == "1" ]] && [[ -d "$CHROOT_DIR" ]]; then
        log_stage_warn "Cleaning up failed bootstrap directory: $CHROOT_DIR"
        rm -rf "$CHROOT_DIR"
    fi
    
    exit $exit_code
}

# Set error trap
trap 'handle_stage_error' ERR

# Stage status reporting
report_stage_status() {
    local status="$1"
    local message="$2"
    
    echo "STAGE_STATUS=$status" > "${CHROOT_DIR:-/tmp}/stage-status"
    echo "STAGE_MESSAGE=$message" >> "${CHROOT_DIR:-/tmp}/stage-status"
    echo "STAGE_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> "${CHROOT_DIR:-/tmp}/stage-status"
    
    log_stage_info "Stage status: $status - $message"
}

# Main stage execution
main() {
    log_stage_info "=== Enhanced Bootstrap Stage v$STAGE_VERSION ==="
    log_stage_info "Stage: $STAGE_NAME"
    log_stage_info "Description: $STAGE_DESCRIPTION"
    log_stage_info "Project Root: $PROJECT_ROOT"
    
    report_stage_status "STARTING" "Enhanced bootstrap stage initialization"
    
    # Load framework and modules
    load_orchestrator_framework || log_stage_warn "Framework loading failed - continuing"
    
    if ! load_mmdebstrap_module; then
        report_stage_status "FAILED" "mmdebstrap module loading failed"
        exit 1
    fi
    
    # Validate environment
    if ! validate_stage_environment; then
        report_stage_status "FAILED" "Environment validation failed"
        exit 1
    fi
    
    report_stage_status "RUNNING" "Executing enhanced bootstrap"
    
    # Execute main bootstrap process
    if execute_enhanced_bootstrap; then
        report_stage_status "COMPLETED" "Enhanced bootstrap stage completed successfully"
        log_stage_success "=== Stage Completed Successfully ==="
    else
        report_stage_status "FAILED" "Enhanced bootstrap execution failed"
        exit 1
    fi
    
    # Final status report
    log_stage_info "Final chroot directory size: $(du -sh "$CHROOT_DIR" 2>/dev/null | cut -f1 || echo "unknown")"
    log_stage_info "Bootstrap method: mmdebstrap"
    log_stage_info "Build profile: $BUILD_PROFILE"
    
    return 0
}

# Stage information display
show_stage_info() {
    cat << EOF
Enhanced Bootstrap Stage Information

Stage Name: $STAGE_NAME
Version: $STAGE_VERSION
Description: $STAGE_DESCRIPTION

Features:
- mmdebstrap-powered bootstrap (2-3x faster than debootstrap)
- Multiple build profiles (minimal, standard, development, zfs_optimized, security)
- Automatic fallback to debootstrap
- Orchestrator framework integration
- Build state checkpointing
- Profile-specific post-processing
- Comprehensive validation

Required Environment Variables:
- CHROOT_DIR: Target chroot directory path

Optional Environment Variables:
- BUILD_SUITE: Ubuntu/Debian suite (default: noble)
- BUILD_ARCH: Target architecture (default: amd64)
- BUILD_PROFILE: Build profile (default: standard)
- PROJECT_ROOT: Project root directory (auto-detected)
- DEBUG: Enable debug output (0/1)
- CLEANUP_ON_FAILURE: Clean up on failure (default: 1)

Usage:
export CHROOT_DIR="/path/to/chroot"
export BUILD_SUITE="noble"
export BUILD_PROFILE="development"
$0

Integration:
This stage integrates with the build orchestrator framework and requires
the mmdebstrap orchestrator module to be installed.

For installation: run setup-mmdebstrap-integration.sh
EOF
}

# Command line handling
case "${1:-}" in
    "--info"|"-i")
        show_stage_info
        exit 0
        ;;
    "--help"|"-h")
        show_stage_info
        exit 0
        ;;
    "")
        # Execute main stage
        main
        ;;
    *)
        log_stage_error "Unknown option: $1"
        show_stage_info
        exit 1
        ;;
esac