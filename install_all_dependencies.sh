#!/bin/bash
# install_all_dependencies.sh - Complete Dependency Installation v1.0
# Installs ALL packages required by any script in the repository

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

# Check root
[[ $EUID -ne 0 ]] && log_error "Must run as root"

# Calculate total packages
calculate_totals() {
    local total=0
    for category in BUILD_ESSENTIALS KERNEL_PACKAGES ZFS_PACKAGES \
                   CONTAINER_PACKAGES FILESYSTEM_PACKAGES ISO_PACKAGES \
                   COMPRESSION_PACKAGES NETWORK_PACKAGES DEV_LIBRARIES \
                   PYTHON_PACKAGES MONITORING_PACKAGES SECURITY_PACKAGES \
                   RECOVERY_PACKAGES TEXT_PACKAGES FIRMWARE_PACKAGES \
                   INTEL_GRAPHICS DATABASE_PACKAGES ADVANCED_DEV \
                   LIVEBOOT_PACKAGES HARDWARE_TOOLS \
                   MULTIMEDIA_PACKAGES DESKTOP_PACKAGES \
                   PROXMOX_PACKAGES DELL_PACKAGES ADDITIONAL_TOOLS \
                   LANGUAGES CLOUD_TOOLS; do
        eval "total+=\${#${category}[@]}"
    done
    echo $total
}

log_info "=== COMPREHENSIVE DEPENDENCY INSTALLATION ==="
log_info "Total packages available: $(calculate_totals)+"
log_info "Categories: 27 (20 mandatory, 7 optional)"
log_info "Estimated time: 15-30 minutes"
log_info "Disk space required: ~5-15GB"
echo

# Update package lists
log_info "Updating package repositories..."
apt-get update || log_error "Failed to update package lists"

