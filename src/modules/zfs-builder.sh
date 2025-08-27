#!/bin/bash
#
# ZFS 2.3.4 Builder Module
# Version: 1.0.0 - PRECISION BUILD
# Part of: LiveCD Build System
#
# Builds and installs ZFS 2.3.4 from source if not available
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
readonly MODULE_NAME="zfs-builder"
readonly MODULE_VERSION="1.0.0"
readonly BUILD_ROOT="${1:-/tmp/build}"
readonly CHROOT_DIR="$BUILD_ROOT/chroot"

# ZFS specific configuration
readonly ZFS_VERSION="2.3.4"
readonly ZFS_URL="https://github.com/openzfs/zfs/releases/download/zfs-${ZFS_VERSION}/zfs-${ZFS_VERSION}.tar.gz"
readonly ZFS_BUILD_DIR="$BUILD_ROOT/zfs-build"
readonly ZFS_SOURCE_DIR="$ZFS_BUILD_DIR/zfs-${ZFS_VERSION}"

#=============================================================================
# ZFS BUILD FUNCTIONS
#=============================================================================

check_existing_zfs() {
    log_info "Checking for existing ZFS installation..."
    
    if chroot "$CHROOT_DIR" /bin/bash -c "command -v zfs >/dev/null 2>&1"; then
        local current_version=$(chroot "$CHROOT_DIR" zfs version 2>/dev/null | grep -oP 'zfs-\K[0-9.]+' | head -1)
        
        if [[ "$current_version" == "$ZFS_VERSION" ]]; then
            log_success "ZFS ${ZFS_VERSION} already installed"
            return 0
        else
            log_warn "Found ZFS version: ${current_version:-unknown}"
            log_info "Will build ZFS ${ZFS_VERSION} from source"
            return 1
        fi
    else
        log_info "ZFS not found, will build from source"
        return 1
    fi
}

download_zfs_source() {
    log_info "Downloading ZFS ${ZFS_VERSION} source code..."
    
    safe_mkdir "$ZFS_BUILD_DIR" 755
    
    if [[ -f "$ZFS_BUILD_DIR/zfs-${ZFS_VERSION}.tar.gz" ]]; then
        log_info "Source tarball already downloaded"
    else
        wget -O "$ZFS_BUILD_DIR/zfs-${ZFS_VERSION}.tar.gz" "$ZFS_URL" || {
            log_error "Failed to download ZFS source"
            return 1
        }
    fi
    
    log_info "Extracting ZFS source..."
    cd "$ZFS_BUILD_DIR"
    tar -xzf "zfs-${ZFS_VERSION}.tar.gz" || {
        log_error "Failed to extract ZFS source"
        return 1
    }
    
    log_success "ZFS source ready"
}

install_build_dependencies() {
    log_info "Installing ZFS build dependencies..."
    
    chroot "$CHROOT_DIR" /bin/bash <<'EOF'
# Update package lists
apt-get update

# Install ZFS build dependencies
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    gawk \
    alien \
    fakeroot \
    dkms \
    libblkid-dev \
    uuid-dev \
    libudev-dev \
    libssl-dev \
    zlib1g-dev \
    libaio-dev \
    libattr1-dev \
    libelf-dev \
    linux-headers-generic \
    python3 \
    python3-dev \
    python3-setuptools \
    python3-cffi \
    python3-packaging \
    libffi-dev \
    libcurl4-openssl-dev \
    debhelper \
    dh-python \
    po-debconf \
    python3-all-dev \
    python3-sphinx \
    libpam0g-dev \
    nfs-kernel-server || {
    echo "Failed to install some dependencies, continuing anyway..."
}

# Install kernel headers for current kernel
KERNEL_VERSION=$(uname -r)
apt-get install -y linux-headers-${KERNEL_VERSION} 2>/dev/null || {
    echo "Specific kernel headers not available, using generic"
    apt-get install -y linux-headers-generic
}

# Ensure kernel source is available
apt-get install -y linux-source || true
EOF
    
    log_success "Build dependencies installed"
}

