# Build Module Scripts for src/modules/

## 1. dependency-validation.sh

```bash
#!/bin/bash
#
# Dependency Validation Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Validates all build dependencies and system requirements
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
MODULE_NAME="dependency-validation"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"

# Dependency requirements
readonly MIN_DISK_SPACE_GB=20
readonly MIN_RAM_GB=4
readonly REQUIRED_COMMANDS=(
    "debootstrap" "systemd-nspawn" "mksquashfs" 
    "xorriso" "git" "zpool" "zfs"
    "gcc" "make" "dpkg" "apt-get"
)

readonly REQUIRED_PACKAGES=(
    "build-essential" "debootstrap" "squashfs-tools"
    "xorriso" "isolinux" "syslinux-utils" 
    "zfsutils-linux" "systemd-container"
)

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

validate_system_requirements() {
    log_info "Validating system requirements..."
    
    local validation_errors=0
    
    # Check disk space
    local available_space=$(df "$BUILD_ROOT" --output=avail -B G 2>/dev/null | tail -1 | tr -d 'G')
    if [[ ${available_space:-0} -lt $MIN_DISK_SPACE_GB ]]; then
        log_error "Insufficient disk space: ${available_space}GB (${MIN_DISK_SPACE_GB}GB required)"
        ((validation_errors++))
    else
        log_success "Disk space: ${available_space}GB available"
    fi
    
    # Check RAM
    local available_ram=$(free -g | awk '/^Mem:/{print $7}')
    if [[ ${available_ram:-0} -lt $MIN_RAM_GB ]]; then
        log_warning "Low memory: ${available_ram}GB (${MIN_RAM_GB}GB recommended)"
    else
        log_success "Memory: ${available_ram}GB available"
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    log_info "CPU cores available: $cpu_cores"
    
    return $validation_errors
}

validate_commands() {
    log_info "Validating required commands..."
    
    local missing_commands=()
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
            log_error "Missing command: $cmd"
        else
            log_debug "Found command: $cmd"
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing ${#missing_commands[@]} required commands"
        log_error "Install with: apt-get install ${missing_commands[*]}"
        return 1
    fi
    
    log_success "All required commands found"
    return 0
}

validate_kernel_support() {
    log_info "Validating kernel support..."
    
    local validation_errors=0
    
    # Check kernel version
    local kernel_version=$(uname -r)
    log_info "Kernel version: $kernel_version"
    
    # Check for required modules
    local required_modules=("zfs" "overlay" "squashfs")
    
    for module in "${required_modules[@]}"; do
        if ! modinfo "$module" &>/dev/null; then
            log_warning "Kernel module not found: $module"
            ((validation_errors++))
        else
            log_debug "Found module: $module"
        fi
    done
    
    return $validation_errors
}

validate_build_environment() {
    log_info "Validating build environment..."
    
    # Create build directory structure
    safe_mkdir "$BUILD_ROOT" 755
    safe_mkdir "$BUILD_ROOT/work" 755
    safe_mkdir "$BUILD_ROOT/logs" 755
    safe_mkdir "$BUILD_ROOT/cache" 755
    
    # Check write permissions
    if ! touch "$BUILD_ROOT/.write_test" 2>/dev/null; then
        log_error "Cannot write to build directory: $BUILD_ROOT"
        return 1
    fi
    rm -f "$BUILD_ROOT/.write_test"
    
    log_success "Build environment validated"
    return 0
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== DEPENDENCY VALIDATION MODULE ==="
    
    local total_errors=0
    
    # Run all validations
    validate_system_requirements || ((total_errors++))
    validate_commands || ((total_errors++))
    validate_kernel_support || ((total_errors++))
    validate_build_environment || ((total_errors++))
    
    if [[ $total_errors -gt 0 ]]; then
        log_error "Dependency validation failed with $total_errors errors"
        exit 1
    fi
    
    # Create validation report
    cat > "$BUILD_ROOT/validation-report.txt" <<EOF
Dependency Validation Report
Generated: $(date -Iseconds)
Status: PASSED

System Requirements:
- Disk Space: $(df -h "$BUILD_ROOT" | tail -1 | awk '{print $4}') available
- Memory: $(free -h | grep Mem | awk '{print $7}') available
- CPU Cores: $(nproc)
- Kernel: $(uname -r)

All dependencies validated successfully
EOF
    
    log_success "=== DEPENDENCY VALIDATION COMPLETE ==="
    exit 0
}

main "$@"
```