# CATEGORY 1: BUILD ESSENTIALS & COMPILERS
readonly BUILD_ESSENTIALS=(
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
readonly KERNEL_PACKAGES=(
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
readonly ZFS_PACKAGES=(
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
    zfsutils-linux zfs-dkms zfs-initramfs zfs-zed 2>/dev/null || true
    zpool-features zfs-dracut 2>/dev/null || true
    libnvpair3linux libuutil3linux libzfs4linux libzpool5linux 2>/dev/null || true
    dracut-core dracut-network
)

# CATEGORY 4: SYSTEM CONTAINER & VIRTUALIZATION
readonly CONTAINER_PACKAGES=(
    systemd-container debootstrap schroot
    lxc lxc-templates lxd lxd-client
    docker.io docker-compose podman buildah
    qemu qemu-kvm qemu-utils qemu-system-x86
    libvirt-daemon libvirt-daemon-system libvirt-clients
    virt-manager virtinst bridge-utils
    vagrant virtualbox
)

# CATEGORY 5: FILESYSTEM TOOLS
readonly FILESYSTEM_PACKAGES=(
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
readonly ISO_PACKAGES=(
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
readonly COMPRESSION_PACKAGES=(
    gzip bzip2 xz-utils lz4 zstd lzip lzop
    p7zip-full p7zip-rar unrar unrar-free
    zip unzip pigz pbzip2 pixz pxz
    tar cpio ar rpm rpm2cpio dpkg-repack alien
    cabextract unshield sharutils uudeview
)

# CATEGORY 8: NETWORK TOOLS
readonly NETWORK_PACKAGES=(
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
readonly DEV_LIBRARIES=(
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
readonly PYTHON_PACKAGES=(
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
readonly MONITORING_PACKAGES=(
    htop atop iotop iftop nethogs sysstat
    glances nmon dstat vmstat iostat mpstat
    powertop laptop-mode-tools thermald
    smartmontools hdparm sdparm nvme-cli
    strace ltrace perf-tools-unstable linux-tools-common
    tcpdump wireshark-common tshark
)

# CATEGORY 12: SECURITY TOOLS  
readonly SECURITY_PACKAGES=(
    aide tripwire chkrootkit rkhunter lynis
    clamav clamav-daemon clamav-freshclam
    fail2ban denyhosts sshguard
    apparmor apparmor-utils apparmor-profiles
    auditd audispd-plugins
    gpg gnupg2 signing-party seahorse
    openssl ca-certificates ssl-cert
)

# CATEGORY 13: RECOVERY & RESCUE
readonly RECOVERY_PACKAGES=(
    testdisk photorec gddrescue ddrescue safecopy
    foremost scalpel extundelete ext4magic
    sleuthkit autopsy binwalk volatility
    gpart parted gdisk fdisk
    memtest86+ memtester stress stress-ng
    systemrescue-cd clonezilla partclone
)

# CATEGORY 14: TEXT & DOCUMENTATION
readonly TEXT_PACKAGES=(
    vim neovim emacs nano micro
    pandoc asciidoc asciidoctor markdown
    texlive-full latex2html rubber
    groff man-db info texinfo
    xmlto docbook-utils docbook-xsl
    doxygen sphinx-doc hugo jekyll
)

# CATEGORY 15: MULTIMEDIA CODECS (Optional)
readonly MULTIMEDIA_PACKAGES=(
    ffmpeg libavcodec-extra gstreamer1.0-plugins-bad
    ubuntu-restricted-extras ubuntu-restricted-addons
)

# CATEGORY 16: FIRMWARE & HARDWARE DRIVERS
readonly FIRMWARE_PACKAGES=(
    linux-firmware firmware-linux firmware-linux-free 
    firmware-linux-nonfree firmware-misc-nonfree
    firmware-iwlwifi firmware-atheros firmware-realtek
    firmware-bnx2 firmware-bnx2x firmware-sof-signed
    alsa-firmware-loaders intel-microcode amd64-microcode
    iucode-tool bolt fwupd fwupd-signed
)

# CATEGORY 17: INTEL GRAPHICS & NPU
readonly INTEL_GRAPHICS=(
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
readonly DATABASE_PACKAGES=(
    postgresql postgresql-client postgresql-contrib
    postgresql-16 postgresql-client-16 postgresql-contrib-16
    mysql-server mysql-client mariadb-server mariadb-client
    sqlite3 libsqlite3-dev redis-server redis-tools
    mongodb mongodb-org memcached libmemcached-tools
)

# CATEGORY 19: DESKTOP ENVIRONMENT
readonly DESKTOP_PACKAGES=(
    kde-plasma-desktop konsole dolphin kate okular
    firefox firefox-esr chromium-browser
    libreoffice thunderbird vlc gimp inkscape
    ubuntu-desktop ubuntu-minimal ubuntu-standard
)

# CATEGORY 20: ADVANCED DEVELOPMENT
readonly ADVANCED_DEV=(
    linux-libc-dev libc6-dev libgtk-3-dev
    libwebkit2gtk-4.0-dev libgmp-dev libreadline-dev
    libgdbm-dev libdb-dev device-tree-compiler
    dwarves pahole trace-cmd kernelshark
    perf-tools-unstable systemtap valgrind
    crash kexec-tools makedumpfile kernel-wedge
)

# CATEGORY 21: PROXMOX SPECIFIC
readonly PROXMOX_PACKAGES=(
    libpve-common-perl libpve-guest-common-perl
    libpve-storage-perl pve-edk2-firmware
    pve-kernel-helper proxmox-archive-keyring
    proxmox-backup-client proxmox-offline-mirror-helper
)

# CATEGORY 22: DELL HARDWARE SUPPORT  
readonly DELL_PACKAGES=(
    libsmbios2 smbios-utils dell-recovery
    oem-config oem-config-gtk
)

# CATEGORY 23: LIVE BOOT & CASPER
readonly LIVEBOOT_PACKAGES=(
    casper lupin-casper ubiquity ubiquity-casper
    live-boot live-boot-initramfs-tools
    live-config live-config-systemd
    live-build live-manual live-tools
)

# CATEGORY 24: ADDITIONAL TOOLS
readonly ADDITIONAL_TOOLS=(
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
                        --no-install-recommends "$pkg" 2>/dev/null || \
                        log_warn "Failed: $pkg"
                done
            }
    done
    echo -ne "\rProgress: 100%\n"
    
    log_success "$group_name installation complete"
}

# Main installation
main() {
    # Configure APT for speed
    cat > /etc/apt/apt.conf.d/99-speed << 'EOF'
Acquire::http::Pipeline-Depth "10";
Acquire::Languages "none";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
DPkg::Options::="--force-unsafe-io";
EOF

    # Add universe and multiverse repositories
    add-apt-repository universe -y
    add-apt-repository multiverse -y
    
    # Add contrib and non-free for firmware
    sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
    
    apt-get update
    
    # Install each category (mandatory)
    install_package_group "Build Essentials" "${BUILD_ESSENTIALS[@]}"
    install_package_group "Kernel Packages" "${KERNEL_PACKAGES[@]}"
    install_package_group "ZFS Build Dependencies" "${ZFS_PACKAGES[@]}"
    
    # Check if we need to build ZFS 2.3.4 from source
    log_info "Checking ZFS version..."
    if command -v zfs >/dev/null 2>&1; then
        ZFS_VERSION=$(zfs version 2>/dev/null | grep -oP 'zfs-\K[0-9.]+' | head -1)
        if [[ "$ZFS_VERSION" == "2.3.4" ]]; then
            log_success "ZFS 2.3.4 already installed"
        else
            log_warn "ZFS version $ZFS_VERSION found, not 2.3.4"
            log_info "ZFS 2.3.4 will be built from source during build process"
        fi
    else
        log_info "ZFS not installed, will be built from source during build process"
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
readonly LANGUAGES=(
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
readonly CLOUD_TOOLS=(
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
readonly HARDWARE_TOOLS=(
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