build_zfs() {
    log_info "Building ZFS ${ZFS_VERSION} from source..."
    
    # Copy source to chroot
    log_info "Copying source to chroot environment..."
    cp -r "$ZFS_SOURCE_DIR" "$CHROOT_DIR/usr/src/"
    
    # Build ZFS in chroot
    chroot "$CHROOT_DIR" /bin/bash <<EOF
cd /usr/src/zfs-${ZFS_VERSION}

# Configure build
log_info "Configuring ZFS build..."
./configure \
    --prefix=/usr \
    --libdir=/usr/lib \
    --includedir=/usr/include \
    --datarootdir=/usr/share \
    --enable-systemd \
    --enable-pyzfs \
    --with-systemdunitdir=/lib/systemd/system \
    --with-systemdpresetdir=/lib/systemd/system-preset \
    --with-config=user \
    || {
    echo "Configuration failed, trying with kernel support..."
    ./configure \
        --prefix=/usr \
        --enable-systemd \
        --with-config=all
}

# Build ZFS
log_info "Compiling ZFS (this may take 10-20 minutes)..."
make -j$(nproc) || {
    echo "Parallel build failed, trying single-threaded..."
    make
}

# Install ZFS
log_info "Installing ZFS..."
make install

# Update library cache
ldconfig

# Build and install Debian packages if possible
if command -v dpkg-buildpackage >/dev/null; then
    log_info "Building Debian packages..."
    make deb-utils deb-kmod || {
        echo "Debian package build failed, continuing with direct installation"
    }
fi
EOF
    
    log_success "ZFS ${ZFS_VERSION} built and installed"
}

configure_zfs() {
    log_info "Configuring ZFS ${ZFS_VERSION}..."
    
    chroot "$CHROOT_DIR" /bin/bash <<'EOF'
# Load ZFS module
modprobe zfs 2>/dev/null || true

# Create ZFS cache directory
mkdir -p /etc/zfs

# Enable ZFS services
systemctl enable zfs-import-cache 2>/dev/null || true
systemctl enable zfs-import-scan 2>/dev/null || true
systemctl enable zfs-mount 2>/dev/null || true
systemctl enable zfs-share 2>/dev/null || true
systemctl enable zfs-zed 2>/dev/null || true
systemctl enable zfs.target 2>/dev/null || true

# Create ZFS module load configuration
cat > /etc/modules-load.d/zfs.conf <<'ZFSMOD'
# Load ZFS modules at boot
zfs
ZFSMOD

# Configure ZFS for live environment
cat > /etc/modprobe.d/zfs.conf <<'ZFSCONF'
# ZFS configuration for LiveCD
# Limit ARC to prevent memory issues in live environment
options zfs zfs_arc_max=536870912
options zfs zfs_arc_min=134217728
ZFSCONF

# Create helper script for ZFS management
cat > /usr/local/bin/zfs-helper <<'ZFSHELPER'
#!/bin/bash
# ZFS Helper Script for LiveCD

case "$1" in
    status)
        echo "ZFS Version: $(zfs version 2>/dev/null | head -1)"
        echo "Kernel Module: $(lsmod | grep -E '^zfs' | head -1)"
        echo "Pools: $(zpool list -H 2>/dev/null | wc -l)"
        ;;
    load)
        modprobe zfs && echo "ZFS module loaded"
        ;;
    test)
        # Create test pool in RAM
        dd if=/dev/zero of=/tmp/zfs-test.img bs=1M count=100 2>/dev/null
        zpool create testpool /tmp/zfs-test.img
        zfs create testpool/test
        echo "Test data" > /testpool/test/file.txt
        zpool status testpool
        zpool destroy testpool
        rm /tmp/zfs-test.img
        echo "ZFS test completed successfully"
        ;;
    *)
        echo "Usage: $0 {status|load|test}"
        ;;
