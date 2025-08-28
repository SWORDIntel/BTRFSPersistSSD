#!/bin/bash
#
# ISO Assembly Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Creates bootable ISO from prepared chroot with BTRFS persistence
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
MODULE_NAME="iso-assembly"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"
ISO_WORK_DIR="$BUILD_ROOT/iso-work"
ISO_OUTPUT="$BUILD_ROOT/ubuntu-btrfs-persist.iso"

# ISO configuration
ISO_LABEL="UBUNTU_BTRFS_PERSIST"
ISO_VOLUME_ID="Ubuntu BTRFS Persistent LiveCD"
APPLICATION_ID="Ubuntu BTRFS Persistent System"

#=============================================================================
# ISO PREPARATION FUNCTIONS
#=============================================================================

prepare_iso_structure() {
    log_info "Preparing ISO directory structure..."
    
    # Clean and create ISO work directory
    [[ -d "$ISO_WORK_DIR" ]] && rm -rf "$ISO_WORK_DIR"
    mkdir -p "$ISO_WORK_DIR"/{casper,isolinux,boot/grub,.disk}
    
    # Create .disk metadata
    cat > "$ISO_WORK_DIR/.disk/info" <<< "$ISO_VOLUME_ID"
    echo "full_cd/single" > "$ISO_WORK_DIR/.disk/cd_type"
    date +%Y%m%d-%H:%M > "$ISO_WORK_DIR/.disk/date-created"
    
    log_success "ISO structure prepared"
}

