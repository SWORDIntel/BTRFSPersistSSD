#!/bin/bash
#
# Boot Configuration Module (ISO Creation Phase)
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Configures chroot for ISO creation with proper casper/live boot support
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
MODULE_NAME="boot-configuration"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"

#=============================================================================
# ISO BOOT CONFIGURATION FUNCTIONS
#=============================================================================

install_live_boot_packages() {
    log_info "Installing live boot packages..."
    
    # Mount required filesystems for package installation
    mount --bind /dev "$CHROOT_DIR/dev" 2>/dev/null || true
    mount --bind /proc "$CHROOT_DIR/proc" 2>/dev/null || true
    mount --bind /sys "$CHROOT_DIR/sys" 2>/dev/null || true
    
    # Fix DNS for package installation
    cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf" 2>/dev/null || true
    
    chroot "$CHROOT_DIR" bash << 'PACKAGES'
export DEBIAN_FRONTEND=noninteractive

# Install essential live boot packages
apt-get update
apt-get install -y \
    casper \
    lupin-casper \
    discover \
    laptop-detect \
    os-prober \
    network-manager \
    resolvconf \
    net-tools \
    wireless-tools \
    wpagui \
    locales \
    linux-generic \
    grub-pc-bin \
    grub-efi-amd64-bin \
    isolinux \
    memtest86+ \
    squashfs-tools

# Install bootloader packages
apt-get install -y \
    grub-efi-amd64 \
    grub-efi-amd64-signed \
    grub-pc \
    shim-signed

# Install BTRFS tools - VITAL for persistence
apt-get install -y btrfs-progs

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*
PACKAGES

    log_success "Live boot packages installed"
}

configure_casper() {
    log_info "Configuring Casper live boot system..."
    
    # Create casper configuration
    cat > "$CHROOT_DIR/etc/casper.conf" << 'EOF'
export USERNAME="ubuntu"
export USERFULLNAME="Ubuntu Live User"
export HOST="ubuntu-live"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="Ubuntu BTRFS Persistent LiveCD"
EOF
    
    # Configure live user
    chroot "$CHROOT_DIR" bash << 'USER_CONFIG'
# Create live user if it doesn't exist
if ! id ubuntu >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,netdev,plugdev,users ubuntu
    echo "ubuntu:ubuntu" | chpasswd
fi

# Configure automatic login
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ubuntu --noclear %I $TERM
AUTOLOGIN

# Configure sudo
echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu
chmod 440 /etc/sudoers.d/ubuntu
USER_CONFIG
    
    log_success "Casper configured"
}

configure_live_services() {
    log_info "Configuring services for live boot..."
    
    chroot "$CHROOT_DIR" bash << 'SERVICES'
# Enable essential services for live system
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable NetworkManager
systemctl enable casper
systemctl enable rsyslog

# Disable problematic services for live boot
systemctl disable apt-daily.service
systemctl disable apt-daily.timer
systemctl disable apt-daily-upgrade.service
systemctl disable apt-daily-upgrade.timer
systemctl disable systemd-timesyncd
systemctl disable udisks2
systemctl disable accounts-daemon

# Mask power management that conflicts with live boot
systemctl mask sleep.target
systemctl mask suspend.target
systemctl mask hibernate.target
systemctl mask hybrid-sleep.target
SERVICES

    log_success "Live services configured"
}

configure_live_filesystem() {
    log_info "Configuring live filesystem settings..."
    
    # Configure fstab for live system
    cat > "$CHROOT_DIR/etc/fstab" << 'EOF'
# Live system fstab - minimal entries
tmpfs /tmp tmpfs nodev,nosuid,size=20% 0 0
tmpfs /var/tmp tmpfs nodev,nosuid,size=20% 0 0
EOF

    # Configure filesystem modules
    cat > "$CHROOT_DIR/etc/modules-load.d/live-filesystem.conf" << 'EOF'
# Filesystem modules for live boot
overlay
squashfs
isofs
btrfs
zfs
loop
EOF

    # Configure kernel parameters for live boot
    mkdir -p "$CHROOT_DIR/etc/sysctl.d"
    cat > "$CHROOT_DIR/etc/sysctl.d/99-live-system.conf" << 'EOF'
# Live system optimizations
vm.swappiness=10
vm.vfs_cache_pressure=50
kernel.sysrq=1
EOF

    log_success "Live filesystem configured"
}

