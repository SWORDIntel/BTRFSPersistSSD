#!/bin/bash
#
# Configuration Apply Module
# Version: 1.0.0
# Part of: LiveCD Build System
#
# Applies authoritative configuration files to the system
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
MODULE_NAME="config-apply"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"
CONFIG_DIR="$REPO_ROOT/src/config"

# Target system type (host or chroot)
TARGET="${2:-chroot}"

#=============================================================================
# CONFIGURATION FUNCTIONS
#=============================================================================

apply_sources_list() {
    local target_dir="$1"
    local ubuntu_version="$2"
    
    log_info "Applying authoritative sources.list configuration..."
    
    # Backup existing sources.list
    if [[ -f "$target_dir/etc/apt/sources.list" ]]; then
        cp "$target_dir/etc/apt/sources.list" "$target_dir/etc/apt/sources.list.backup.$(date +%Y%m%d)"
        log_info "Backed up existing sources.list"
    fi
    
    # CRITICAL: Handle Ubuntu 24.04+ DEB822 format
    # Ubuntu 24.04 uses /etc/apt/sources.list.d/ubuntu.sources which conflicts
    if [[ -f "$target_dir/etc/apt/sources.list.d/ubuntu.sources" ]]; then
        log_warninging "Found Ubuntu DEB822 format sources file, disabling it"
        mv "$target_dir/etc/apt/sources.list.d/ubuntu.sources" \
           "$target_dir/etc/apt/sources.list.d/ubuntu.sources.disabled" 2>/dev/null || true
        log_info "Disabled ubuntu.sources to prevent conflicts"
    fi
    
    # Determine which sources.list to use
    local sources_file="$CONFIG_DIR/sources.list"
    
    if [[ "$ubuntu_version" == "22.04" ]] || [[ "$ubuntu_version" == "jammy" ]]; then
        sources_file="$CONFIG_DIR/sources.list.jammy"
        log_info "Using Jammy (22.04) sources.list"
    elif [[ "$ubuntu_version" == "24.04" ]] || [[ "$ubuntu_version" == "noble" ]]; then
        sources_file="$CONFIG_DIR/sources.list"
        log_info "Using Noble (24.04) sources.list"
    else
        log_warninging "Unknown Ubuntu version: $ubuntu_version, using default Noble sources"
    fi
    
    # Copy authoritative sources.list
    cp "$sources_file" "$target_dir/etc/apt/sources.list"
    
    # Remove any sources.list.d files that might conflict
    if [[ -d "$target_dir/etc/apt/sources.list.d" ]]; then
        # Backup sources.list.d
        tar -czf "$target_dir/etc/apt/sources.list.d.backup.$(date +%Y%m%d).tar.gz" \
            -C "$target_dir/etc/apt" sources.list.d 2>/dev/null || true
        
        # Remove/disable conflicting sources
        rm -f "$target_dir/etc/apt/sources.list.d/"*cdrom*.list 2>/dev/null || true
        
        # Disable all .sources files (DEB822 format) to prevent conflicts
        for sourcefile in "$target_dir/etc/apt/sources.list.d/"*.sources; do
            if [[ -f "$sourcefile" ]]; then
                mv "$sourcefile" "${sourcefile}.disabled" 2>/dev/null || true
                log_info "Disabled: $(basename "$sourcefile")"
            fi
        done
        
        # Clear any duplicate PPAs
        for listfile in "$target_dir/etc/apt/sources.list.d/"*.list; do
            if [[ -f "$listfile" ]] && grep -q "^deb.*archive.ubuntu.com.*noble main" "$listfile" 2>/dev/null; then
                mv "$listfile" "${listfile}.disabled" 2>/dev/null || true
                log_info "Disabled duplicate: $(basename "$listfile")"
            fi
        done
        
        log_info "Cleaned sources.list.d directory"
    fi
    
    log_success "Applied authoritative sources.list configuration"
}