## 2. environment-setup.sh

```bash
#!/bin/bash
#
# Environment Setup Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Sets up the build environment and chroot structure
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
MODULE_NAME="environment-setup"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"
readonly WORK_DIR="$BUILD_ROOT/work"

# Environment settings
readonly DEBIAN_RELEASE="jammy"
readonly ARCH="amd64"

#=============================================================================
# ENVIRONMENT SETUP FUNCTIONS
#=============================================================================

setup_build_directories() {
    log_info "Setting up build directory structure..."
    
    # Create directory hierarchy
    local directories=(
        "$CHROOT_DIR"
        "$WORK_DIR/iso"
        "$WORK_DIR/scratch"
        "$BUILD_ROOT/cache/packages"
        "$BUILD_ROOT/logs"
        "$BUILD_ROOT/config"
    )
    
    for dir in "${directories[@]}"; do
        safe_mkdir "$dir" 755
        log_debug "Created: $dir"
    done
    
    log_success "Build directories created"
}

setup_apt_cache() {
    log_info "Setting up APT cache..."
    
    # Configure apt caching to speed up builds
    cat > "$BUILD_ROOT/config/apt-cache.conf" <<EOF
Dir::Cache::Archives "$BUILD_ROOT/cache/packages";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Languages "none";
EOF
    
    log_success "APT cache configured"
}

setup_debootstrap() {
    log_info "Initializing debootstrap environment..."
    
    # Check if chroot already exists
    if [[ -f "$CHROOT_DIR/bin/bash" ]]; then
        log_warning "Chroot already exists, skipping debootstrap"
        return 0
    fi
    
    # Create checkpoint before debootstrap
    create_checkpoint "pre_debootstrap" "$BUILD_ROOT"
    
    # Run debootstrap
    log_info "Running debootstrap (this may take 5-10 minutes)..."
    
    if debootstrap \
        --arch="$ARCH" \
        --variant=minbase \
        --include=systemd,systemd-sysv,dbus,apt-utils \
        "$DEBIAN_RELEASE" \
        "$CHROOT_DIR" \
        http://archive.ubuntu.com/ubuntu; then
        log_success "Debootstrap completed"
    else
        log_error "Debootstrap failed"
        return 1
    fi
    
    # Create post-debootstrap checkpoint
    create_checkpoint "post_debootstrap" "$BUILD_ROOT"
    
    return 0
}

configure_chroot_mounts() {
    log_info "Configuring chroot mount points..."
    
    # Setup essential mount points
    safe_mkdir "$CHROOT_DIR/proc" 555
    safe_mkdir "$CHROOT_DIR/sys" 555
    safe_mkdir "$CHROOT_DIR/dev" 755
    safe_mkdir "$CHROOT_DIR/dev/pts" 755
    safe_mkdir "$CHROOT_DIR/run" 755
    
    log_success "Mount points configured"
}

setup_network_configuration() {
    log_info "Setting up network configuration..."
    
    # Copy resolv.conf for network access
    cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"
    
    # Configure hostname
    echo "livecd" > "$CHROOT_DIR/etc/hostname"
    
    # Configure hosts file
    cat > "$CHROOT_DIR/etc/hosts" <<EOF
127.0.0.1       localhost
127.0.1.1       livecd
::1             localhost ip6-localhost ip6-loopback
EOF
    
    log_success "Network configuration complete"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== ENVIRONMENT SETUP MODULE ==="
    
    # Setup build environment
    setup_build_directories || exit 1
    setup_apt_cache || exit 1
    setup_debootstrap || exit 1
    configure_chroot_mounts || exit 1
    setup_network_configuration || exit 1
    
    # Save environment configuration
    cat > "$BUILD_ROOT/config/environment.conf" <<EOF
# Build Environment Configuration
BUILD_DATE=$(date -Iseconds)
DEBIAN_RELEASE=$DEBIAN_RELEASE
ARCHITECTURE=$ARCH
BUILD_ROOT=$BUILD_ROOT
CHROOT_DIR=$CHROOT_DIR
WORK_DIR=$WORK_DIR
EOF
    
    log_success "=== ENVIRONMENT SETUP COMPLETE ==="
    exit 0
}

main "$@"
```