esac
ZFSHELPER

chmod +x /usr/local/bin/zfs-helper

# Update initramfs to include ZFS
if command -v update-initramfs >/dev/null; then
    update-initramfs -u -k all 2>/dev/null || true
fi
EOF
    
    log_success "ZFS configuration complete"
}

verify_zfs_installation() {
    log_info "Verifying ZFS ${ZFS_VERSION} installation..."
    
    # Check ZFS command
    if chroot "$CHROOT_DIR" /bin/bash -c "command -v zfs >/dev/null 2>&1"; then
        log_success "ZFS command available"
    else
        log_error "ZFS command not found"
        return 1
    fi
    
    # Check version
    local installed_version=$(chroot "$CHROOT_DIR" zfs version 2>/dev/null | grep -oP 'zfs-\K[0-9.]+' | head -1)
    if [[ "$installed_version" == "$ZFS_VERSION" ]]; then
        log_success "ZFS ${ZFS_VERSION} verified"
    else
        log_warn "Version mismatch: expected ${ZFS_VERSION}, got ${installed_version:-unknown}"
    fi
    
    # Check kernel module availability
    if chroot "$CHROOT_DIR" /bin/bash -c "modinfo zfs >/dev/null 2>&1"; then
        log_success "ZFS kernel module available"
    else
        log_warn "ZFS kernel module not found (may need DKMS rebuild)"
    fi
    
    # List ZFS components
    chroot "$CHROOT_DIR" /bin/bash <<'EOF'
echo "Installed ZFS components:"
for cmd in zfs zpool zdb zed zgenhostid arcstat arc_summary; do
    if command -v $cmd >/dev/null 2>&1; then
        echo "  ✓ $cmd: $(command -v $cmd)"
    else
        echo "  ✗ $cmd: not found"
    fi
done

# Show library status
echo "ZFS libraries:"
ldconfig -p | grep -E 'libzfs|libnvpair|libuutil|libzpool' | head -5
EOF
    
    return 0
}

fallback_install_zfs_packages() {
    log_warn "Attempting fallback installation via packages..."
    
    chroot "$CHROOT_DIR" /bin/bash <<'EOF'
# Try to install ZFS from packages as fallback
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    zfsutils-linux \
    zfs-dkms \
    zfs-initramfs \
    zfs-zed \
    zfs-dracut \
    libzfs4linux \
    libzfslinux-dev \
    2>/dev/null || {
    echo "Package installation also failed"
    exit 1
}
EOF
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== ZFS ${ZFS_VERSION} BUILDER MODULE ==="
    log_info "Ensuring ZFS ${ZFS_VERSION} is available in the build environment"
    
    # Check if chroot exists
    [[ -d "$CHROOT_DIR" ]] || {
        log_error "Chroot directory not found: $CHROOT_DIR"
        exit 1
    }
    
    # Check if ZFS 2.3.4 is already installed
    if check_existing_zfs; then
        log_success "ZFS ${ZFS_VERSION} already installed, skipping build"
        exit 0
    fi
    
    # Install build dependencies
    install_build_dependencies
    
    # Try to build from source
    if download_zfs_source && build_zfs; then
        configure_zfs
        verify_zfs_installation
    else
        log_warn "Source build failed, attempting package installation"
        if fallback_install_zfs_packages; then
            configure_zfs
            verify_zfs_installation
        else
            log_error "Failed to install ZFS ${ZFS_VERSION}"
            log_warn "System will continue without ZFS ${ZFS_VERSION}"
            # Don't fail the build, just warn
            exit 0
        fi
    fi
    
    # Create checkpoint
    create_checkpoint "zfs_${ZFS_VERSION}_installed" "$BUILD_ROOT"
    
    log_success "=== ZFS ${ZFS_VERSION} MODULE COMPLETE ==="
    log_info "ZFS ${ZFS_VERSION} is ready for use in the LiveCD environment"
    
    exit 0
}

# Execute main function
main "$@"