apply_resolv_conf() {
    local target_dir="$1"
    
    log_info "Applying authoritative DNS configuration..."
    
    # Check if systemd-resolved is being used
    local use_systemd_resolved=false
    
    if [[ "$TARGET" == "chroot" ]]; then
        if [[ -L "$target_dir/etc/resolv.conf" ]] && \
           [[ "$(readlink "$target_dir/etc/resolv.conf")" == *"systemd"* ]]; then
            use_systemd_resolved=true
        fi
    else
        if systemctl is-active --quiet systemd-resolved; then
            use_systemd_resolved=true
        fi
    fi
    
    if [[ "$use_systemd_resolved" == "true" ]]; then
        log_info "System uses systemd-resolved, applying systemd configuration"
        
        # Apply systemd-resolved configuration
        mkdir -p "$target_dir/etc/systemd"
        cp "$CONFIG_DIR/resolv.conf.systemd" "$target_dir/etc/systemd/resolved.conf"
        
        # Ensure resolv.conf is properly linked
        if [[ ! -L "$target_dir/etc/resolv.conf" ]]; then
            mv "$target_dir/etc/resolv.conf" "$target_dir/etc/resolv.conf.backup.$(date +%Y%m%d)" 2>/dev/null || true
            ln -sf /run/systemd/resolve/stub-resolv.conf "$target_dir/etc/resolv.conf"
        fi
        
        # Restart systemd-resolved if on host
        if [[ "$TARGET" == "host" ]]; then
            systemctl restart systemd-resolved || true
        fi
    else
        log_info "Using traditional resolv.conf"
        
        # Backup existing resolv.conf
        if [[ -f "$target_dir/etc/resolv.conf" ]]; then
            cp "$target_dir/etc/resolv.conf" "$target_dir/etc/resolv.conf.backup.$(date +%Y%m%d)"
            log_info "Backed up existing resolv.conf"
        fi
        
        # Remove symlink if it exists
        if [[ -L "$target_dir/etc/resolv.conf" ]]; then
            rm -f "$target_dir/etc/resolv.conf"
        fi
        
        # Copy authoritative resolv.conf
        cp "$CONFIG_DIR/resolv.conf" "$target_dir/etc/resolv.conf"
        
        # Make it immutable to prevent NetworkManager from changing it
        if [[ "$TARGET" == "host" ]]; then
            chattr +i "$target_dir/etc/resolv.conf" 2>/dev/null || true
        fi
    fi
    
    log_success "Applied authoritative DNS configuration"
}

verify_network_connectivity() {
    local target_dir="$1"
    
    log_info "Verifying network connectivity..."
    
    # Test DNS resolution
    local test_domains=("google.com" "ubuntu.com" "github.com")
    local dns_working=false
    
    for domain in "${test_domains[@]}"; do
        if [[ "$TARGET" == "chroot" ]]; then
            if chroot "$target_dir" /bin/bash -c "nslookup $domain >/dev/null 2>&1" || \
               chroot "$target_dir" /bin/bash -c "host $domain >/dev/null 2>&1" || \
               chroot "$target_dir" /bin/bash -c "getent hosts $domain >/dev/null 2>&1"; then
                dns_working=true
                log_success "DNS resolution working: $domain"
                break
            fi
        else
            if nslookup "$domain" >/dev/null 2>&1 || host "$domain" >/dev/null 2>&1; then
                dns_working=true
                log_success "DNS resolution working: $domain"
                break
            fi
        fi
    done
    
    if [[ "$dns_working" == "false" ]]; then
        log_warning "DNS resolution might not be working properly"
        log_info "This could be normal in a chroot environment"
    fi
    
    # Test package repository access
    if [[ "$TARGET" == "chroot" ]]; then
        if chroot "$target_dir" /bin/bash -c "apt-get update -qq" 2>/dev/null; then
            log_success "Package repositories accessible"
        else
            log_warning "Could not update package lists (might be normal in chroot)"
        fi
    else
        if apt-get update -qq 2>/dev/null; then
            log_success "Package repositories accessible"
        else
            log_error "Could not access package repositories"
        fi
    fi
}

apply_apt_configuration() {
    local target_dir="$1"
    
    log_info "Applying APT configuration optimizations..."
    
    # Create APT configuration for better performance and no authentication
    cat > "$target_dir/etc/apt/apt.conf.d/99-optimize" << 'EOF'
# APT Optimizations for Build System - No Authentication
Acquire::http::Pipeline-Depth "10";
Acquire::Languages "none";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Get::Assume-Yes "true";
APT::Get::AllowUnauthenticated "true";
APT::Get::Allow-Insecure-Repositories "true";
APT::Get::Allow-Downgrades "true";
APT::Authentication::TrustCDROM "false";
Acquire::AllowInsecureRepositories "true";
Acquire::Check-Valid-Until "false";
DPkg::Options::="--force-unsafe-io";
DPkg::Options::="--force-confold";
DPkg::Options::="--force-confdef";
DPkg::Options::="--force-bad-verify";
Dir::Cache::Archives "/var/cache/apt/archives";

# Parallel downloads (for APT 2.3+)
Acquire::Queue-Mode "access";
Acquire::Retries "3";

# Disable all signature checks
APT::Update::Post-Invoke-Success "";
Debug::Acquire::gpgv "true";
EOF
    
    # Create preferences to prioritize certain repositories
    cat > "$target_dir/etc/apt/preferences.d/99-build-system" << 'EOF'
# Package priorities for build system
Package: *
Pin: release a=noble-security
Pin-Priority: 1000

Package: *
Pin: release a=noble-updates
Pin-Priority: 900

Package: *
Pin: release a=noble
Pin-Priority: 800
EOF
    
    log_success "Applied APT configuration optimizations"
}

