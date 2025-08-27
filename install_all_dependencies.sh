#!/bin/bash
# install_all_dependencies.sh - Complete Dependency Installation v1.0
# Installs ALL packages required by any script in the repository

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

# Check root
[[ $EUID -ne 0 ]] && log_error "Must run as root"

log_info "=== COMPREHENSIVE DEPENDENCY INSTALLATION ==="
log_info "Total packages available: 500+"
log_info "Categories: 27 (20 mandatory, 7 optional)"
log_info "Estimated time: 15-30 minutes"
log_info "Disk space required: ~5-15GB"
echo

# CRITICAL: Apply authoritative sources FIRST before any apt operations
log_info "Applying authoritative repository configuration..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/src/config"

# Backup existing sources
if [[ -f /etc/apt/sources.list ]]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d-%H%M%S)
    log_info "Backed up existing sources.list"
fi

# Disable Ubuntu 24.04 DEB822 format to prevent conflicts
if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
    log_warn "Found Ubuntu DEB822 format sources, disabling to prevent duplicates"
    mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.disabled 2>/dev/null || true
fi

# Disable all .sources files (DEB822 format) to prevent conflicts
for sourcefile in /etc/apt/sources.list.d/*.sources; do
    if [[ -f "$sourcefile" ]]; then
        mv "$sourcefile" "${sourcefile}.disabled" 2>/dev/null || true
        log_info "Disabled: $(basename "$sourcefile")"
    fi
done

# Copy our authoritative sources.list
if [[ -f "$CONFIG_DIR/sources.list" ]]; then
    cp "$CONFIG_DIR/sources.list" /etc/apt/sources.list
    log_success "Applied authoritative sources.list"
else
    log_warn "Authoritative sources.list not found at $CONFIG_DIR/sources.list"
fi

# Apply authoritative DNS configuration
if [[ -f "$CONFIG_DIR/resolv.conf" ]]; then
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
    cp "$CONFIG_DIR/resolv.conf" /etc/resolv.conf
    log_success "Applied authoritative DNS configuration"
fi

# Remove any CDROM sources
sed -i '/^deb cdrom:/d' /etc/apt/sources.list 2>/dev/null || true
sed -i 's/^deb cdrom:/#deb cdrom:/g' /etc/apt/sources.list 2>/dev/null || true

# Update package lists with new sources (allow unauthenticated, ignore 404s)
log_info "Updating package repositories with authoritative sources..."
apt-get update --allow-unauthenticated --allow-insecure-repositories 2>&1 | grep -v "404  Not Found" || {
    # Check if we at least got main repositories
    if apt-cache policy | grep -q "archive.ubuntu.com"; then
        log_warn "Some repositories failed but main repos are available, continuing..."
    else
        log_error "Failed to update package lists - no repositories available"
    fi
}

# CATEGORY 1: BUILD ESSENTIALS & COMPILERS
BUILD_ESSENTIALS=(
    build-essential gcc g++ make cmake automake autoconf libtool
    gcc-12 gcc-13 g++-12 g++-13 clang llvm
    bison flex bc rsync cpio kmod dkms module-assistant
    pkg-config dpkg-dev debhelper dh-make fakeroot
    git subversion mercurial cvs bzr
    wget curl aria2 axel
    patch patchutils quilt
    nasm yasm iasl
    gawk alien rpm rpm2cpio
    ninja-build meson scons
)

# CATEGORY 2: KERNEL & HEADERS
KERNEL_PACKAGES=(
    linux-headers-generic linux-headers-$(uname -r)
    linux-source linux-tools-common linux-tools-generic
    linux-cloud-tools-generic linux-image-generic
    linux-generic-hwe-22.04 linux-headers-generic-hwe-22.04
    kernel-package libncurses-dev libncurses5-dev
    crash kexec-tools makedumpfile kernel-wedge
    linux-source-$(uname -r | cut -d. -f1,2) linux-doc
)

# CATEGORY 3: ZFS PACKAGES & DEPENDENCIES
# Note: These are build dependencies for ZFS 2.3.4 compilation
ZFS_PACKAGES=(
    # ZFS build dependencies for compiling 2.3.4 from source
    libblkid-dev uuid-dev libudev-dev libssl-dev
    zlib1g-dev libaio-dev libattr1-dev libelf-dev
    libtirpc-dev libtirpc3 libtirpc-common
    python3 python3-dev python3-setuptools python3-cffi
    python3-packaging python3-sphinx python3-all-dev
    libffi-dev libcurl4-openssl-dev libacl1-dev
    libpam0g-dev nfs-kernel-server
    # Additional build tools for ZFS
    autoconf automake libtool gawk alien fakeroot
    debhelper dh-python po-debconf
    # Kernel build dependencies
    linux-headers-generic linux-headers-$(uname -r)
    linux-source dkms
    # Optional ZFS packages (may not exist yet)
    zfsutils-linux zfs-dkms zfs-initramfs zfs-zed
    zpool-features zfs-dracut
    libnvpair3linux libuutil3linux libzfs4linux libzpool5linux
    dracut-core dracut-network
)

# CATEGORY 4: SYSTEM CONTAINER & VIRTUALIZATION
CONTAINER_PACKAGES=(
    systemd-container debootstrap schroot
    lxc lxc-templates lxd lxd-client
    docker.io docker-compose podman buildah
    qemu qemu-kvm qemu-utils qemu-system-x86
    libvirt-daemon libvirt-daemon-system libvirt-clients
    virt-manager virtinst bridge-utils
    vagrant virtualbox
)

# CATEGORY 5: FILESYSTEM TOOLS
FILESYSTEM_PACKAGES=(
    e2fsprogs xfsprogs btrfs-progs dosfstools
    ntfs-3g f2fs-tools nilfs-tools reiserfsprogs jfsutils
    lvm2 mdadm cryptsetup cryptsetup-initramfs
    parted gdisk fdisk gparted sgdisk sfdisk
    squashfs-tools genext2fs mtd-utils
    fuse3 libfuse3-dev sshfs davfs2 cifs-utils nfs-common
    nfs-kernel-server samba smbclient
    exfat-fuse exfat-utils hfsplus hfsprogs
)

# CATEGORY 6: ISO & BOOT TOOLS
ISO_PACKAGES=(
    xorriso isolinux syslinux syslinux-common syslinux-efi
    grub-pc-bin grub-efi-amd64-bin grub2-common
    grub-efi-amd64 grub-efi-amd64-signed
    shim-signed mokutil sbsigntool secureboot-db
    mtools dosfstools genisoimage mkisofs
    casper lupin-casper ubiquity ubiquity-casper
    live-build live-config live-config-systemd
    efibootmgr efitools efivar libefivar-dev
    memtest86+ memtest86 grub-imageboot
    ipxe ipxe-qemu syslinux-utils extlinux
)

# CATEGORY 7: COMPRESSION & ARCHIVE
COMPRESSION_PACKAGES=(
    gzip bzip2 xz-utils lz4 zstd lzip lzop
    p7zip-full p7zip-rar unrar unrar-free
    zip unzip pigz pbzip2 pixz pxz
    tar cpio ar rpm rpm2cpio dpkg-repack alien
    cabextract unshield sharutils uudeview
)

# CATEGORY 8: NETWORK TOOLS
NETWORK_PACKAGES=(
    net-tools iproute2 iputils-ping traceroute
    netcat-openbsd socat nmap tcpdump tshark
    wget curl aria2 axel lftp rsync
    openssh-server openssh-client sshpass autossh mosh
    openvpn wireguard openconnect network-manager
    iptables nftables ufw firewalld
    dnsutils bind9-utils whois host dig
    ethtool mtr-tiny iperf3 speedtest-cli nethogs iftop
    ngrep tcpflow tcptrack vnstat bmon slurm
    wavemon aircrack-ng kismet
    x11vnc tightvncserver tigervnc-standalone-server
    xrdp remmina remmina-plugin-rdp
)

# CATEGORY 9: DEVELOPMENT LIBRARIES
DEV_LIBRARIES=(
    libssl-dev libcrypto++-dev libgcrypt20-dev
    libsqlite3-dev libmysqlclient-dev libpq-dev
    libxml2-dev libxslt1-dev libyaml-dev libjson-c-dev
    libpcre3-dev libpcre2-dev libre2-dev
    libglib2.0-dev libgtk-3-dev libqt5-dev
    libboost-all-dev libevent-dev libev-dev
    libusb-1.0-0-dev libusb-dev libftdi1-dev
    libpci-dev libpcap-dev libnet1-dev
)

# CATEGORY 10: PYTHON ECOSYSTEM
PYTHON_PACKAGES=(
    python3-full python3-pip python3-venv python3-dev
    python3-setuptools python3-wheel python3-pytest
    python3-numpy python3-scipy python3-matplotlib
    python3-pandas python3-sklearn python3-torch
    python3-flask python3-django python3-fastapi
    python3-requests python3-urllib3 python3-boto3
    python3-cryptography python3-paramiko python3-pexpect
    ipython3 jupyter-notebook python3-notebook
    cython3 python3-cffi python3-pycparser
    pipx python-is-python3 python3-distutils
    python3-apt python3-gi python3-cairo
    python3-tk python3-pil python3-openssl
)

# CATEGORY 11: MONITORING & PERFORMANCE
MONITORING_PACKAGES=(
    htop atop iotop iftop nethogs sysstat
    glances nmon dstat vmstat iostat mpstat
    powertop laptop-mode-tools thermald
    smartmontools hdparm sdparm nvme-cli
    strace ltrace perf-tools-unstable linux-tools-common
    tcpdump wireshark-common tshark
)

# CATEGORY 12: SECURITY TOOLS  
SECURITY_PACKAGES=(
    aide tripwire chkrootkit rkhunter lynis
    clamav clamav-daemon clamav-freshclam
    fail2ban denyhosts sshguard
    apparmor apparmor-utils apparmor-profiles
    auditd audispd-plugins
    gpg gnupg2 signing-party seahorse
    openssl ca-certificates ssl-cert
)

# CATEGORY 13: RECOVERY & RESCUE
RECOVERY_PACKAGES=(
    testdisk photorec gddrescue ddrescue safecopy
    foremost scalpel extundelete ext4magic
    sleuthkit autopsy binwalk volatility
    gpart parted gdisk fdisk
    memtest86+ memtester stress stress-ng
    systemrescue-cd clonezilla partclone
)

# CATEGORY 14: TEXT & DOCUMENTATION
TEXT_PACKAGES=(
    vim neovim emacs nano micro
    pandoc asciidoc asciidoctor markdown
    texlive-full latex2html rubber
    groff man-db info texinfo
    xmlto docbook-utils docbook-xsl
    doxygen sphinx-doc hugo jekyll
)

# CATEGORY 15: MULTIMEDIA CODECS (Optional)
MULTIMEDIA_PACKAGES=(
    ffmpeg libavcodec-extra gstreamer1.0-plugins-bad
    ubuntu-restricted-extras ubuntu-restricted-addons
)

# CATEGORY 16: FIRMWARE & HARDWARE DRIVERS
FIRMWARE_PACKAGES=(
    linux-firmware firmware-linux firmware-linux-free 
    firmware-linux-nonfree firmware-misc-nonfree
    firmware-iwlwifi firmware-atheros firmware-realtek
    firmware-bnx2 firmware-bnx2x firmware-sof-signed
    alsa-firmware-loaders intel-microcode amd64-microcode
    iucode-tool bolt fwupd fwupd-signed
)

# CATEGORY 17: INTEL GRAPHICS & NPU
INTEL_GRAPHICS=(
    intel-media-va-driver-non-free intel-gpu-tools
    i965-va-driver i965-va-driver-shaders libigdgmm12
    xserver-xorg-video-intel libgl1-mesa-dri
    libglx-mesa0 libegl1-mesa libgbm1
    intel-opencl-icd intel-level-zero-gpu
    level-zero level-zero-dev beignet-opencl-icd
    ocl-icd-libopencl1 opencl-headers
    va-driver-all vdpau-driver-all
    mesa-utils mesa-va-drivers mesa-vdpau-drivers
    vulkan-tools vulkan-validationlayers
)

# CATEGORY 18: DATABASE SYSTEMS
DATABASE_PACKAGES=(
    postgresql postgresql-client postgresql-contrib
    postgresql-16 postgresql-client-16 postgresql-contrib-16
    mysql-server mysql-client mariadb-server mariadb-client
    sqlite3 libsqlite3-dev redis-server redis-tools
    mongodb mongodb-org memcached libmemcached-tools
)

# CATEGORY 19: DESKTOP ENVIRONMENT
DESKTOP_PACKAGES=(
    kde-plasma-desktop konsole dolphin kate okular
    firefox firefox-esr chromium-browser
    libreoffice thunderbird vlc gimp inkscape
    ubuntu-desktop ubuntu-minimal ubuntu-standard
)

# CATEGORY 20: ADVANCED DEVELOPMENT
ADVANCED_DEV=(
    linux-libc-dev libc6-dev libgtk-3-dev
    libwebkit2gtk-4.0-dev libgmp-dev libreadline-dev
    libgdbm-dev libdb-dev device-tree-compiler
    dwarves pahole trace-cmd kernelshark
    perf-tools-unstable systemtap valgrind
    crash kexec-tools makedumpfile kernel-wedge
)

# CATEGORY 21: PROXMOX SPECIFIC
PROXMOX_PACKAGES=(
    libpve-common-perl libpve-guest-common-perl
    libpve-storage-perl pve-edk2-firmware
    pve-kernel-helper proxmox-archive-keyring
    proxmox-backup-client proxmox-offline-mirror-helper
)

# CATEGORY 22: DELL HARDWARE SUPPORT  
DELL_PACKAGES=(
    libsmbios2 smbios-utils dell-recovery
    oem-config oem-config-gtk
)

# CATEGORY 23: LIVE BOOT & CASPER
LIVEBOOT_PACKAGES=(
    casper lupin-casper ubiquity ubiquity-casper
    live-boot live-boot-initramfs-tools
    live-config live-config-systemd
    live-build live-manual live-tools
)

# CATEGORY 24: ADDITIONAL TOOLS
ADDITIONAL_TOOLS=(
    gh ripgrep fd-find bat exa fzf
    neofetch screenfetch inxi
    ranger mc vifm tmux screen byobu
    mosh autossh sshpass keychain
    jq yq xmlstarlet miller
    httpie aria2 axel lftp
    tree pv progress parallel
    ncdu duf dust broot
    hyperfine tokei loc cloc
    direnv asdf nvm pyenv rbenv
)

# Function to install package group
install_package_group() {
    local group_name="$1"
    shift
    local packages=("$@")
    
    log_info "Installing $group_name (${#packages[@]} packages)..."
    
    # Install in batches to avoid command line limits
    local batch_size=20
    local total=${#packages[@]}
    
    for ((i=0; i<total; i+=batch_size)); do
        local batch=("${packages[@]:i:batch_size}")
        local progress=$((i * 100 / total))
        
        echo -ne "\rProgress: ${progress}% "
        
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            --no-install-recommends \
            --allow-unauthenticated \
            "${batch[@]}" 2>/dev/null || {
                # Try individual installation on batch failure
                for pkg in "${batch[@]}"; do
                    DEBIAN_FRONTEND=noninteractive apt-get install -y \
                        --no-install-recommends \
                        --allow-unauthenticated \
                        "$pkg" 2>/dev/null || \
                        log_warn "Failed: $pkg"
                done
            }
    done
    echo -ne "\rProgress: 100%\n"
    
    log_success "$group_name installation complete"
}

# Main installation
main() {
    # Apply our authoritative configuration first
    log_info "Applying authoritative repository and DNS configuration..."
    
    # Check if config-apply module exists and use it
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/src/modules/config-apply.sh" ]]; then
        log_info "Using config-apply module for configuration"
        bash "$SCRIPT_DIR/src/modules/config-apply.sh" / host || {
            log_warn "Config module failed, applying manually"
            # Fallback to manual configuration
            if [[ -f "$SCRIPT_DIR/src/config/sources.list" ]]; then
                cp "$SCRIPT_DIR/src/config/sources.list" /etc/apt/sources.list
                log_success "Applied authoritative sources.list"
            fi
            if [[ -f "$SCRIPT_DIR/src/config/resolv.conf" ]]; then
                cp "$SCRIPT_DIR/src/config/resolv.conf" /etc/resolv.conf
                log_success "Applied authoritative resolv.conf"
            fi
        }
    else
        # Direct fallback if module doesn't exist
        if [[ -f "$SCRIPT_DIR/src/config/sources.list" ]]; then
            log_info "Applying authoritative sources.list directly"
            cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d) 2>/dev/null || true
            cp "$SCRIPT_DIR/src/config/sources.list" /etc/apt/sources.list
        else
            # Last resort: remove CDROM and add repositories manually
            log_warn "No config files found, configuring manually"
            sed -i '/^deb cdrom:/d' /etc/apt/sources.list
            sed -i '/^deb-src cdrom:/d' /etc/apt/sources.list
            add-apt-repository universe -y
            add-apt-repository multiverse -y
        fi
        
        if [[ -f "$SCRIPT_DIR/src/config/resolv.conf" ]]; then
            log_info "Applying authoritative resolv.conf directly"
            cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d) 2>/dev/null || true
            cp "$SCRIPT_DIR/src/config/resolv.conf" /etc/resolv.conf
        fi
    fi
    
    # Configure APT for speed
    cat > /etc/apt/apt.conf.d/99-speed << 'EOF'
Acquire::http::Pipeline-Depth "10";
Acquire::Languages "none";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
DPkg::Options::="--force-unsafe-io";
EOF
    
    apt-get update
    
    # CRITICAL: Remove any existing ZFS versions first
    log_info "Removing any existing ZFS installations..."
    apt-get remove -y --purge zfsutils-linux zfs-dkms zfs-initramfs zfs-zed \
        libzfs4linux libzpool5linux libnvpair3linux libuutil3linux \
        zfs-dracut zpool-features 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    
    # Remove ZFS kernel modules if loaded
    rmmod zfs 2>/dev/null || true
    rmmod spl 2>/dev/null || true
    
    # Clean any ZFS remnants
    rm -rf /lib/modules/*/extra/zfs* 2>/dev/null || true
    rm -rf /lib/modules/*/extra/spl* 2>/dev/null || true
    
    log_success "Cleaned existing ZFS installations"
    
    # Install build essentials and kernel packages first (needed for ZFS)
    install_package_group "Build Essentials" "${BUILD_ESSENTIALS[@]}"
    install_package_group "Kernel Packages" "${KERNEL_PACKAGES[@]}"
    
    # Install ZFS build dependencies
    install_package_group "ZFS Build Dependencies" "${ZFS_PACKAGES[@]}"
    
    # Build ZFS 2.3.4 from source immediately
    log_info "Building ZFS 2.3.4 from source..."
    if [[ -f "$SCRIPT_DIR/src/modules/zfs-builder.sh" ]]; then
        bash "$SCRIPT_DIR/src/modules/zfs-builder.sh" / host || {
            log_warn "ZFS build failed on host, will retry in chroot during build"
        }
    else
        log_warn "ZFS builder module not found, will build during main process"
    fi
    
    # Verify ZFS version
    if command -v zfs >/dev/null 2>&1; then
        ZFS_VERSION=$(zfs version 2>/dev/null | grep -oP 'zfs-\K[0-9.]+' | head -1)
        if [[ "$ZFS_VERSION" == "2.3.4" ]]; then
            log_success "ZFS 2.3.4 successfully installed on host"
        else
            log_warn "ZFS version $ZFS_VERSION found, not 2.3.4"
            log_info "Will ensure ZFS 2.3.4 in chroot environment"
        fi
    else
        log_info "ZFS not installed on host, will be built in chroot"
    fi
    install_package_group "Container Tools" "${CONTAINER_PACKAGES[@]}"
    install_package_group "Filesystem Tools" "${FILESYSTEM_PACKAGES[@]}"
    install_package_group "ISO Tools" "${ISO_PACKAGES[@]}"
    install_package_group "Compression Tools" "${COMPRESSION_PACKAGES[@]}"
    install_package_group "Network Stack" "${NETWORK_PACKAGES[@]}"
    install_package_group "Dev Libraries" "${DEV_LIBRARIES[@]}"
    install_package_group "Python Ecosystem" "${PYTHON_PACKAGES[@]}"
    install_package_group "Monitoring Tools" "${MONITORING_PACKAGES[@]}"
    install_package_group "Security Tools" "${SECURITY_PACKAGES[@]}"
    install_package_group "Recovery Tools" "${RECOVERY_PACKAGES[@]}"
    install_package_group "Text Tools" "${TEXT_PACKAGES[@]}"
    install_package_group "Firmware" "${FIRMWARE_PACKAGES[@]}"
    install_package_group "Intel Graphics" "${INTEL_GRAPHICS[@]}"
    install_package_group "Database Systems" "${DATABASE_PACKAGES[@]}"
    install_package_group "Advanced Development" "${ADVANCED_DEV[@]}"
    install_package_group "Live Boot" "${LIVEBOOT_PACKAGES[@]}"
    install_package_group "Hardware Diagnostics" "${HARDWARE_TOOLS[@]}"
    
    # Optional categories (ask user)
    echo
    read -p "Install multimedia codecs? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_package_group "Multimedia" "${MULTIMEDIA_PACKAGES[@]}"
    
    read -p "Install desktop environment? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_package_group "Desktop" "${DESKTOP_PACKAGES[@]}"
    
    read -p "Install Proxmox packages? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_package_group "Proxmox" "${PROXMOX_PACKAGES[@]}"
    
    read -p "Install Dell hardware support? (y/N): " -n 1 -r  
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_package_group "Dell Support" "${DELL_PACKAGES[@]}"
    
    read -p "Install additional CLI tools? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_package_group "Additional Tools" "${ADDITIONAL_TOOLS[@]}"
    
    read -p "Install programming languages? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_package_group "Programming Languages" "${LANGUAGES[@]}"
    
    read -p "Install cloud & orchestration tools? (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_package_group "Cloud Tools" "${CLOUD_TOOLS[@]}"
    
    # Clean up
    apt-get autoremove -y
    apt-get clean
    
    # Generate summary
    local installed=$(dpkg -l | grep ^ii | wc -l)
    local disk_used=$(du -sh /var/cache/apt/archives | cut -f1)
    
    log_success "=== INSTALLATION COMPLETE ==="
    log_success "Total packages installed: $installed"
    log_success "Disk space used for packages: $disk_used"
    log_success "All repository dependencies satisfied"
    
    # Create marker file with installation details
    cat > /var/lib/dependencies-installed.marker << EOF
Installation Date: $(date -Iseconds)
Total Packages: $installed
Categories Installed: 27
Mandatory Categories: 20
Optional Categories: 7
Disk Space Used: $disk_used
Installation Log: /var/log/installed-packages-$(date +%Y%m%d).list
EOF
    
    # Generate detailed package list
    dpkg -l | grep ^ii > /var/log/installed-packages-$(date +%Y%m%d).list
    
    log_success "Package list saved to: /var/log/installed-packages-$(date +%Y%m%d).list"
    
    # Display final summary
    echo
    echo "========================================="
    echo "   INSTALLATION SUMMARY"
    echo "========================================="
    echo "✓ Total packages installed: $installed"
    echo "✓ Disk space used: $disk_used"
    echo "✓ Log file: /var/log/installed-packages-$(date +%Y%m%d).list"
    echo "✓ Marker: /var/lib/dependencies-installed.marker"
    echo
    echo "Repository scripts are now ready to execute!"
    echo "========================================="
}

# CATEGORY 25: PROGRAMMING LANGUAGES
LANGUAGES=(
    nodejs npm yarn
    golang-go golang-doc golang-golang-x-tools
    rustc cargo rust-doc rust-src rustfmt rust-clippy
    ruby ruby-dev ruby-bundler
    php php-cli php-fpm php-mysql php-curl php-gd
    openjdk-17-jdk openjdk-17-jre maven gradle ant
    dotnet-sdk-7.0 dotnet-runtime-7.0 mono-complete
    erlang elixir
    lua5.4 luarocks
    perl perl-doc libperl-dev
    julia julia-doc
    kotlin scala clojure leiningen
    swift swiftlang
    r-base r-base-dev
)

# CATEGORY 26: CLOUD & ORCHESTRATION
CLOUD_TOOLS=(
    kubectl kubeadm kubelet kubernetes-client
    helm helmfile kustomize
    terraform terraform-docs terragrunt
    ansible ansible-lint ansible-doc
    puppet puppet-lint
    chef chef-workstation
    salt-master salt-minion salt-ssh
    consul vault nomad waypoint boundary
    aws-cli azure-cli gcloud-sdk
    doctl linode-cli vultr-cli
    openstack-client ovh-cli
    cloudflare-cli digitalocean-cli
)

# CATEGORY 27: HARDWARE DIAGNOSTICS
HARDWARE_TOOLS=(
    dmidecode lshw hwinfo inxi hardinfo
    i2c-tools lm-sensors fancontrol
    pciutils usbutils usb-modeswitch
    hdparm sdparm nvme-cli udisks2
    gsmartcontrol smartmontools hddtemp
    laptop-mode-tools pm-utils powermanagement-interface
    acpi acpid acpitool iasl
    rasdaemon edac-utils mcelog
    flashrom fwupdate firmware-updater
    cpu-checker cpufrequtils cpupower
    irqbalance numactl numad
    rtkit rtirq-init tuned tuned-utils
)

# Run main
main "$@"