## 3. base-system.sh

```bash
#!/bin/bash
#
# Base System Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Installs and configures the base system packages
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
MODULE_NAME="base-system"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"

# Base packages
readonly BASE_PACKAGES=(
    # System essentials
    "systemd" "systemd-sysv" "init" "dbus" "udev"
    "apt-utils" "software-properties-common"
    
    # Core utilities
    "bash" "dash" "coreutils" "util-linux" "mount"
    "procps" "psmisc" "findutils" "grep" "sed" "gawk"
    
    # Networking
    "iproute2" "iputils-ping" "netbase" "ifupdown"
    "network-manager" "dhcpcd5" "resolvconf"
    
    # Package management
    "apt" "dpkg" "apt-transport-https" "ca-certificates"
    "gnupg" "lsb-release" "curl" "wget"
    
    # System tools
    "sudo" "passwd" "adduser" "locales" "tzdata"
    "console-setup" "keyboard-configuration"
    
    # Hardware support
    "pciutils" "usbutils" "lshw" "dmidecode"
    "hdparm" "smartmontools"
    
    # Filesystem tools
    "e2fsprogs" "xfsprogs" "dosfstools" "ntfs-3g"
    "fdisk" "parted" "gdisk"
    
    # Compression
    "gzip" "bzip2" "xz-utils" "zstd" "lz4"
    
    # Text editors
    "vim" "nano"
    
    # Development basics
    "build-essential" "git" "python3" "perl"
)

#=============================================================================
# BASE SYSTEM FUNCTIONS
#=============================================================================

mount_chroot() {
    log_info "Mounting chroot filesystems..."
    
    mount -t proc proc "$CHROOT_DIR/proc" 2>/dev/null || true
    mount -t sysfs sys "$CHROOT_DIR/sys" 2>/dev/null || true
    mount -t devtmpfs dev "$CHROOT_DIR/dev" 2>/dev/null || true
    mount -t devpts devpts "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    mount -t tmpfs run "$CHROOT_DIR/run" 2>/dev/null || true
    
    log_success "Filesystems mounted"
}

umount_chroot() {
    log_info "Unmounting chroot filesystems..."
    
    umount "$CHROOT_DIR/run" 2>/dev/null || true
    umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    umount "$CHROOT_DIR/dev" 2>/dev/null || true
    umount "$CHROOT_DIR/sys" 2>/dev/null || true
    umount "$CHROOT_DIR/proc" 2>/dev/null || true
    
    log_success "Filesystems unmounted"
}

configure_apt_sources() {
    log_info "Configuring APT sources..."
    
    cat > "$CHROOT_DIR/etc/apt/sources.list" <<EOF
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF
    
    # Update package lists
    chroot "$CHROOT_DIR" apt-get update
    
    log_success "APT sources configured"
}

install_base_packages() {
    log_info "Installing base system packages..."
    
    # Install packages in batches
    local batch_size=10
    local installed=0
    local total=${#BASE_PACKAGES[@]}
    
    for ((i=0; i<${#BASE_PACKAGES[@]}; i+=batch_size)); do
        local batch=("${BASE_PACKAGES[@]:i:batch_size}")
        
        log_info "Installing batch $((i/batch_size + 1)): ${batch[*]}"
        
        if DEBIAN_FRONTEND=noninteractive chroot "$CHROOT_DIR" \
            apt-get install -y "${batch[@]}"; then
            installed=$((installed + ${#batch[@]}))
            log_success "Installed ${#batch[@]} packages ($installed/$total)"
        else
            log_warning "Some packages in batch failed to install"
        fi
    done
    
    log_success "Base packages installed"
}

configure_locale() {
    log_info "Configuring locale settings..."
    
    # Generate locale
    echo "en_US.UTF-8 UTF-8" > "$CHROOT_DIR/etc/locale.gen"
    chroot "$CHROOT_DIR" locale-gen
    
    # Set default locale
    echo "LANG=en_US.UTF-8" > "$CHROOT_DIR/etc/default/locale"
    
    log_success "Locale configured"
}

configure_timezone() {
    log_info "Configuring timezone..."
    
    # Set timezone to UTC
    ln -sf /usr/share/zoneinfo/UTC "$CHROOT_DIR/etc/localtime"
    echo "Etc/UTC" > "$CHROOT_DIR/etc/timezone"
    
    log_success "Timezone set to UTC"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== BASE SYSTEM MODULE ==="
    
    # Mount chroot
    mount_chroot
    
    # Configure and install base system
    configure_apt_sources || exit 1
    install_base_packages || exit 1
    configure_locale || exit 1
    configure_timezone || exit 1
    
    # Create checkpoint
    create_checkpoint "base_system_complete" "$BUILD_ROOT"
    
    # Cleanup
    umount_chroot
    
    log_success "=== BASE SYSTEM COMPLETE ==="
    exit 0
}

# Ensure cleanup on exit
trap umount_chroot EXIT

main "$@"
```