detect_ubuntu_version() {
    local target_dir="$1"
    local version="24.04"  # Default to Noble
    
    if [[ -f "$target_dir/etc/os-release" ]]; then
        version=$(grep "VERSION_ID" "$target_dir/etc/os-release" | cut -d'"' -f2)
        log_info "Detected Ubuntu version: $version"
    elif [[ -f "$target_dir/etc/lsb-release" ]]; then
        version=$(grep "DISTRIB_RELEASE" "$target_dir/etc/lsb-release" | cut -d'=' -f2)
        log_info "Detected Ubuntu version: $version"
    else
        log_warning "Could not detect Ubuntu version, assuming 24.04 (Noble)"
    fi
    
    echo "$version"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== CONFIGURATION APPLY MODULE v$MODULE_VERSION ==="
    log_info "Applying authoritative configurations to $TARGET environment"
    
    # Determine target directory
    local target_dir=""
    
    if [[ "$TARGET" == "host" ]]; then
        target_dir=""
        log_info "Applying configurations to host system"
    elif [[ "$TARGET" == "chroot" ]]; then
        target_dir="$CHROOT_DIR"
        log_info "Applying configurations to chroot: $CHROOT_DIR"
        
        # Verify chroot exists
        if [[ ! -d "$CHROOT_DIR" ]]; then
            log_error "Chroot directory not found: $CHROOT_DIR"
            exit 1
        fi
    else
        log_error "Unknown target: $TARGET (must be 'host' or 'chroot')"
        exit 1
    fi
    
    # Detect Ubuntu version
    local ubuntu_version=$(detect_ubuntu_version "$target_dir")
    
    # Apply configurations in order
    apply_sources_list "$target_dir" "$ubuntu_version"
    apply_resolv_conf "$target_dir"
    apply_apt_configuration "$target_dir"
    
    # Verify network connectivity
    verify_network_connectivity "$target_dir"
    
    # Update package lists with new sources (ignore 404s from partner repos)
    if [[ "$TARGET" == "host" ]]; then
        log_info "Updating package lists..."
        apt-get update --allow-unauthenticated --allow-insecure-repositories 2>&1 | grep -v "404  Not Found" || {
            if apt-cache policy | grep -q "archive.ubuntu.com"; then
                log_warning "Some repositories failed but main repos are available"
            else
                log_warning "Failed to update package lists"
            fi
        }
    elif [[ "$TARGET" == "chroot" ]]; then
        log_info "Updating package lists in chroot..."
        chroot "$CHROOT_DIR" apt-get update --allow-unauthenticated --allow-insecure-repositories 2>&1 | grep -v "404  Not Found" || {
            if chroot "$CHROOT_DIR" apt-cache policy | grep -q "archive.ubuntu.com"; then
                log_warning "Some repositories failed but main repos are available"
            else
                log_warning "Failed to update package lists in chroot"
            fi
        }
    fi
    
    # Create marker file
    local marker_file
    if [[ "$TARGET" == "host" ]]; then
        marker_file="/var/lib/config-applied.marker"
    else
        marker_file="$CHROOT_DIR/var/lib/config-applied.marker"
    fi
    
    cat > "$marker_file" << EOF
Configuration Applied: $(date -Iseconds)
Module Version: $MODULE_VERSION
Target: $TARGET
Ubuntu Version: $ubuntu_version
Sources List: Applied
DNS Configuration: Applied
APT Optimizations: Applied
EOF
    
    log_success "=== CONFIGURATION APPLY COMPLETE ==="
    log_success "System now using authoritative configurations"
    log_success "Sources: All Ubuntu repositories enabled"
    log_success "DNS: Multiple providers for redundancy"
    log_success "APT: Optimized for build performance"
    
    exit 0
}

# Execute main function
main "$@"