setup_persistence_detection() {
    log_info "Setting up persistence detection..."
    
    # Create persistence detection script
    cat > "$CHROOT_DIR/usr/local/bin/detect-persistence" << 'EOF'
#!/bin/bash
#
# Persistence Detection Script for BTRFS LiveCD
#

# Look for BTRFS persistence partitions
for device in /dev/sd* /dev/nvme* /dev/vd*; do
    if [ -b "$device" ]; then
        # Check if it's a BTRFS filesystem with persistence markers
        if blkid -t TYPE=btrfs "$device" >/dev/null 2>&1; then
            # Mount temporarily to check for persistence
            mkdir -p /tmp/check-persist 2>/dev/null
            if mount -t btrfs "$device" /tmp/check-persist 2>/dev/null; then
                if [ -d /tmp/check-persist/casper-rw ] || [ -f /tmp/check-persist/casper-uuid-* ]; then
                    echo "BTRFS persistence found on $device"
                    echo "$device" > /tmp/persistence-device
                    umount /tmp/check-persist 2>/dev/null
                    exit 0
                fi
                umount /tmp/check-persist 2>/dev/null
            fi
        fi
    fi
done

echo "No BTRFS persistence found"
exit 1
EOF
    
    chmod +x "$CHROOT_DIR/usr/local/bin/detect-persistence"
    
    # Create systemd service for persistence detection
    cat > "$CHROOT_DIR/etc/systemd/system/detect-persistence.service" << 'EOF'
[Unit]
Description=Detect BTRFS Persistence
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/detect-persistence
RemainAfterExit=yes
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF
    
    chroot "$CHROOT_DIR" systemctl enable detect-persistence.service 2>/dev/null || true
    
    log_success "Persistence detection configured"
}

cleanup_for_iso() {
    log_info "Cleaning up chroot for ISO creation..."
    
    chroot "$CHROOT_DIR" bash << 'CLEANUP'
# Clean package cache
apt-get clean
rm -rf /var/cache/apt/archives/*.deb

# Clean temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clean logs but keep structure
find /var/log -type f -exec truncate -s 0 {} \;

# Clean systemd machine-id (will be regenerated on boot)
rm -f /etc/machine-id /var/lib/dbus/machine-id
touch /etc/machine-id

# Clean network configuration
rm -f /etc/udev/rules.d/70-persistent-net.rules

# Clean SSH host keys (will be regenerated)
rm -f /etc/ssh/ssh_host_*

# Clean user history
rm -f /root/.bash_history
rm -f /home/ubuntu/.bash_history 2>/dev/null || true
CLEANUP

    # Unmount bind mounts
    umount "$CHROOT_DIR/sys" 2>/dev/null || true
    umount "$CHROOT_DIR/proc" 2>/dev/null || true
    umount "$CHROOT_DIR/dev" 2>/dev/null || true
    
    log_success "Chroot cleaned for ISO creation"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== BOOT CONFIGURATION MODULE v$MODULE_VERSION ==="
    log_info "Configuring chroot for ISO creation with BTRFS persistence"
    
    # Check prerequisites
    [[ -d "$CHROOT_DIR" ]] || {
        log_error "Chroot directory not found: $CHROOT_DIR"
        return 1
    }
    
    # Install required packages
    install_live_boot_packages || return 1
    
    # Configure live boot system
    configure_casper || return 1
    configure_live_services || return 1
    configure_live_filesystem || return 1
    setup_persistence_detection || return 1
    
    # Clean up for ISO creation
    cleanup_for_iso || return 1
    
    # Create checkpoint
    create_checkpoint "boot_configured" "$BUILD_ROOT"
    
    log_success "=== BOOT CONFIGURATION COMPLETE ==="
    log_success "Chroot configured for:"
    log_success "  ✓ Casper live boot system"
    log_success "  ✓ BTRFS persistence detection"
    log_success "  ✓ Automatic ubuntu user login"
    log_success "  ✓ NetworkManager networking"
    log_success "  ✓ Live system optimizations"
    log_success "  ✓ Clean state for ISO creation"
    
    exit 0
}

# Execute main function
main "$@"