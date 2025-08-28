#!/bin/bash
#
# Boot Configuration Module with EFI Management
# Version: 1.0.0
# Part of: LiveCD Build System
#
# Configures GRUB and EFI boot entries with fallback support
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
TARGET_DEVICE="${2:-/dev/sda}"
MOUNT_POINT="${3:-/mnt/persist}"

# Partition configuration
EFI_PARTITION="${TARGET_DEVICE}2"
PERSIST_PARTITION="${TARGET_DEVICE}1"
EFI_MOUNT="$MOUNT_POINT/boot/efi"

#=============================================================================
# EFI BOOT MANAGEMENT FUNCTIONS
#=============================================================================

configure_grub() {
    local chroot_dir="$1"
    
    log_info "Configuring GRUB for persistent boot..."
    
    # Create GRUB configuration
    cat > "$chroot_dir/etc/default/grub" << 'EOF'
# GRUB Configuration for BTRFS Persistent LiveCD
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="BTRFS Persistent Ubuntu"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash persistent"
GRUB_CMDLINE_LINUX="dis_ucode_ldr"  # Disable microcode loading
GRUB_TERMINAL_OUTPUT="console"
GRUB_DISABLE_OS_PROBER=false
GRUB_DISABLE_RECOVERY=false
GRUB_DISABLE_SUBMENU=true
GRUB_GFXMODE=1024x768x32
GRUB_GFXPAYLOAD_LINUX=keep

# Enable BTRFS support
GRUB_BTRFS_ENABLE=yes
GRUB_BTRFS_SUBVOL_SORT="descending"

# Custom menu entries
GRUB_DISABLE_LINUX_UUID=false
GRUB_DISABLE_LINUX_PARTUUID=false
EOF
    
    # Create custom GRUB menu entry
    cat > "$chroot_dir/etc/grub.d/40_custom" << 'EOF'
#!/bin/sh
exec tail -n +3 $0

# Custom boot entries for BTRFS Persistent System

menuentry "Ubuntu Persistent (Primary)" {
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod ext2
    insmod fat
    
    # Search for the EFI partition
    search --no-floppy --fs-uuid --set=root ${EFI_UUID}
    
    # Load kernel and initramfs
    linux /vmlinuz root=UUID=${PERSIST_UUID} rw persistent dis_ucode_ldr quiet splash
    initrd /initrd.img
}

menuentry "Ubuntu Persistent (Fallback)" {
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod ext2
    insmod fat
    
    # Search for the EFI partition
    search --no-floppy --fs-uuid --set=root ${EFI_UUID}
    
    # Load kernel with recovery options
    linux /vmlinuz root=UUID=${PERSIST_UUID} rw persistent dis_ucode_ldr single nomodeset
    initrd /initrd.img
}

menuentry "Ubuntu Persistent (Safe Mode)" {
    insmod gzio
    insmod part_gpt
    insmod btrfs
    insmod ext2
    insmod fat
    
    # Search for the EFI partition
    search --no-floppy --fs-uuid --set=root ${EFI_UUID}
    
    # Load kernel with minimal drivers
    linux /vmlinuz root=UUID=${PERSIST_UUID} rw persistent dis_ucode_ldr text nomodeset nosplash
    initrd /initrd.img
}
EOF
    
    chmod +x "$chroot_dir/etc/grub.d/40_custom"
    
    log_success "GRUB configuration complete"
}

install_grub_efi() {
    local chroot_dir="$1"
    
    log_info "Installing GRUB EFI bootloader..."
    
    # Mount required filesystems for chroot
    mount -t proc proc "$chroot_dir/proc"
    mount -t sysfs sys "$chroot_dir/sys"
    mount -t devtmpfs dev "$chroot_dir/dev"
    mount -t devpts devpts "$chroot_dir/dev/pts"
    mount -t tmpfs run "$chroot_dir/run"
    
    # Mount EFI partition
    mkdir -p "$chroot_dir/boot/efi"
    mount "$EFI_PARTITION" "$chroot_dir/boot/efi"
    
    # Install GRUB for EFI
    chroot "$chroot_dir" bash << 'GRUB_INSTALL'
# Install GRUB packages if not present
apt-get update
apt-get install -y grub-efi-amd64 grub-efi-amd64-signed grub-pc-bin efibootmgr

# Install GRUB to EFI partition
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=BTRFS-Persistent --recheck --no-floppy

# Also install with Ubuntu name for compatibility
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=ubuntu --recheck --no-floppy

# Generate GRUB configuration
update-grub
GRUB_INSTALL
    
    # Copy kernel and initramfs to EFI partition for direct booting
    cp "$chroot_dir/boot/vmlinuz"* "$chroot_dir/boot/efi/vmlinuz" 2>/dev/null || true
    cp "$chroot_dir/boot/initrd"* "$chroot_dir/boot/efi/initrd.img" 2>/dev/null || true
    
    log_success "GRUB EFI installation complete"
}