## 4. kernel-compilation.sh

```bash
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
```

## 5. package-installation.sh

```bash
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
MODULE_NAME="package-installation"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"

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
```

## 6. system-configuration.sh

```bash
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
    
    # Update initramfs
    chroot "$CHROOT_DIR" update-initramfs -u -k all
    
    # Create checkpoint
    create_checkpoint "system_configured" "$BUILD_ROOT"
    
    log_success "=== SYSTEM CONFIGURATION COMPLETE ==="
    exit 0
}

main "$@"
```

## 7. initramfs-generation.sh

```bash
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
readonly WORK_DIR="$BUILD_ROOT/work"

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

# Filesystem
zfs
overlay
squashfs
isofs
vfat

# Network (for network boot)
e1000e
r8169
virtio_net

# USB
xhci_pci
ehci_pci
uhci_hcd
usb_storage
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
    
    log_success "Live scripts created"
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
```

## 8. iso-assembly.sh

```bash
#!/bin/bash
#
# ISO Assembly Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Creates the final ISO image
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
readonly WORK_DIR="$BUILD_ROOT/work"
readonly ISO_DIR="$WORK_DIR/iso"
readonly OUTPUT_DIR="$BUILD_ROOT/output"

#=============================================================================
# ISO ASSEMBLY FUNCTIONS
#=============================================================================

prepare_iso_structure() {
    log_info "Preparing ISO structure..."
    
    # Create ISO directories
    safe_mkdir "$ISO_DIR" 755
    safe_mkdir "$ISO_DIR/casper" 755
    safe_mkdir "$ISO_DIR/isolinux" 755
    safe_mkdir "$ISO_DIR/install" 755
    safe_mkdir "$ISO_DIR/.disk" 755
    safe_mkdir "$OUTPUT_DIR" 755
    
    # Create disk info
    echo "Ubuntu ZFS LiveCD" > "$ISO_DIR/.disk/info"
    echo "https://ubuntu.com" > "$ISO_DIR/.disk/release_notes_url"
    
    # Create base structure
    touch "$ISO_DIR/ubuntu"
    
    log_success "ISO structure prepared"
}

create_squashfs() {
    log_info "Creating SquashFS filesystem..."
    
    # Clean chroot before compression
    chroot "$CHROOT_DIR" bash <<'EOF'
apt-get clean
rm -rf /tmp/* /var/tmp/*
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*.bin
rm -rf /root/.bash_history
find /var/log -type f -exec truncate -s 0 {} \;
EOF
    
    # Create SquashFS
    log_info "Compressing filesystem (this may take 10-15 minutes)..."
    
    mksquashfs "$CHROOT_DIR" "$ISO_DIR/casper/filesystem.squashfs" \
        -comp xz \
        -b 1M \
        -noappend \
        -quiet \
        -no-progress
    
    # Create filesystem manifest
    chroot "$CHROOT_DIR" dpkg-query -W > "$ISO_DIR/casper/filesystem.manifest"
    cp "$ISO_DIR/casper/filesystem.manifest" "$ISO_DIR/casper/filesystem.manifest-desktop"
    
    # Calculate filesystem size
    printf "%s\n" $(du -sx --block-size=1 "$CHROOT_DIR" | cut -f1) \
        > "$ISO_DIR/casper/filesystem.size"
    
    log_success "SquashFS created"
}

setup_bootloader() {
    log_info "Setting up bootloader..."
    
    # Copy isolinux files
    cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/isolinux/"
    cp /usr/lib/syslinux/modules/bios/*.c32 "$ISO_DIR/isolinux/" 2>/dev/null || true
    
    # Create isolinux configuration
    cat > "$ISO_DIR/isolinux/isolinux.cfg" <<'EOF'
DEFAULT live
LABEL live
  menu label ^Boot Ubuntu ZFS LiveCD
  kernel /casper/vmlinuz
  append initrd=/casper/initrd boot=casper quiet splash ---
  
LABEL live-nomodeset
  menu label ^Boot Ubuntu ZFS LiveCD (nomodeset)
  kernel /casper/vmlinuz
  append initrd=/casper/initrd boot=casper nomodeset quiet splash ---

LABEL memtest
  menu label Test memory
  kernel /install/memtest86+

LABEL hd
  menu label Boot from first hard disk
  localboot 0x80
EOF
    
    # Create GRUB configuration for UEFI
    safe_mkdir "$ISO_DIR/boot/grub" 755
    
    cat > "$ISO_DIR/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=10

menuentry "Boot Ubuntu ZFS LiveCD" {
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}

menuentry "Boot Ubuntu ZFS LiveCD (nomodeset)" {
    linux /casper/vmlinuz boot=casper nomodeset quiet splash ---
    initrd /casper/initrd
}

menuentry "Check disc for defects" {
    linux /casper/vmlinuz boot=casper integrity-check quiet splash ---
    initrd /casper/initrd
}

menuentry "Test memory" {
    linux /install/memtest86+
}
EOF
    
    log_success "Bootloader configured"
}

create_iso() {
    log_info "Creating ISO image..."
    
    local iso_name="ubuntu-zfs-livecd-$(date +%Y%m%d).iso"
    local iso_path="$OUTPUT_DIR/$iso_name"
    
    # Create ISO with xorriso
    xorriso \
        -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "Ubuntu ZFS LiveCD" \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -output "$iso_path" \
        "$ISO_DIR"
    
    # Calculate MD5sum
    md5sum "$iso_path" > "$iso_path.md5"
    
    # Display ISO information
    local iso_size=$(du -h "$iso_path" | cut -f1)
    log_success "ISO created: $iso_name ($iso_size)"
    log_success "Location: $iso_path"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== ISO ASSEMBLY MODULE ==="
    
    # Prepare and create ISO
    prepare_iso_structure || exit 1
    create_squashfs || exit 1
    setup_bootloader || exit 1
    create_iso || exit 1
    
    # Create checkpoint
    create_checkpoint "iso_complete" "$BUILD_ROOT"
    
    log_success "=== ISO ASSEMBLY COMPLETE ==="
    exit 0
}

main "$@"
```

