#!/bin/bash
#
# Kernel Compilation Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Installs or compiles kernel with ZFS support
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
MODULE_NAME="kernel-compilation"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"
readonly BUILD_KERNEL="${BUILD_KERNEL:-false}"
readonly KERNEL_VERSION="${KERNEL_VERSION:-6.8.0}"

#=============================================================================
# KERNEL FUNCTIONS
#=============================================================================

mount_chroot() {
    mount -t proc proc "$CHROOT_DIR/proc" 2>/dev/null || true
    mount -t sysfs sys "$CHROOT_DIR/sys" 2>/dev/null || true
    mount -t devtmpfs dev "$CHROOT_DIR/dev" 2>/dev/null || true
    mount -t devpts devpts "$CHROOT_DIR/dev/pts" 2>/dev/null || true
}

umount_chroot() {
    umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    umount "$CHROOT_DIR/dev" 2>/dev/null || true
    umount "$CHROOT_DIR/sys" 2>/dev/null || true
    umount "$CHROOT_DIR/proc" 2>/dev/null || true
}

install_kernel_packages() {
    log_info "Installing kernel packages..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    linux-generic-hwe-22.04 \
    linux-headers-generic-hwe-22.04 \
    linux-image-generic-hwe-22.04 \
    linux-tools-generic-hwe-22.04 \
    initramfs-tools \
    initramfs-tools-core
EOF
    
    log_success "Kernel packages installed"
}

install_zfs_support() {
    log_info "Installing ZFS kernel support..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
export DEBIAN_FRONTEND=noninteractive

# Add ZFS repository
apt-get install -y software-properties-common
add-apt-repository -y ppa:jonathonf/zfs
apt-get update

# Install ZFS
apt-get install -y \
    zfsutils-linux \
    zfs-dkms \
    zfs-initramfs
    
# Enable ZFS services
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-share
systemctl enable zfs.target
EOF
    
    log_success "ZFS support installed"
}

compile_custom_kernel() {
    log_info "Compiling custom kernel (this will take 30-60 minutes)..."
    
    chroot "$CHROOT_DIR" bash <<EOF
export DEBIAN_FRONTEND=noninteractive

# Install build dependencies
apt-get install -y \
    build-essential \
    libncurses-dev \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    bc \
    rsync \
    kmod \
    cpio

# Download kernel source
cd /usr/src
wget -q https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/linux-${KERNEL_VERSION}.tar.xz
tar xf linux-${KERNEL_VERSION}.tar.xz
cd linux-${KERNEL_VERSION}

# Configure kernel
make defconfig
make menuconfig ARCH=x86_64

# Enable ZFS-related options
scripts/config --enable CONFIG_CRYPTO_SHA256
scripts/config --enable CONFIG_CRYPTO_SHA512
scripts/config --enable CONFIG_ZLIB_INFLATE
scripts/config --enable CONFIG_ZLIB_DEFLATE

# Compile kernel
make -j$(nproc) bzImage
make -j$(nproc) modules
make modules_install
make install

# Update initramfs
update-initramfs -c -k ${KERNEL_VERSION}
EOF
    
    log_success "Custom kernel compiled"
}

configure_grub() {
    log_info "Configuring bootloader..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
export DEBIAN_FRONTEND=noninteractive

# Install GRUB packages
apt-get install -y \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-efi-amd64-signed \
    shim-signed

# Configure GRUB defaults
cat > /etc/default/grub <<'GRUB'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Ubuntu ZFS LiveCD"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX="root=ZFS=rpool/ROOT/ubuntu"
GRUB'

# Update GRUB configuration
update-grub
EOF
    
    log_success "Bootloader configured"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== KERNEL COMPILATION MODULE ==="
    
    # Mount chroot
    mount_chroot
    
    # Install or compile kernel
    if [[ "$BUILD_KERNEL" == "true" ]]; then
        compile_custom_kernel || exit 1
    else
        install_kernel_packages || exit 1
    fi
    
    # Install ZFS support
    install_zfs_support || exit 1
    
    # Configure bootloader
    configure_grub || exit 1
    
    # Create checkpoint
    create_checkpoint "kernel_complete" "$BUILD_ROOT"
    
    # Cleanup
    umount_chroot
    
    log_success "=== KERNEL COMPILATION COMPLETE ==="
    exit 0
}

trap umount_chroot EXIT
main "$@"