configure_efi_boot_entries() {
    local chroot_dir="$1"
    local device_name="${4:-BTRFS-SSD}"
    
    log_info "Configuring EFI boot entries with efibootmgr..."
    
    # Get disk number and partition number
    local disk_num=$(echo "$TARGET_DEVICE" | grep -o '[0-9]*$')
    local efi_part_num="2"  # EFI is partition 2
    
    chroot "$chroot_dir" bash << EFIBOOT
# Remove any existing entries with our names
for entry in \$(efibootmgr | grep -E "(${device_name}|BTRFS-Persistent|Ubuntu-Persistent)" | cut -d' ' -f1 | tr -d 'Boot*'); do
    efibootmgr -B -b \$entry 2>/dev/null || true
done

# Get the EFI system partition device
ESP_DEVICE="${TARGET_DEVICE}${efi_part_num}"

# Create primary boot entry
efibootmgr --create \
    --disk "${TARGET_DEVICE}" \
    --part "${efi_part_num}" \
    --label "${device_name}-Primary" \
    --loader '\EFI\BTRFS-Persistent\grubx64.efi' \
    --verbose

# Create fallback boot entry
efibootmgr --create \
    --disk "${TARGET_DEVICE}" \
    --part "${efi_part_num}" \
    --label "${device_name}-Fallback" \
    --loader '\EFI\ubuntu\grubx64.efi' \
    --verbose

# Create direct kernel boot entry (emergency)
efibootmgr --create \
    --disk "${TARGET_DEVICE}" \
    --part "${efi_part_num}" \
    --label "${device_name}-Direct" \
    --loader '\vmlinuz' \
    --unicode 'root=UUID=$(blkid -s UUID -o value ${PERSIST_PARTITION}) rw persistent dis_ucode_ldr initrd=\initrd.img' \
    --verbose

# Set boot order (Primary, Fallback, Direct, then others)
BOOT_CURRENT=\$(efibootmgr | grep BootCurrent | awk '{print \$2}')
PRIMARY=\$(efibootmgr | grep "${device_name}-Primary" | cut -d' ' -f1 | tr -d 'Boot*')
FALLBACK=\$(efibootmgr | grep "${device_name}-Fallback" | cut -d' ' -f1 | tr -d 'Boot*')
DIRECT=\$(efibootmgr | grep "${device_name}-Direct" | cut -d' ' -f1 | tr -d 'Boot*')

# Get other boot entries
OTHER_ENTRIES=\$(efibootmgr | grep -E "^Boot[0-9]" | grep -vE "(${device_name}|BootCurrent)" | cut -d' ' -f1 | tr -d 'Boot*' | tr '\n' ',' | sed 's/,$//')

# Set boot order with our entries first
if [ -n "\$PRIMARY" ] && [ -n "\$FALLBACK" ] && [ -n "\$DIRECT" ]; then
    if [ -n "\$OTHER_ENTRIES" ]; then
        efibootmgr --bootorder "\${PRIMARY},\${FALLBACK},\${DIRECT},\${OTHER_ENTRIES}" --verbose
    else
        efibootmgr --bootorder "\${PRIMARY},\${FALLBACK},\${DIRECT}" --verbose
    fi
fi

# Display final boot configuration
echo "=== EFI Boot Configuration ==="
efibootmgr -v
echo "==========================="
EFIBOOT
    
    log_success "EFI boot entries configured"
}

create_systemd_boot_fallback() {
    local chroot_dir="$1"
    
    log_info "Creating systemd-boot as additional fallback..."
    
    chroot "$chroot_dir" bash << 'SYSTEMD_BOOT'
# Install systemd-boot
apt-get install -y systemd-boot

# Install systemd-boot to EFI
bootctl install --esp-path=/boot/efi

# Create loader configuration
mkdir -p /boot/efi/loader/entries

cat > /boot/efi/loader/loader.conf << 'LOADER'
default btrfs-persistent
timeout 5
console-mode max
editor no
LOADER

# Create boot entry
cat > /boot/efi/loader/entries/btrfs-persistent.conf << 'ENTRY'
title    BTRFS Persistent Ubuntu
linux    /vmlinuz
initrd   /initrd.img
options  root=UUID=${PERSIST_UUID} rw persistent dis_ucode_ldr quiet splash
ENTRY

# Create fallback entry
cat > /boot/efi/loader/entries/btrfs-fallback.conf << 'ENTRY'
title    BTRFS Persistent (Fallback)
linux    /vmlinuz
initrd   /initrd.img
options  root=UUID=${PERSIST_UUID} rw persistent dis_ucode_ldr single nomodeset
ENTRY
SYSTEMD_BOOT
    
    log_success "systemd-boot fallback configured"
}

