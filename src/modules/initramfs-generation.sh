#!/bin/bash
#
# Initramfs Generation Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Generates initramfs with ZFS and live boot support
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
MODULE_NAME="initramfs-generation"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"
WORK_DIR="$BUILD_ROOT/work"

#=============================================================================
# INITRAMFS FUNCTIONS
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

configure_initramfs() {
    log_info "Configuring initramfs settings..."
    
    # Initramfs configuration
    cat > "$CHROOT_DIR/etc/initramfs-tools/initramfs.conf" <<'EOF'
MODULES=most
BUSYBOX=auto
KEYMAP=n
COMPRESS=lz4
DEVICE=
NFSROOT=auto
RUNSIZE=10%
FSTYPE=auto
EOF
    
    # Update modules
    cat > "$CHROOT_DIR/etc/initramfs-tools/modules" <<'EOF'
# Storage drivers
ahci
nvme
virtio_blk
sd_mod

# Filesystem - BTRFS is VITAL for persistence
btrfs
zfs
overlay
squashfs
isofs
vfat
ext4
ext3
ext2

# Network (for network boot)
e1000e
r8169
virtio_net

# USB
xhci_pci
ehci_pci
uhci_hcd
usb_storage

# Live boot essentials
loop
dm_mod
dm_snapshot
EOF
    
    log_success "Initramfs configured"
}

create_live_scripts() {
    log_info "Creating live boot scripts..."
    
    # Create custom live boot script
    mkdir -p "$CHROOT_DIR/etc/initramfs-tools/scripts/casper-bottom"
    
    cat > "$CHROOT_DIR/etc/initramfs-tools/scripts/casper-bottom/10_zfs_live" <<'EOF'
#!/bin/sh

PREREQ=""
prereqs()
{
    echo "$PREREQ"
}

case $1 in
prereqs)
    prereqs
    exit 0
    ;;
esac

. /scripts/casper-functions

log_begin_msg "Setting up ZFS for live system"

# Import ZFS pools
zpool import -a -f 2>/dev/null || true

# Mount ZFS filesystems
zfs mount -a 2>/dev/null || true

log_end_msg
EOF
    
    chmod +x "$CHROOT_DIR/etc/initramfs-tools/scripts/casper-bottom/10_zfs_live"
    
    # Create BTRFS persistence script - VITAL for BTRFS functionality
    cat > "$CHROOT_DIR/etc/initramfs-tools/scripts/casper-bottom/05_btrfs_persist" <<'EOF'
#!/bin/sh

PREREQ=""
prereqs()
{
    echo "$PREREQ"
}

case $1 in
prereqs)
    prereqs
    exit 0
    ;;
esac

. /scripts/casper-functions

log_begin_msg "Setting up BTRFS persistence"

# Scan for BTRFS filesystems
btrfs device scan 2>/dev/null || true

# Wait for device detection
sleep 2

# Look for BTRFS persistence partitions
for device in /dev/sd* /dev/nvme* /dev/vd* /dev/hd*; do
    if [ -b "$device" ]; then
        # Check if it's a BTRFS filesystem
        if blkid -t TYPE=btrfs "$device" >/dev/null 2>&1; then
            log_begin_msg "Found BTRFS device: $device"
            
            # Try to mount for persistence
            mkdir -p /mnt/btrfs-persist 2>/dev/null || true
            if mount -t btrfs -o compress=zstd:6,space_cache=v2 "$device" /mnt/btrfs-persist 2>/dev/null; then
                log_begin_msg "BTRFS persistence mounted: $device"
                
                # Create persistence directories if they don't exist
                mkdir -p /mnt/btrfs-persist/casper-rw 2>/dev/null || true
                mkdir -p /mnt/btrfs-persist/home-rw 2>/dev/null || true
                
                # Set up persistence overlay
                if [ -d /mnt/btrfs-persist/casper-rw ]; then
                    echo "/mnt/btrfs-persist/casper-rw" > /tmp/persistence-device
                fi
            fi
        fi
    fi
done

log_end_msg
EOF
    
    chmod +x "$CHROOT_DIR/etc/initramfs-tools/scripts/casper-bottom/05_btrfs_persist"
    
    log_success "Live scripts created (ZFS + BTRFS persistence)"
}

generate_initramfs() {
    log_info "Generating initramfs..."
    
    # Get kernel version
    local kernel_version=$(chroot "$CHROOT_DIR" ls /lib/modules | tail -1)
    
    log_info "Generating initramfs for kernel $kernel_version"
    
    # Generate initramfs
    chroot "$CHROOT_DIR" bash <<EOF
export DEBIAN_FRONTEND=noninteractive

# Update initramfs
update-initramfs -c -k $kernel_version

# Verify initramfs
if [ -f /boot/initrd.img-$kernel_version ]; then
    echo "Initramfs generated successfully"
    ls -lh /boot/initrd.img-$kernel_version
else
    echo "ERROR: Initramfs generation failed"
    exit 1
fi
EOF
    
    # Copy kernel and initramfs for ISO
    safe_mkdir "$WORK_DIR/iso/casper" 755
    
    cp "$CHROOT_DIR/boot/vmlinuz-$kernel_version" \
       "$WORK_DIR/iso/casper/vmlinuz"
    
    cp "$CHROOT_DIR/boot/initrd.img-$kernel_version" \
       "$WORK_DIR/iso/casper/initrd"
    
    log_success "Initramfs generated and copied"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== INITRAMFS GENERATION MODULE ==="
    
    # Mount chroot
    mount_chroot
    
    # Configure and generate initramfs
    configure_initramfs || exit 1
    create_live_scripts || exit 1
    generate_initramfs || exit 1
    
    # Create checkpoint
    create_checkpoint "initramfs_complete" "$BUILD_ROOT"
    
    # Cleanup
    umount_chroot
    
    log_success "=== INITRAMFS GENERATION COMPLETE ==="
    exit 0
}

trap umount_chroot EXIT
main "$@"
