#!/bin/bash
#
# System Configuration Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Configures system settings, users, and services
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
MODULE_NAME="system-configuration"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"

#=============================================================================
# CONFIGURATION FUNCTIONS
#=============================================================================

configure_users() {
    log_info "Configuring system users..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
# Create live user
useradd -m -s /bin/bash -G sudo,audio,video,netdev,plugdev ubuntu
echo "ubuntu:ubuntu" | chpasswd

# Configure sudoers
echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu
chmod 440 /etc/sudoers.d/ubuntu

# Set root password
echo "root:root" | chpasswd
EOF
    
    log_success "Users configured"
}

configure_networking() {
    log_info "Configuring networking..."
    
    # Network interfaces
    cat > "$CHROOT_DIR/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # NetworkManager configuration
    cat > "$CHROOT_DIR/etc/NetworkManager/NetworkManager.conf" <<'EOF'
[main]
plugins=ifupdown,keyfile
dns=default
rc-manager=resolvconf

[ifupdown]
managed=false

[keyfile]
unmanaged-devices=none
EOF
    
    log_success "Networking configured"
}

configure_systemd() {
    log_info "Configuring systemd services..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
# Set default target
systemctl set-default multi-user.target

# Enable essential services
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable ssh
systemctl enable cron

# Disable unnecessary services
systemctl disable bluetooth
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
EOF
    
    log_success "Systemd configured"
}

configure_live_system() {
    log_info "Configuring live system..."
    
    # Casper configuration
    cat > "$CHROOT_DIR/etc/casper.conf" <<'EOF'
export USERNAME="ubuntu"
export USERFULLNAME="Ubuntu Live User"
export HOST="ubuntu-live"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="Ubuntu ZFS LiveCD"
EOF
    
    # Live system hooks
    mkdir -p "$CHROOT_DIR/usr/share/initramfs-tools/hooks"
    cat > "$CHROOT_DIR/usr/share/initramfs-tools/hooks/zfs" <<'EOF'
#!/bin/sh
set -e
case $1 in
    prereqs)
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/zfs
copy_exec /sbin/zpool
copy_exec /sbin/mount.zfs

manual_add_modules zfs
EOF
    
    chmod +x "$CHROOT_DIR/usr/share/initramfs-tools/hooks/zfs"
    
    log_success "Live system configured"
}

configure_kernel_modules() {
    log_info "Configuring kernel modules..."
    
    # Modules to load at boot
    cat > "$CHROOT_DIR/etc/modules" <<'EOF'
# Network
e1000e
r8169
virtio_net

# Storage
ahci
nvme
virtio_blk
sd_mod

# Filesystem
zfs
overlay
squashfs

# USB
xhci_hcd
ehci_hcd
uhci_hcd
usb_storage

# Graphics
i915
nouveau
radeon
amdgpu
EOF
    
    log_success "Kernel modules configured"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== SYSTEM CONFIGURATION MODULE ==="
    
    # Configure system
    configure_users || exit 1
    configure_networking || exit 1
    configure_systemd || exit 1
    configure_live_system || exit 1
    configure_kernel_modules || exit 1
    
    # Install and use appropriate initrd generator
    log_info "Installing initrd generation tools..."
    
    # Mount necessary filesystems for package installation
    mount --bind /dev "$CHROOT_DIR/dev" 2>/dev/null || true
    mount --bind /proc "$CHROOT_DIR/proc" 2>/dev/null || true
    mount --bind /sys "$CHROOT_DIR/sys" 2>/dev/null || true
    # Fix resolv.conf (might be a dangling symlink)
    rm -f "$CHROOT_DIR/etc/resolv.conf"
    cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"
    
    # Try dracut first (better for ZFS LiveCD), fallback to initramfs-tools
    if chroot "$CHROOT_DIR" bash -c "apt-get update && apt-get install -y dracut-core dracut-network"; then
        log_success "Installed dracut - using modern initrd generation"
        # Generate dracut initramfs with standard modules (livenet not available in Ubuntu)
        chroot "$CHROOT_DIR" dracut --force --add "network" /boot/initrd.img-$(ls "$CHROOT_DIR/lib/modules" | head -1)
    elif chroot "$CHROOT_DIR" bash -c "apt-get install -y initramfs-tools"; then
        log_success "Installed initramfs-tools - using Ubuntu standard"
        chroot "$CHROOT_DIR" update-initramfs -u -k all
    else
        log_warning "Could not install initrd tools - creating basic initramfs"
        # Create minimal initramfs manually
        mkdir -p "$CHROOT_DIR/boot"
        echo "#!/bin/sh" > "$CHROOT_DIR/boot/initrd.img-generic"
    fi
    
    # Create checkpoint
    create_checkpoint "system_configured" "$BUILD_ROOT"
    
    log_success "=== SYSTEM CONFIGURATION COMPLETE ==="
    exit 0
}

main "$@"