verify_boot_configuration() {
    local chroot_dir="$1"
    
    log_info "Verifying boot configuration..."
    
    # Check GRUB installation
    if [[ -f "$chroot_dir/boot/efi/EFI/BTRFS-Persistent/grubx64.efi" ]]; then
        log_success "✓ GRUB EFI binary found (primary)"
    else
        log_warning "✗ GRUB EFI binary not found (primary)"
    fi
    
    if [[ -f "$chroot_dir/boot/efi/EFI/ubuntu/grubx64.efi" ]]; then
        log_success "✓ GRUB EFI binary found (fallback)"
    else
        log_warning "✗ GRUB EFI binary not found (fallback)"
    fi
    
    # Check kernel and initramfs on EFI partition
    if [[ -f "$chroot_dir/boot/efi/vmlinuz" ]]; then
        log_success "✓ Kernel found on EFI partition"
    else
        log_warning "✗ Kernel not found on EFI partition"
    fi
    
    if [[ -f "$chroot_dir/boot/efi/initrd.img" ]]; then
        log_success "✓ Initramfs found on EFI partition"
    else
        log_warning "✗ Initramfs not found on EFI partition"
    fi
    
    # Check systemd-boot
    if [[ -f "$chroot_dir/boot/efi/EFI/systemd/systemd-bootx64.efi" ]]; then
        log_success "✓ systemd-boot installed as additional fallback"
    else
        log_info "ℹ systemd-boot not installed (optional)"
    fi
    
    # Check EFI variables
    chroot "$chroot_dir" bash << 'CHECK_EFI'
if [ -d /sys/firmware/efi ]; then
    echo "✓ EFI mode detected"
    
    # Check if our boot entries exist
    if efibootmgr | grep -q "BTRFS-Persistent\|${device_name}"; then
        echo "✓ Custom EFI boot entries found"
    else
        echo "✗ Custom EFI boot entries not found"
    fi
else
    echo "ℹ Not in EFI mode (normal for chroot)"
fi
CHECK_EFI
    
    log_success "Boot configuration verification complete"
}

cleanup_mounts() {
    local chroot_dir="$1"
    
    log_info "Cleaning up mount points..."
    
    umount "$chroot_dir/boot/efi" 2>/dev/null || true
    umount "$chroot_dir/run" 2>/dev/null || true
    umount "$chroot_dir/dev/pts" 2>/dev/null || true
    umount "$chroot_dir/dev" 2>/dev/null || true
    umount "$chroot_dir/sys" 2>/dev/null || true
    umount "$chroot_dir/proc" 2>/dev/null || true
    
    log_success "Mount points cleaned up"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== BOOT CONFIGURATION MODULE v$MODULE_VERSION ==="
    log_info "Configuring EFI boot with primary and fallback entries"
    log_info "Target device: $TARGET_DEVICE"
    log_info "Mount point: $MOUNT_POINT"
    
    # Check if running as root
    [[ $EUID -ne 0 ]] && log_error "This module must be run as root"
    
    # Check if mount point exists
    [[ -d "$MOUNT_POINT" ]] || log_error "Mount point not found: $MOUNT_POINT"
    
    # Get UUIDs
    PERSIST_UUID=$(blkid -s UUID -o value "$PERSIST_PARTITION")
    EFI_UUID=$(blkid -s UUID -o value "$EFI_PARTITION")
    
    log_info "Persistence UUID: $PERSIST_UUID"
    log_info "EFI UUID: $EFI_UUID"
    
    # Export UUIDs for GRUB configuration
    export PERSIST_UUID EFI_UUID
    
    # Configure GRUB
    configure_grub "$MOUNT_POINT"
    
    # Install GRUB EFI
    install_grub_efi "$MOUNT_POINT"
    
    # Configure EFI boot entries
    DEVICE_NAME="${DEVICE_NAME:-BTRFS-SSD}"
    configure_efi_boot_entries "$MOUNT_POINT" "$TARGET_DEVICE" "$EFI_PARTITION" "$DEVICE_NAME"
    
    # Create systemd-boot as additional fallback
    create_systemd_boot_fallback "$MOUNT_POINT"
    
    # Verify configuration
    verify_boot_configuration "$MOUNT_POINT"
    
    # Cleanup
    cleanup_mounts "$MOUNT_POINT"
    
    log_success "=== BOOT CONFIGURATION COMPLETE ==="
    log_success "Primary boot: ${DEVICE_NAME}-Primary -> GRUB EFI"
    log_success "Fallback boot: ${DEVICE_NAME}-Fallback -> Ubuntu GRUB"
    log_success "Emergency boot: ${DEVICE_NAME}-Direct -> Direct kernel"
    log_success "Additional fallback: systemd-boot"
    log_success "Microcode loading: DISABLED (dis_ucode_ldr)"
    
    exit 0
}

# Execute main function
main "$@"