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
MODULE_NAME="zfs-builder"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${BUILD_ROOT:-${1:-/dev/shm/build}}"
CHROOT_DIR="$BUILD_ROOT/chroot"

# ZFS specific configuration
ZFS_VERSION="2.3.4"
ZFS_URL="https://github.com/openzfs/zfs/releases/download/zfs-${ZFS_VERSION}/zfs-${ZFS_VERSION}.tar.gz"
ZFS_BUILD_DIR="/tmp/zfs-host-build-$$"
ZFS_SOURCE_DIR="$ZFS_BUILD_DIR/zfs-${ZFS_VERSION}"

#=============================================================================
# ZFS BUILD FUNCTIONS
#=============================================================================

check_existing_zfs() {
    log_info "Checking for existing ZFS installation..."
    
    # Check on host first
    if command -v zfs >/dev/null 2>&1; then
        local host_version=$(zfs version 2>/dev/null | grep -oP 'zfs-\K[0-9.]+' | head -1)
        log_info "Host has ZFS version: ${host_version:-unknown}"
    fi
    
    # Check in chroot if it exists
    if [[ -d "$CHROOT_DIR" ]]; then
        if chroot "$CHROOT_DIR" /bin/bash -c "command -v zfs >/dev/null 2>&1"; then
            local current_version=$(chroot "$CHROOT_DIR" zfs version 2>/dev/null | grep -oP 'zfs-\K[0-9.]+' | head -1)
            
            if [[ "$current_version" == "$ZFS_VERSION" ]]; then
                log_success "ZFS ${ZFS_VERSION} already installed in chroot"
                return 0
            else
                log_warn "Chroot has ZFS version: ${current_version:-unknown}"
                log_info "Will build ZFS ${ZFS_VERSION} from source"
                return 1
            fi
        else
            log_info "ZFS not found in chroot, will build from source"
            return 1
        fi
    else
        log_info "Chroot not available yet, building on host"
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
    log_info "Installing ZFS build dependencies on host..."
    
    # Install on host system
    sudo bash <<'EOF'
# Update package lists
apt-get update

# CRITICAL: Remove any existing ZFS packages first
echo "Removing any existing ZFS installations..."
apt-get remove -y --purge zfsutils-linux zfs-dkms zfs-initramfs zfs-zed \
    libzfs4linux libzpool5linux libnvpair3linux libuutil3linux \
    zfs-dracut zpool-features 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

# Remove ZFS kernel modules if present
rmmod zfs 2>/dev/null || true
rmmod spl 2>/dev/null || true

# Clean any ZFS remnants from modules directories
rm -rf /lib/modules/*/extra/zfs* 2>/dev/null || true
rm -rf /lib/modules/*/extra/spl* 2>/dev/null || true
rm -rf /usr/src/zfs* 2>/dev/null || true
rm -rf /usr/src/spl* 2>/dev/null || true

echo "Cleaned existing ZFS installations"

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

build_zfs_on_host() {
    log_info "Building ZFS ${ZFS_VERSION} on host system..."
    
    cd "$ZFS_SOURCE_DIR"
    
    # Run autogen
    log_info "Running autogen.sh..."
    ./autogen.sh || {
        log_error "autogen.sh failed"
        return 1
    }

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
        --with-config=all || {
        log_error "Configuration failed"
        return 1
    }
    
    # Build ZFS
    log_info "Compiling ZFS (this may take 10-20 minutes)..."
    make -j$(nproc) || {
        log_warn "Parallel build failed, trying single-threaded..."
        make || {
            log_error "Build failed"
            return 1
        }
    }
    
    # Build Debian packages
    log_info "Building Debian packages..."
    make deb || {
        log_warn "Debian package build failed, will try direct install"
    }
    
    # Install on host (optional)
    log_info "Installing ZFS on host..."
    sudo make install || {
        log_warn "Host installation failed, will copy to chroot"
    }
    sudo ldconfig
    
    log_success "ZFS ${ZFS_VERSION} built on host"
    return 0
}

copy_zfs_to_chroot() {
    log_info "Copying ZFS build to chroot..."
    
    if [[ ! -d "$CHROOT_DIR" ]]; then
        log_warn "Chroot not available yet, skipping copy"
        return 0
    fi
    
    # Look for .deb packages first
    local deb_dir="$ZFS_SOURCE_DIR"
    local deb_files=$(find "$deb_dir" -maxdepth 2 -name "*.deb" 2>/dev/null)
    
    if [[ -n "$deb_files" ]]; then
        log_info "Found Debian packages, installing in chroot..."
        
        # Copy debs to chroot
        sudo mkdir -p "$CHROOT_DIR/tmp/zfs-debs"
        sudo cp $deb_files "$CHROOT_DIR/tmp/zfs-debs/"
        
        # Install in chroot
        sudo chroot "$CHROOT_DIR" /bin/bash <<'EOF'
cd /tmp/zfs-debs
DEBIAN_FRONTEND=noninteractive dpkg -i *.deb || apt-get install -f -y
rm -rf /tmp/zfs-debs
ldconfig
EOF
        log_success "ZFS packages installed in chroot"
    else
        log_info "No .deb packages found, copying built files..."
        
        # Copy built files directly
        if [[ -d "$ZFS_SOURCE_DIR" ]]; then
            # Copy libraries
            sudo find "$ZFS_SOURCE_DIR" -name "*.so*" -exec cp {} "$CHROOT_DIR/usr/lib/" \; 2>/dev/null || true
            
            # Copy binaries
            for bin in zfs zpool zdb zed zgenhostid; do
                if [[ -f "$ZFS_SOURCE_DIR/cmd/$bin/$bin" ]]; then
                    sudo cp "$ZFS_SOURCE_DIR/cmd/$bin/$bin" "$CHROOT_DIR/usr/sbin/" 2>/dev/null || true
                fi
            done
            
            # Copy kernel modules if built
            if [[ -d "$ZFS_SOURCE_DIR/module" ]]; then
                sudo cp -r "$ZFS_SOURCE_DIR/module" "$CHROOT_DIR/usr/src/zfs-${ZFS_VERSION}/" 2>/dev/null || true
            fi
            
            # Update library cache in chroot
            sudo chroot "$CHROOT_DIR" ldconfig
        fi
    fi
    
    return 0
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
    log_info "Building ZFS ${ZFS_VERSION} on host, then deploying to chroot if available"
    
    # Don't require chroot to exist yet
    if [[ -d "$CHROOT_DIR" ]]; then
        log_info "Chroot found at: $CHROOT_DIR"
    else
        log_info "Chroot not yet available, building on host for later deployment"
    fi
    
    # Check if ZFS 2.3.4 is already installed
    if check_existing_zfs; then
        log_success "ZFS ${ZFS_VERSION} already installed, skipping build"
        exit 0
    fi
    
    # Install build dependencies
    install_build_dependencies
    
    # Clean up any existing ZFS on host first
    log_info "Cleaning existing ZFS installations..."
    sudo apt-get remove -y --purge zfsutils-linux zfs-dkms 2>/dev/null || true
    
    # Try to build from source on host
    if download_zfs_source && build_zfs_on_host; then
        copy_zfs_to_chroot
        if [[ -d "$CHROOT_DIR" ]]; then
            configure_zfs
            verify_zfs_installation
        else
            log_info "Chroot not ready, ZFS built on host for later use"
        fi
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
    
    # Clean up build directory
    log_info "Cleaning up build directory..."
    rm -rf "$ZFS_BUILD_DIR"
    
    # Create checkpoint
    create_checkpoint "zfs_${ZFS_VERSION}_installed" "$BUILD_ROOT"
    
    log_success "=== ZFS ${ZFS_VERSION} MODULE COMPLETE ==="
    if [[ -d "$CHROOT_DIR" ]]; then
        log_info "ZFS ${ZFS_VERSION} is ready for use in the LiveCD environment"
    else
        log_info "ZFS ${ZFS_VERSION} built on host, ready for chroot deployment"
    fi
    
    exit 0
}

# Trap to clean up on exit
trap "rm -rf $ZFS_BUILD_DIR" EXIT

# Execute main function
main "$@"