## 9. validation.sh

```bash
#!/bin/bash
#
# Validation Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Validates the generated ISO and system integrity
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
MODULE_NAME="validation"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
readonly OUTPUT_DIR="$BUILD_ROOT/output"

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

validate_iso_exists() {
    log_info "Validating ISO existence..."
    
    local iso_count=$(find "$OUTPUT_DIR" -name "*.iso" 2>/dev/null | wc -l)
    
    if [[ $iso_count -eq 0 ]]; then
        log_error "No ISO file found in $OUTPUT_DIR"
        return 1
    fi
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    local iso_size=$(stat -c%s "$iso_file")
    local iso_size_mb=$((iso_size / 1048576))
    
    log_success "ISO found: $(basename "$iso_file") (${iso_size_mb}MB)"
    
    # Validate size
    if [[ $iso_size_mb -lt 500 ]]; then
        log_error "ISO size too small: ${iso_size_mb}MB"
        return 1
    fi
    
    if [[ $iso_size_mb -gt 4096 ]]; then
        log_warning "ISO size large: ${iso_size_mb}MB (may not fit on DVD)"
    fi
    
    return 0
}

validate_iso_integrity() {
    log_info "Validating ISO integrity..."
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    
    # Check if ISO is readable
    if ! isoinfo -d -i "$iso_file" &>/dev/null; then
        log_error "ISO is not readable or corrupted"
        return 1
    fi
    
    # Extract and validate boot files
    local temp_mount=$(mktemp -d)
    
    if mount -o loop,ro "$iso_file" "$temp_mount" 2>/dev/null; then
        # Check for essential files
        local essential_files=(
            "casper/vmlinuz"
            "casper/initrd"
            "casper/filesystem.squashfs"
            "isolinux/isolinux.bin"
        )
        
        local missing_files=0
        for file in "${essential_files[@]}"; do
            if [[ ! -f "$temp_mount/$file" ]]; then
                log_error "Missing essential file: $file"
                ((missing_files++))
            else
                log_debug "Found: $file"
            fi
        done
        
        umount "$temp_mount"
        rmdir "$temp_mount"
        
        if [[ $missing_files -gt 0 ]]; then
            return 1
        fi
    else
        log_error "Failed to mount ISO for validation"
        return 1
    fi
    
    log_success "ISO integrity validated"
    return 0
}

validate_boot_capability() {
    log_info "Validating boot capability..."
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    
    # Check for BIOS boot
    if isoinfo -d -i "$iso_file" 2>/dev/null | grep -q "El Torito"; then
        log_success "BIOS boot: ENABLED"
    else
        log_error "BIOS boot: NOT FOUND"
        return 1
    fi
    
    # Check for UEFI boot
    if isoinfo -J -i "$iso_file" -x /EFI/BOOT/BOOTX64.EFI 2>/dev/null | head -c 4 | grep -q "MZ"; then
        log_success "UEFI boot: ENABLED"
    else
        log_warning "UEFI boot: NOT FOUND (may be BIOS only)"
    fi
    
    return 0
}

generate_validation_report() {
    log_info "Generating validation report..."
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    local report_file="${iso_file%.iso}-validation.txt"
    
    {
        echo "ISO Validation Report"
        echo "===================="
        echo "Generated: $(date -Iseconds)"
        echo ""
        echo "ISO File: $(basename "$iso_file")"
        echo "Size: $(du -h "$iso_file" | cut -f1)"
        echo "MD5: $(md5sum "$iso_file" | cut -d' ' -f1)"
        echo "SHA256: $(sha256sum "$iso_file" | cut -d' ' -f1)"
        echo ""
        echo "Boot Capabilities:"
        echo "- BIOS: Supported"
        echo "- UEFI: $(isoinfo -J -i "$iso_file" -x /EFI/BOOT/BOOTX64.EFI &>/dev/null && echo "Supported" || echo "Not supported")"
        echo ""
        echo "Contents Summary:"
        isoinfo -l -i "$iso_file" 2>/dev/null | head -20
        echo ""
        echo "Validation Status: PASSED"
    } > "$report_file"
    
    log_success "Validation report: $report_file"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== VALIDATION MODULE ==="
    
    local validation_errors=0
    
    # Run all validations
    validate_iso_exists || ((validation_errors++))
    validate_iso_integrity || ((validation_errors++))
    validate_boot_capability || ((validation_errors++))
    
    if [[ $validation_errors -eq 0 ]]; then
        generate_validation_report
        log_success "=== VALIDATION PASSED ==="
        exit 0
    else
        log_error "=== VALIDATION FAILED ($validation_errors errors) ==="
        exit 1
    fi
}

main "$@"
```

