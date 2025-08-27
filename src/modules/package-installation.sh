#!/bin/bash
#
# Package Installation Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Installs all required packages and tools
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
readonly MODULE_NAME="package-installation"
readonly MODULE_VERSION="1.0.0"
readonly BUILD_ROOT="${1:-/tmp/build}"
readonly CHROOT_DIR="$BUILD_ROOT/chroot"

#=============================================================================
# PACKAGE LISTS
#=============================================================================

readonly SYSTEM_PACKAGES=(
    # Live system requirements
    "casper" "lupin-casper"
    "discover" "laptop-detect" "os-prober"
    
    # Firmware
    "linux-firmware" "amd64-microcode" "intel-microcode"
    
    # Networking tools
    "net-tools" "wireless-tools" "wpasupplicant"
    "network-manager-gnome"
    
    # System utilities
    "htop" "iotop" "sysstat" "lsof"
    "tmux" "screen" "byobu"
    
    # Recovery tools
    "testdisk" "gddrescue" "ddrescue"
    "foremost" "extundelete"
    
    # Disk utilities
    "gparted" "gnome-disk-utility"
    "mdadm" "lvm2" "cryptsetup"
)

readonly DEVELOPMENT_PACKAGES=(
    "gcc" "g++" "make" "cmake"
    "python3-dev" "python3-pip"
    "golang" "rustc" "nodejs"
    "docker.io" "containerd"
)

readonly SECURITY_PACKAGES=(
    "apparmor" "apparmor-utils"
    "fail2ban" "ufw" "iptables"
    "aide" "rkhunter" "chkrootkit"
    "clamav" "clamav-daemon"
)

#=============================================================================
# INSTALLATION FUNCTIONS
#=============================================================================

mount_chroot() {
    mount -t proc proc "$CHROOT_DIR/proc" 2>/dev/null || true
    mount -t sysfs sys "$CHROOT_DIR/sys" 2>/dev/null || true
    mount -t devtmpfs dev "$CHROOT_DIR/dev" 2>/dev/null || true
}

umount_chroot() {
    umount "$CHROOT_DIR/dev" 2>/dev/null || true
    umount "$CHROOT_DIR/sys" 2>/dev/null || true
    umount "$CHROOT_DIR/proc" 2>/dev/null || true
}

install_package_group() {
    local group_name="$1"
    shift
    local packages=("$@")
    
    log_info "Installing $group_name packages..."
    
    # Install in batches to avoid overwhelming apt
    local batch_size=5
    for ((i=0; i<${#packages[@]}; i+=batch_size)); do
        local batch=("${packages[@]:i:batch_size}")
        
        if DEBIAN_FRONTEND=noninteractive chroot "$CHROOT_DIR" \
            apt-get install -y --no-install-recommends "${batch[@]}"; then
            log_success "Installed: ${batch[*]}"
        else
            log_warning "Failed to install some packages: ${batch[*]}"
        fi
    done
}

configure_installed_packages() {
    log_info "Configuring installed packages..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
# Configure network manager
systemctl enable NetworkManager

# Configure Docker
systemctl enable docker
usermod -aG docker ubuntu 2>/dev/null || true

# Configure security services
systemctl enable apparmor
systemctl enable ufw

# Disable unnecessary services
systemctl disable apt-daily.service
systemctl disable apt-daily.timer
systemctl disable apt-daily-upgrade.timer
systemctl disable apt-daily-upgrade.service
EOF
    
    log_success "Package configuration complete"
}

clean_package_cache() {
    log_info "Cleaning package cache..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
apt-get clean
apt-get autoclean
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*
EOF
    
    log_success "Package cache cleaned"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== PACKAGE INSTALLATION MODULE ==="
    
    # Mount chroot
    mount_chroot
    
    # Update package lists
    chroot "$CHROOT_DIR" apt-get update
    
    # Install package groups
    install_package_group "System" "${SYSTEM_PACKAGES[@]}"
    install_package_group "Development" "${DEVELOPMENT_PACKAGES[@]}"
    install_package_group "Security" "${SECURITY_PACKAGES[@]}"
    
    # Configure packages
    configure_installed_packages
    
    # Clean up
    clean_package_cache
    
    # Create checkpoint
    create_checkpoint "packages_complete" "$BUILD_ROOT"
    
    # Unmount
    umount_chroot
    
    log_success "=== PACKAGE INSTALLATION COMPLETE ==="
    exit 0
}

trap umount_chroot EXIT
main "$@"