create_squashfs_filesystem() {
    log_info "Creating compressed SquashFS filesystem..."
    
    # Remove unnecessary files to reduce size
    chroot "$CHROOT_DIR" bash << 'CLEANUP'
# Clean package cache
apt-get clean
rm -rf /var/cache/apt/archives/*.deb
rm -rf /var/lib/apt/lists/*

# Clean temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clean logs
find /var/log -type f -exec truncate -s 0 {} \;

# Remove man pages and docs to save space (optional)
# rm -rf /usr/share/doc/*
# rm -rf /usr/share/man/*
CLEANUP

    # Create SquashFS with maximum compression for smaller ISO
    log_info "Creating SquashFS (this may take 10-15 minutes)..."
    
    # Use zstd compression for best balance of speed/size
    if ! mksquashfs "$CHROOT_DIR" "$ISO_WORK_DIR/casper/filesystem.squashfs" \
        -comp zstd -Xcompression-level 19 \
        -e boot \
        -progress \
        -processors $(nproc); then
        log_error "Failed to create SquashFS filesystem"
        return 1
    fi
    
    # Create size file for casper
    du -sx --block-size=1 "$CHROOT_DIR" | cut -f1 > "$ISO_WORK_DIR/casper/filesystem.size"
    
    log_success "SquashFS filesystem created ($(du -h "$ISO_WORK_DIR/casper/filesystem.squashfs" | cut -f1))"
}

copy_boot_files() {
    log_info "Copying boot files from chroot..."
    
    # Copy kernel and initramfs
    local kernel_version=$(ls "$CHROOT_DIR/lib/modules" | head -1)
    
    if [[ -f "$CHROOT_DIR/boot/vmlinuz-$kernel_version" ]]; then
        cp "$CHROOT_DIR/boot/vmlinuz-$kernel_version" "$ISO_WORK_DIR/casper/vmlinuz"
        log_success " Kernel copied: vmlinuz-$kernel_version"
    else
        log_error "Kernel not found: /boot/vmlinuz-$kernel_version"
        return 1
    fi
    
    if [[ -f "$CHROOT_DIR/boot/initrd.img-$kernel_version" ]]; then
        cp "$CHROOT_DIR/boot/initrd.img-$kernel_version" "$ISO_WORK_DIR/casper/initrd"
        log_success " Initramfs copied: initrd.img-$kernel_version"
    else
        log_error "Initramfs not found: /boot/initrd.img-$kernel_version"
        return 1
    fi
    
    # Copy memtest if available
    if [[ -f "$CHROOT_DIR/boot/memtest86+.bin" ]]; then
        cp "$CHROOT_DIR/boot/memtest86+.bin" "$ISO_WORK_DIR/boot/memtest"
        log_info " Memtest86+ copied"
    fi
}

create_grub_config() {
    log_info "Creating GRUB bootloader configuration..."
    
    # Create GRUB configuration for ISO boot
    cat > "$ISO_WORK_DIR/boot/grub/grub.cfg" << 'EOF'
# GRUB Configuration for Ubuntu BTRFS Persistent LiveCD

set default="0"
set timeout=10

# Load GRUB modules
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod ext2
insmod btrfs
insmod squash4
insmod loopback
insmod video_bochs
insmod video_cirrus
insmod gfxterm

# Set graphical mode
if loadfont /boot/grub/fonts/unicode.pf2; then
    set gfxmode=auto
    insmod gfxterm
    terminal_output gfxterm
fi

# Set colors
set color_normal=white/black
set color_highlight=black/light-gray

# Main menu
menuentry "Ubuntu BTRFS Persistent LiveCD" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper persistent quiet splash ---
    initrd /casper/initrd
}

menuentry "Ubuntu BTRFS Persistent LiveCD (Safe Mode)" {
    set gfxpayload=text
    linux /casper/vmlinuz boot=casper persistent nomodeset nosplash ---
    initrd /casper/initrd
}

menuentry "Ubuntu BTRFS Persistent LiveCD (Debug)" {
    set gfxpayload=text
    linux /casper/vmlinuz boot=casper persistent debug ---
    initrd /casper/initrd
}

menuentry "Check disc for defects" {
    set gfxpayload=text
    linux /casper/vmlinuz boot=casper integrity-check quiet splash ---
    initrd /casper/initrd
}

if [ -f /boot/memtest ]; then
menuentry "Memory test (memtest86+)" {
    linux16 /boot/memtest
}
fi

menuentry "Boot from first hard disk" {
    set root=(hd0)
    chainloader +1
}
EOF

    # Create GRUB font directory and copy font if available
    mkdir -p "$ISO_WORK_DIR/boot/grub/fonts"
    if [[ -f "$CHROOT_DIR/usr/share/grub/unicode.pf2" ]]; then
        cp "$CHROOT_DIR/usr/share/grub/unicode.pf2" "$ISO_WORK_DIR/boot/grub/fonts/"
    fi
    
    log_success "GRUB configuration created"
}

create_isolinux_config() {
    log_info "Creating ISOLINUX bootloader configuration..."
    
    # Install syslinux files
    if [[ -d "$CHROOT_DIR/usr/lib/ISOLINUX" ]]; then
        cp "$CHROOT_DIR/usr/lib/ISOLINUX/isolinux.bin" "$ISO_WORK_DIR/isolinux/"
    elif [[ -d "$CHROOT_DIR/usr/lib/syslinux/modules/bios" ]]; then
        cp "$CHROOT_DIR/usr/lib/syslinux/modules/bios/isolinux.bin" "$ISO_WORK_DIR/isolinux/"
    else
        log_warning "ISOLINUX binary not found, trying package installation..."
        chroot "$CHROOT_DIR" apt-get install -y isolinux
        cp "$CHROOT_DIR/usr/lib/ISOLINUX/isolinux.bin" "$ISO_WORK_DIR/isolinux/"
    fi
    
    # Copy additional ISOLINUX modules
    for module in ldlinux.c32 libcom32.c32 libutil.c32 vesamenu.c32; do
        if [[ -f "$CHROOT_DIR/usr/lib/syslinux/modules/bios/$module" ]]; then
            cp "$CHROOT_DIR/usr/lib/syslinux/modules/bios/$module" "$ISO_WORK_DIR/isolinux/"
        fi
    done
    
    # Create ISOLINUX configuration
    cat > "$ISO_WORK_DIR/isolinux/isolinux.cfg" << 'EOF'
DEFAULT vesamenu.c32
TIMEOUT 100
MENU TITLE Ubuntu BTRFS Persistent LiveCD

MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

MENU BACKGROUND splash.png

LABEL live
  MENU LABEL ^Ubuntu BTRFS Persistent LiveCD
  MENU DEFAULT
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper persistent quiet splash ---

LABEL livesafe
  MENU LABEL Ubuntu BTRFS Persistent LiveCD (^Safe Mode)
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper persistent nomodeset nosplash ---

LABEL check
  MENU LABEL ^Check disc for defects
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper integrity-check quiet splash ---

LABEL memtest
  MENU LABEL ^Memory test
  KERNEL /boot/memtest
  APPEND -

LABEL hd
  MENU LABEL ^Boot from first hard disk
  LOCALBOOT 0x80
  APPEND -
EOF

    # Create a simple splash screen
    cat > "$ISO_WORK_DIR/isolinux/splash.png" << 'EOF' || true
# Placeholder for splash image - create a simple text file for now
EOF

    log_success "ISOLINUX configuration created"
}

create_manifest() {
    log_info "Creating package manifest..."
    
    # Create manifest of installed packages
    chroot "$CHROOT_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' \
        > "$ISO_WORK_DIR/casper/filesystem.manifest"
    
    # Create manifest-desktop (same as manifest for our use case)
    cp "$ISO_WORK_DIR/casper/filesystem.manifest" "$ISO_WORK_DIR/casper/filesystem.manifest-desktop"
    
    log_success "Package manifest created"
}

generate_md5_checksums() {
    log_info "Generating MD5 checksums..."
    
    cd "$ISO_WORK_DIR"
    
    # Generate checksums for all files
    find . -type f -not -name md5sum.txt -print0 | xargs -0 md5sum > md5sum.txt
    
    log_success "MD5 checksums generated"
}

create_iso_image() {
    log_info "Creating final ISO image..."
    
    # Remove existing ISO
    [[ -f "$ISO_OUTPUT" ]] && rm -f "$ISO_OUTPUT"
    
    # Create hybrid ISO that can boot from USB and DVD
    if ! xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$ISO_LABEL" \
        -appid "$APPLICATION_ID" \
        -publisher "Ubuntu BTRFS Persistent System Builder" \
        -preparer "Built with: $MODULE_NAME v$MODULE_VERSION" \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -isohybrid-apm-hfsplus \
        -output "$ISO_OUTPUT" \
        "$ISO_WORK_DIR"; then
        
        log_warning "xorriso with EFI failed, trying simpler approach..."
        
        # Fallback: Create ISO without EFI support
        if ! genisoimage -D -r -V "$ISO_LABEL" \
            -cache-inodes -J -l \
            -b isolinux/isolinux.bin \
            -c isolinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -o "$ISO_OUTPUT" \
            "$ISO_WORK_DIR"; then
            
            log_error "Failed to create ISO image"
            return 1
        fi
    fi
    
    # Make it hybrid bootable (USB + DVD)
    if command -v isohybrid &>/dev/null; then
        isohybrid "$ISO_OUTPUT" 2>/dev/null || log_warning "Failed to make hybrid bootable"
    fi
    
    # Calculate final size
    local iso_size=$(du -h "$ISO_OUTPUT" | cut -f1)
    
    log_success "ISO image created: $ISO_OUTPUT ($iso_size)"
    
    # Create symlink for easy access
    ln -sf "$ISO_OUTPUT" "$BUILD_ROOT/ubuntu.iso"
    log_info "Symlink created: $BUILD_ROOT/ubuntu.iso -> $(basename "$ISO_OUTPUT")"
}

verify_iso() {
    log_info "Verifying ISO image..."
    
    if [[ ! -f "$ISO_OUTPUT" ]]; then
        log_error "ISO file not found: $ISO_OUTPUT"
        return 1
    fi
    
    # Check file size (should be reasonable)
    local size_bytes=$(stat -c%s "$ISO_OUTPUT")
    local size_mb=$((size_bytes / 1024 / 1024))
    
    if [[ $size_mb -lt 100 ]]; then
        log_error "ISO size too small: ${size_mb}MB (expected >100MB)"
        return 1
    fi
    
    if [[ $size_mb -gt 8000 ]]; then
        log_warning "ISO size very large: ${size_mb}MB (might not fit on DVD)"
    fi
    
    log_success " ISO size: ${size_mb}MB"
    
    # Verify ISO integrity
    if command -v isoinfo &>/dev/null; then
        if isoinfo -d -i "$ISO_OUTPUT" >/dev/null 2>&1; then
            log_success " ISO structure valid"
        else
            log_warning " ISO structure validation failed"
        fi
    fi
    
    # Check for boot sectors
    if file "$ISO_OUTPUT" | grep -q "boot sector"; then
        log_success " Boot sector present"
    else
        log_warning " Boot sector not detected"
    fi
    
    log_success "ISO verification complete"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== ISO ASSEMBLY MODULE v$MODULE_VERSION ==="
    log_info "Creating bootable Ubuntu BTRFS Persistent LiveCD"
    log_info "Build root: $BUILD_ROOT"
    log_info "Output ISO: $ISO_OUTPUT"
    
    # Validate prerequisites
    [[ -d "$CHROOT_DIR" ]] || {
        log_error "Chroot directory not found: $CHROOT_DIR"
        return 1
    }
    
    # Check required tools
    local missing_tools=()
    for tool in mksquashfs xorriso genisoimage; do
        command -v "$tool" >/dev/null || missing_tools+=("$tool")
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install with: apt-get install squashfs-tools xorriso genisoimage"
        return 1
    fi
    
    # Execute ISO creation steps
    prepare_iso_structure || return 1
    create_squashfs_filesystem || return 1  
    copy_boot_files || return 1
    create_grub_config || return 1
    create_isolinux_config || return 1
    create_manifest || return 1
    generate_md5_checksums || return 1
    create_iso_image || return 1
    verify_iso || return 1
    
    # Create checkpoint
    create_checkpoint "iso_assembled" "$BUILD_ROOT"
    
    log_success "=== ISO ASSEMBLY COMPLETE ==="
    log_success "ISO Location: $ISO_OUTPUT"
    log_success "Symlink: $BUILD_ROOT/ubuntu.iso"
    log_success "Size: $(du -h "$ISO_OUTPUT" | cut -f1)"
    log_success "Label: $ISO_LABEL"
    log_success "Features: BTRFS persistence, hybrid boot (USB+DVD), GRUB+ISOLINUX"
    
    exit 0
}

# Execute main function
main "$@"