## 10. finalization.sh

```bash
#!/bin/bash
#
# Finalization Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Final cleanup and build completion
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
MODULE_NAME="finalization"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
readonly OUTPUT_DIR="$BUILD_ROOT/output"

#=============================================================================
# FINALIZATION FUNCTIONS
#=============================================================================

cleanup_build_environment() {
    log_info "Cleaning up build environment..."
    
    # Unmount any remaining mounts
    local chroot_dir="$BUILD_ROOT/chroot"
    
    for mount in proc sys dev/pts dev run; do
        if mountpoint -q "$chroot_dir/$mount" 2>/dev/null; then
            umount "$chroot_dir/$mount" 2>/dev/null || true
            log_debug "Unmounted: $chroot_dir/$mount"
        fi
    done
    
    # Clean temporary files
    find "$BUILD_ROOT/work" -type f -name "*.tmp" -delete 2>/dev/null || true
    
    log_success "Build environment cleaned"
}

organize_output() {
    log_info "Organizing output files..."
    
    # Create organized structure
    safe_mkdir "$OUTPUT_DIR/iso" 755
    safe_mkdir "$OUTPUT_DIR/logs" 755
    safe_mkdir "$OUTPUT_DIR/checksums" 755
    safe_mkdir "$OUTPUT_DIR/reports" 755
    
    # Move ISO files
    mv "$OUTPUT_DIR"/*.iso "$OUTPUT_DIR/iso/" 2>/dev/null || true
    mv "$OUTPUT_DIR"/*.md5 "$OUTPUT_DIR/checksums/" 2>/dev/null || true
    
    # Copy logs
    cp "$BUILD_ROOT/logs"/* "$OUTPUT_DIR/logs/" 2>/dev/null || true
    
    # Move reports
    mv "$OUTPUT_DIR"/*-validation.txt "$OUTPUT_DIR/reports/" 2>/dev/null || true
    mv "$BUILD_ROOT"/*-report*.txt "$OUTPUT_DIR/reports/" 2>/dev/null || true
    
    log_success "Output organized"
}

generate_build_summary() {
    log_info "Generating build summary..."
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    local summary_file="$OUTPUT_DIR/build-summary.txt"
    
    {
        echo "================================"
        echo "   BUILD SUMMARY"
        echo "================================"
        echo ""
        echo "Build Date: $(date -Iseconds)"
        echo "Build Duration: $(uptime -p | sed 's/up //')"
        echo ""
        echo "OUTPUT FILES:"
        echo "-------------"
        
        if [[ -n "$iso_file" ]]; then
            echo "ISO: $(basename "$iso_file")"
            echo "Size: $(du -h "$iso_file" | cut -f1)"
            echo "MD5: $(md5sum "$iso_file" | cut -d' ' -f1)"
        fi
        
        echo ""
        echo "BUILD STATISTICS:"
        echo "-----------------"
        echo "Total Disk Used: $(du -sh "$BUILD_ROOT" | cut -f1)"
        echo "Packages Installed: $(find "$BUILD_ROOT/chroot" -name "*.deb" | wc -l)"
        echo "Build Logs: $(find "$BUILD_ROOT/logs" -type f | wc -l)"
        echo ""
        echo "NEXT STEPS:"
        echo "-----------"
        echo "1. Test ISO in virtual machine"
        echo "2. Write to USB: dd if=$iso_file of=/dev/sdX bs=4M status=progress"
        echo "3. Verify on target hardware"
        echo ""
        echo "BUILD STATUS: SUCCESS"
        echo "================================"
    } | tee "$summary_file"
    
    log_success "Build summary generated"
}

create_distribution_package() {
    log_info "Creating distribution package..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local dist_name="ubuntu-zfs-livecd-$timestamp"
    local dist_dir="$OUTPUT_DIR/$dist_name"
    
    # Create distribution directory
    safe_mkdir "$dist_dir" 755
    
    # Copy essential files
    cp "$OUTPUT_DIR/iso"/*.iso "$dist_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR/checksums"/* "$dist_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR/reports"/* "$dist_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR/build-summary.txt" "$dist_dir/" 2>/dev/null || true
    
    # Create README
    cat > "$dist_dir/README.txt" <<EOF
Ubuntu ZFS LiveCD Distribution
==============================

Version: $timestamp
Build Date: $(date)

Contents:
- $(basename "$(find "$dist_dir" -name "*.iso" | head -1)")
- MD5/SHA256 checksums
- Build and validation reports

Usage:
1. Write to USB drive:
   sudo dd if=*.iso of=/dev/sdX bs=4M status=progress

2. Boot from USB and select "Boot Ubuntu ZFS LiveCD"

3. Default credentials:
   Username: ubuntu
   Password: ubuntu

Support:
For issues or questions, please refer to the documentation.

EOF
    
    # Create tarball
    cd "$OUTPUT_DIR"
    tar czf "$dist_name.tar.gz" "$dist_name/"
    
    log_success "Distribution package created: $dist_name.tar.gz"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== FINALIZATION MODULE ==="
    
    # Perform finalization tasks
    cleanup_build_environment || log_warning "Cleanup had warnings"
    organize_output || exit 1
    generate_build_summary || exit 1
    create_distribution_package || exit 1
    
    # Final message
    log_success "=== BUILD FINALIZATION COMPLETE ==="
    log_success "ISO location: $OUTPUT_DIR/iso/"
    log_success "Distribution package: $OUTPUT_DIR/*.tar.gz"
    
    exit 0
}

main "$@"
```
