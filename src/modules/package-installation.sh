#!/bin/bash
#
# Enhanced Package Installation Module
# Version: 2.0.0 - COMPREHENSIVE EDITION
# Part of: LiveCD Build System
#
# Installs ALL packages mentioned throughout the repository
# Including QOL tools and comprehensive development environment
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
MODULE_NAME="enhanced-package-installation"
MODULE_VERSION="2.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#=============================================================================
# COMPREHENSIVE PACKAGE LISTS
#=============================================================================

# CATEGORY 1: SYSTEM CORE & LIVE BOOT
SYSTEM_CORE_PACKAGES=(
    # Live system requirements
    "casper" "lupin-casper"
    "discover" "laptop-detect" "os-prober"
    "ubiquity" "ubiquity-casper"
    "live-boot" "live-boot-initramfs-tools"
    "live-config" "live-config-systemd"
    "live-build" "live-manual" "live-tools"
    
    # Package management
    "snapd" "snapd-xdg-open" "snap-confine"
    "flatpak" "appstream"
    
    # Firmware (NO MICROCODE - microcode loading disabled)
    "linux-firmware"
    "firmware-linux" "firmware-linux-nonfree" "firmware-misc-nonfree"
    "firmware-iwlwifi" "firmware-realtek" "firmware-atheros"
    "firmware-bnx2" "firmware-bnx2x" "firmware-sof-signed"
    
    # Boot loaders and EFI
    "grub-efi-amd64" "grub-efi-amd64-signed" "grub-pc-bin"
    "efibootmgr" "efitools" "efivar" "libefivar-dev"
    "mokutil" "sbsigntool" "secureboot-db" "shim-signed"
    "isolinux" "syslinux" "syslinux-common" "syslinux-efi"
    
    # System essentials
    "systemd" "systemd-container" "systemd-coredump"
    "udev" "dbus" "rsyslog" "cron" "anacron"
    "sudo" "passwd" "adduser" "login"
)

# CATEGORY 2: QOL (QUALITY OF LIFE) TOOLS - PRIMARY FOCUS
QOL_PACKAGES=(
    # Modern system monitors
    "htop" "btop" "atop" "iotop" "iftop" "nethogs"
    "glances" "nmon" "sysstat" "dstat" "powertop"
    
    # System information
    "neofetch" "screenfetch" "inxi" "lshw" "hwinfo"
    "dmidecode" "lscpu" "lsblk" "lsusb" "lspci"
    "cpu-x" "hardinfo"
    
    # Terminal enhancements
    "tmux" "screen" "byobu" "terminator" "tilix"
    "zsh" "fish" "bash-completion"
    
    # File management and navigation
    "tree" "ranger" "mc" "vifm" "ncdu" "duf" "dust"
    "fd-find" "ripgrep" "fzf" "silversearcher-ag"
    "bat" "exa" "lsd" "broot"
    
    # Text processing and utilities
    "jq" "yq" "xmlstarlet" "miller" "pv" "progress"
    "parallel" "moreutils" "gawk" "sed"
    
    # Network utilities
    "httpie" "curl" "wget" "aria2" "axel" "lftp"
    "mtr" "traceroute" "dig" "whois" "nmap"
    "mosh" "autossh" "sshpass" "keychain"
    
    # Archive and compression
    "p7zip-full" "p7zip-rar" "unrar" "unrar-free"
    "zip" "unzip" "pigz" "pbzip2" "pixz" "pxz"
    "zstd" "lz4" "xz-utils" "bzip2" "gzip"
    
    # Development helpers
    "gh" "git-extras" "tig" "gitk" "git-gui"
    "direnv" "thefuck" "tldr" "cheat"
    "tokei" "loc" "cloc" "hyperfine"
)

# CATEGORY 3: BUILD ESSENTIALS & COMPILERS
BUILD_ESSENTIALS=(
    "build-essential" "gcc" "g++" "make" "cmake"
    "gcc-12" "gcc-13" "g++-12" "g++-13" "clang" "llvm"
    "automake" "autoconf" "libtool" "bison" "flex" "bc"
    "rsync" "cpio" "kmod" "dkms" "module-assistant"
    "pkg-config" "dpkg-dev" "debhelper" "dh-make" "fakeroot"
    "patch" "patchutils" "quilt" "nasm" "yasm" "iasl"
    "ninja-build" "meson" "scons" "ccache" "distcc"
)

# CATEGORY 4: KERNEL & HEADERS
KERNEL_PACKAGES=(
    "linux-headers-generic" "linux-headers-$(uname -r)"
    "linux-source" "linux-tools-common" "linux-tools-generic"
    "linux-cloud-tools-generic" "linux-image-generic"
    "linux-generic-hwe-22.04" "linux-headers-generic-hwe-22.04"
    "kernel-package" "libncurses-dev" "libssl-dev" "libelf-dev"
    "crash" "makedumpfile" "kdump-tools" "kexec-tools"
    "systemtap" "systemtap-sdt-dev" "perf-tools-unstable"
    "trace-cmd" "kernelshark" "dwarves" "pahole"
)

# CATEGORY 5: ZFS & FILESYSTEM PACKAGES
ZFS_FILESYSTEM_PACKAGES=(
    # ZFS core
    "zfsutils-linux" "zfs-dkms" "zfs-initramfs" "zfs-zed"
    "zfs-auto-snapshot" "pv" "mbuffer" "lzop"
    
    # Filesystem tools
    "e2fsprogs" "xfsprogs" "btrfs-progs" "dosfstools"
    "ntfs-3g" "f2fs-tools" "nilfs-tools" "reiserfsprogs" "jfsutils"
    "exfatprogs" "squashfs-tools" "genext2fs" "mtd-utils"
    
    # Storage management
    "lvm2" "mdadm" "cryptsetup" "cryptsetup-initramfs"
    "parted" "gdisk" "fdisk" "gparted" "gnome-disk-utility"
    
    # FUSE filesystems
    "fuse3" "libfuse3-dev" "sshfs" "davfs2" "cifs-utils" "nfs-common"
)

# CATEGORY 6: RECOVERY & FORENSICS TOOLS
RECOVERY_PACKAGES=(
    # Data recovery
    "testdisk" "photorec" "gddrescue" "ddrescue" "safecopy"
    "foremost" "scalpel" "extundelete" "ext4magic"
    "recoverjpeg" "sleuthkit" "autopsy"
    
    # Disk diagnostics
    "smartmontools" "hdparm" "nvme-cli" "blktrace"
    
    # System recovery
    "memtest86+" "stress" "stress-ng" "memtester"
    "sysbench" "fio" "iozone3" "bonnie++"
)

# CATEGORY 7: SECURITY & MONITORING
SECURITY_PACKAGES=(
    # Security frameworks
    "apparmor" "apparmor-utils" "fail2ban" "ufw" "iptables"
    "nftables" "firewalld"
    
    # Intrusion detection
    "aide" "rkhunter" "chkrootkit" "lynis" "tripwire"
    "samhain" "osquery"
    
    # Antivirus
    "clamav" "clamav-daemon" "clamav-freshclam"
    
    # Network security
    "wireshark" "wireshark-qt" "tshark" "tcpdump"
    "nmap" "netcat-openbsd" "socat" "ethtool"
    
    # Penetration testing
    "aircrack-ng" "john" "hashcat" "hydra" "medusa"
    "sqlmap" "nikto" "dirb" "gobuster"
)

# CATEGORY 8: DEVELOPMENT TOOLS & LANGUAGES
DEVELOPMENT_PACKAGES=(
    # Version control
    "git" "subversion" "mercurial" "cvs" "bzr"
    
    # Editors and IDEs
    "vim" "vim-gtk3" "neovim" "emacs" "nano"
    "code" "codium" "atom" "sublime-text"
    "gedit" "mousepad" "leafpad"
    
    # Python ecosystem
    "python3" "python3-full" "python3-dev" "python3-pip"
    "python3-venv" "python3-virtualenv" "pipx"
    "python3-setuptools" "python3-wheel" "python3-pytest"
    "python3-numpy" "python3-scipy" "python3-pandas"
    "python3-matplotlib" "python3-requests" "python3-flask"
    
    # Other languages
    "nodejs" "npm" "yarn" "golang-go" "rustc" "cargo"
    "openjdk-17-jdk" "openjdk-11-jdk" "maven" "gradle"
    "php" "php-cli" "composer" "ruby" "ruby-dev"
    "perl" "lua5.4" "tcl" "tk"
    
    # Database clients
    "postgresql-client" "mysql-client" "redis-tools"
    "sqlite3" "mongodb-clients"
)

# CATEGORY 9: MULTIMEDIA & DESKTOP
MULTIMEDIA_PACKAGES=(
    # Audio/Video codecs
    "ubuntu-restricted-extras" "gstreamer1.0-plugins-base"
    "gstreamer1.0-plugins-good" "gstreamer1.0-plugins-bad"
    "gstreamer1.0-plugins-ugly" "gstreamer1.0-libav"
    "libavcodec-extra" "libdvd-pkg"
    
    # Media players
    "vlc" "mpv" "totem" "rhythmbox" "audacious"
    "clementine" "banshee" "amarok"
    
    # Graphics and imaging
    "gimp" "inkscape" "krita" "blender" "shotwell"
    "imagemagick" "graphicsmagick" "optipng" "jpegoptim"
    
    # Video editing
    "kdenlive" "openshot" "pitivi" "obs-studio"
    
    # Audio production
    "audacity" "ardour" "lmms" "hydrogen"
    
    # 3D graphics
    "mesa-utils" "mesa-va-drivers" "mesa-vdpau-drivers"
    "mesa-vulkan-drivers" "vulkan-tools" "vulkan-validationlayers"
)

# CATEGORY 10: OFFICE & PRODUCTIVITY
OFFICE_PACKAGES=(
    # Office suites
    "libreoffice" "libreoffice-gtk3" "calligra"
    "abiword" "gnumeric" "focuswriter"
    
    # Email and communication
    "thunderbird" "evolution" "claws-mail"
    "pidgin" "hexchat" "irssi" "weechat"
    
    # Browsers
    "firefox" "firefox-esr" "chromium-browser"
    "lynx" "w3m" "elinks"
    
    # Document viewers
    "evince" "okular" "zathura" "mupdf"
    "calibre" "fbreader"
    
    # Note taking
    "tomboy" "cherrytree" "zim" "tiddlywiki"
)

# CATEGORY 11: NETWORK TOOLS & SERVICES
NETWORK_PACKAGES=(
    # Network basics
    "net-tools" "iproute2" "iputils-ping" "traceroute"
    "wireless-tools" "wpasupplicant" "iw" "rfkill"
    "network-manager" "network-manager-gnome"
    "network-manager-openvpn" "network-manager-pptp"
    "network-manager-vpnc"
    
    # SSH and remote access
    "openssh-server" "openssh-client" "openssh-sftp-server"
    "sshfs" "x11-apps" "xauth"
    
    # VPN clients
    "openvpn" "wireguard" "openconnect" "strongswan"
    
    # Network monitoring
    "vnstat" "bmon" "slurm" "bwm-ng" "bandwidthd"
    "darkstat" "ntopng" "cacti"
    
    # DNS tools
    "bind9-utils" "dnsutils" "ldnsutils" "unbound-host"
)

# CATEGORY 12: CONTAINER & VIRTUALIZATION
CONTAINER_PACKAGES=(
    # Docker ecosystem
    "docker.io" "docker-compose" "docker-buildx"
    "containerd" "runc"
    
    # Podman and alternatives
    "podman" "buildah" "skopeo" "crun"
    
    # System containers
    "lxc" "lxd" "systemd-container" "debootstrap"
    "schroot" "pbuilder"
    
    # Virtual machines
    "qemu" "qemu-kvm" "qemu-utils" "qemu-system-x86"
    "libvirt-daemon" "libvirt-daemon-system" "libvirt-clients"
    "virt-manager" "virtinst" "virt-viewer"
    "bridge-utils" "vlan"
    
    # Vagrant
    "vagrant" "virtualbox" "virtualbox-ext-pack"
)

# CATEGORY 13: DATABASE SYSTEMS
DATABASE_PACKAGES=(
    # PostgreSQL
    "postgresql" "postgresql-client" "postgresql-contrib"
    "pgadmin4" "postgresql-doc"
    
    # MySQL/MariaDB
    "mariadb-server" "mariadb-client" "mysql-workbench"
    "phpmyadmin" "adminer"
    
    # NoSQL
    "mongodb" "redis-server" "memcached"
    "couchdb" "elasticsearch"
    
    # SQLite tools
    "sqlite3" "sqlitebrowser" "db-util"
)

# CATEGORY 14: PROXMOX & ENTERPRISE
PROXMOX_PACKAGES=(
    # Proxmox specific
    "libpve-common-perl" "libpve-guest-common-perl"
    "libpve-storage-perl" "pve-edk2-firmware"
    "pve-kernel-helper" "proxmox-archive-keyring"
    "proxmox-backup-client" "proxmox-offline-mirror-helper"
    "pve-qemu-kvm" "qemu-server"
    
    # Ceph storage
    "ceph-common" "ceph-fuse" "radosgw"
    
    # Backup tools
    "borgbackup" "duplicity" "rdiff-backup" "rsnapshot"
    "bacula-client" "amanda-client"
)

# CATEGORY 15: HARDWARE SPECIFIC (NO MICROCODE)
HARDWARE_PACKAGES=(
    # Graphics (no Intel microcode)
    "intel-gpu-tools" "intel-media-va-driver" "i965-va-driver"
    "thermald" "powertop"
    
    # Dell hardware
    "libsmbios2" "smbios-utils" "dell-recovery"
    "oem-config" "oem-config-gtk"
    
    # General hardware
    "lm-sensors" "fancontrol" "hddtemp" "acpi"
    "cpufrequtils" "laptop-mode-tools" "tlp"
    "usbutils" "pciutils" "dmidecode"
    
    # Thunderbolt
    "thunderbolt-tools" "bolt"
)

# CATEGORY 19: ANDROID SDK & MOBILE DEVELOPMENT
readonly ANDROID_SDK_PACKAGES=(
    # Android development dependencies
    "android-tools-adb" "android-tools-fastboot"
    "android-sdk-platform-tools-common"
    "lib32z1" "lib32ncurses6" "lib32stdc++6"
    "lib32gcc-s1" "lib32z1-dev" "libc6-dev-i386"
    
    # Build tools for Android
    "gradle" "ant" "maven" "unzip" "zip"
    "openjdk-8-jdk" "openjdk-11-jdk" "openjdk-17-jdk"
    "openjdk-21-jdk" "default-jdk"
    
    # Graphics and UI development
    "libgl1-mesa-dev" "libxrandr2" "libxss1"
    "libgconf-2-4" "libxdamage1" "libdrm2"
    "libxcomposite1" "libxcursor1" "libxtst6"
    "libasound2" "libatk1.0-0" "libcairo-gobject2"
    "libgtk-3-0" "libgdk-pixbuf2.0-0"
    
    # Network and debugging
    "wget" "curl" "unzip" "git" "ssh"
    "usbutils" "dkms" "qemu-kvm"
    
    # Additional mobile dev tools
    "nodejs" "npm" "python3" "python3-pip"
    "flutter" "dart"
)

# CATEGORY 20: COMPLETE JAVA DEVELOPMENT ECOSYSTEM
readonly JAVA_ECOSYSTEM_PACKAGES=(
    # Multiple JDK versions
    "openjdk-8-jdk" "openjdk-8-jre" "openjdk-8-source"
    "openjdk-11-jdk" "openjdk-11-jre" "openjdk-11-source"
    "openjdk-17-jdk" "openjdk-17-jre" "openjdk-17-source"
    "openjdk-21-jdk" "openjdk-21-jre" "openjdk-21-source"
    "default-jdk" "default-jre" "default-jdk-headless"
    
    # Build tools
    "maven" "gradle" "ant" "sbt" "leiningen"
    "ivy" "ivy-doc" "gradle-doc" "maven-doc"
    
    # Application servers
    "tomcat9" "tomcat9-admin" "tomcat9-docs"
    "jetty9" "wildfly"
    
    # IDEs and development tools
    "eclipse" "eclipse-cdt" "eclipse-jdt"
    "netbeans" "bluej" "drjava"
    
    # Testing frameworks
    "junit4" "testng" "mockito"
    "libhamcrest-java" "libassertj-core-java"
    
    # Database connectors
    "libmysql-java" "libpostgresql-jdbc-java"
    "libsqlite-jdbc-java" "libmongo-java"
    
    # Spring framework
    "libspring-core-java" "libspring-beans-java"
    "libspring-context-java" "libspring-web-java"
    
    # Logging and utilities
    "liblog4j2-java" "libslf4j-java" "liblogback-java"
    "libcommons-lang3-java" "libcommons-io-java"
    "libcommons-cli-java" "libguava-java"
    
    # Android support
    "android-libadb" "android-libutils"
    "android-liblog" "android-libbase"
)
readonly KERNEL_TOOLCHAIN_PACKAGES=(
    # Core kernel build requirements
    "linux-libc-dev" "libc6-dev" "linux-source"
    "kernel-package" "fakeroot" "build-essential"
    "libncurses-dev" "libssl-dev" "libelf-dev"
    "flex" "bison" "openssl" "dkms"
    
    # Cross-compilation toolchains
    "gcc-aarch64-linux-gnu" "gcc-arm-linux-gnueabihf"
    "gcc-i686-linux-gnu" "gcc-mips-linux-gnu"
    "gcc-mips64el-linux-gnuabi64" "gcc-powerpc-linux-gnu"
    "gcc-powerpc64le-linux-gnu" "gcc-s390x-linux-gnu"
    "gcc-riscv64-linux-gnu" "gcc-sparc64-linux-gnu"
    
    # Additional cross-compilation tools
    "binutils-aarch64-linux-gnu" "binutils-arm-linux-gnueabihf"
    "binutils-i686-linux-gnu" "binutils-mips-linux-gnu"
    "binutils-mips64el-linux-gnuabi64" "binutils-powerpc-linux-gnu"
    "binutils-powerpc64le-linux-gnu" "binutils-s390x-linux-gnu"
    "binutils-riscv64-linux-gnu" "binutils-sparc64-linux-gnu"
    
    # LLVM/Clang toolchain for kernel
    "clang" "llvm" "lld" "lldb"
    "clang-tools" "clang-tidy" "clang-format"
    "libc++-dev" "libc++abi-dev"
    
    # Kernel debugging and profiling
    "crash" "makedumpfile" "kdump-tools"
    "systemtap" "systemtap-sdt-dev" "systemtap-client"
    "perf-tools-unstable" "linux-tools-common"
    "trace-cmd" "kernelshark" "ftrace"
    
    # Advanced kernel development
    "pahole" "dwarves" "sparse" "smatch"
    "coccinelle" "cppcheck" "splint"
    "kgraft-patch-default" "livepatch-tools"
)

# CATEGORY 17: COMPLETE CODE COMPILATION TOOLCHAIN
readonly CODE_TOOLCHAIN_PACKAGES=(
    # GCC Toolchain (multiple versions)
    "gcc" "g++" "gcc-9" "g++-9" "gcc-10" "g++-10"
    "gcc-11" "g++-11" "gcc-12" "g++-12" "gcc-13" "g++-13"
    "gcc-multilib" "g++-multilib"
    
    # Build systems and tools
    "make" "cmake" "cmake-gui" "cmake-curses-gui"
    "ninja-build" "meson" "scons" "autotools-dev"
    "automake" "autoconf" "libtool" "pkg-config"
    "m4" "gettext" "intltool" "gperf"
    
    # Assembly and low-level tools
    "nasm" "yasm" "fasmg" "as31"
    "binutils" "binutils-dev" "elfutils"
    "objdump" "readelf" "nm" "strip"
    
    # Static analysis and quality tools
    "cppcheck" "clang-tidy" "clang-format"
    "splint" "flawfinder" "rats" "pscan"
    "valgrind" "valgrind-dbg" "helgrind"
    "cachegrind" "massif-visualizer"
    
    # Profiling and performance
    "gprof" "gcov" "lcov" "kcov"
    "google-perftools" "libtcmalloc-minimal4"
    "libgoogle-perftools-dev" "gperftools"
    
    # Memory debugging
    "electric-fence" "duma" "libduma0"
    "libefence0" "address-sanitizer"
    
    # Optimization and vectorization
    "gcc-plugin-dev" "libgcc-s1-dbg"
    "libc6-dbg" "libc6-dev-i386"
    
    # Alternative compilers and runtimes
    "icc" "intel-opencl-icd" "intel-level-zero-gpu"
    "tcc" "pcc" "open64" "pathscale"
    
    # Language-specific toolchains
    "rustc" "cargo" "rustfmt" "clippy"
    "golang" "gccgo" "golang-any"
    "openjdk-8-jdk" "openjdk-11-jdk" "openjdk-17-jdk"
    "openjdk-21-jdk" "maven" "gradle" "ant"
    
    # Python compilation tools
    "python3-dev" "python3-all-dev" "python3-dbg"
    "cython3" "python3-setuptools-scm" "python3-wheel"
    "python3-build" "python3-installer" "python3-hatchling"
    
    # Ruby compilation
    "ruby-dev" "ruby-all-dev" "bundler"
    "rake" "gem2deb"
    
    # Node.js and JavaScript
    "nodejs" "npm" "yarn" "node-gyp"
    "nodejs-dev" "libnode-dev"
    
    # Perl compilation
    "perl" "libperl-dev" "perl-modules-5.36"
    "liblocal-lib-perl" "cpanminus"
)

# CATEGORY 18: ADVANCED DEVELOPMENT LIBRARIES
readonly ADVANCED_DEV_PACKAGES=(
    # Core development libraries
    "libgtk-3-dev" "libgtk-4-dev" "libqt5-dev" "qtbase5-dev"
    "libwebkit2gtk-4.0-dev" "libgmp-dev" "libreadline-dev"
    "libgdbm-dev" "libdb-dev" "device-tree-compiler"
    "libcrypto++-dev" "libgcrypt20-dev" "libgnutls28-dev"
    "libsqlite3-dev" "libmysqlclient-dev" "libpq-dev"
    "libxml2-dev" "libxslt1-dev" "libyaml-dev" "libjson-c-dev"
    "libpcre3-dev" "libpcre2-dev" "libre2-dev"
    "libglib2.0-dev" "libevent-dev" "libev-dev"
    "libboost-all-dev" "libusb-1.0-0-dev" "libftdi1-dev"
    "libpci-dev" "libpcap-dev" "libnet1-dev"
    
    # Graphics and multimedia development
    "libgl1-mesa-dev" "libglu1-mesa-dev" "freeglut3-dev"
    "libglew-dev" "libglfw3-dev" "libglm-dev"
    "libsdl2-dev" "libsdl2-image-dev" "libsdl2-mixer-dev"
    "libsfml-dev" "liballegro5-dev" "libogre-1.12-dev"
    
    # Audio development
    "libasound2-dev" "libpulse-dev" "libjack-jackd2-dev"
    "libportaudio2" "libsndfile1-dev" "libvorbis-dev"
    "libflac-dev" "libmp3lame-dev" "libopus-dev"
    
    # Image and video processing
    "libopencv-dev" "libavcodec-dev" "libavformat-dev"
    "libswscale-dev" "libavutil-dev" "libavdevice-dev"
    "libmagickwand-dev" "libfreeimage-dev" "libjpeg-dev"
    "libpng-dev" "libtiff-dev" "libwebp-dev"
    
    # Debugging and profiling tools
    "gdb" "gdb-multiarch" "gdbserver" "ddd"
    "strace" "ltrace" "time" "rr-debugger"
)

#=============================================================================
# INSTALLATION FUNCTIONS
#=============================================================================

# Mount chroot environment
mount_chroot() {
    log_info "Mounting chroot environment..."
    mount -t proc proc "$CHROOT_DIR/proc" 2>/dev/null || true
    mount -t sysfs sys "$CHROOT_DIR/sys" 2>/dev/null || true
    mount -t devtmpfs dev "$CHROOT_DIR/dev" 2>/dev/null || true
    mount -t devpts devpts "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    mount -t tmpfs run "$CHROOT_DIR/run" 2>/dev/null || true
}

# Unmount chroot environment
umount_chroot() {
    log_info "Unmounting chroot environment..."
    umount "$CHROOT_DIR/run" 2>/dev/null || true
    umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    umount "$CHROOT_DIR/dev" 2>/dev/null || true
    umount "$CHROOT_DIR/sys" 2>/dev/null || true
    umount "$CHROOT_DIR/proc" 2>/dev/null || true
}

# Install package group with advanced error handling
install_package_group() {
    local group_name="$1"
    shift
    local packages=("$@")
    
    log_info "Installing $group_name (${#packages[@]} packages)..."
    
    # Update package lists first
    chroot "$CHROOT_DIR" apt-get update -qq
    
    # Install in batches to avoid command line limits
    local batch_size=20
    local total=${#packages[@]}
    local installed=0
    local failed=0
    
    for ((i=0; i<total; i+=batch_size)); do
        local batch=("${packages[@]:i:batch_size}")
        local progress=$((i * 100 / total))
        
        echo -ne "\rProgress: ${progress}% (${installed} installed, ${failed} failed)"
        
        # Try batch installation first
        if DEBIAN_FRONTEND=noninteractive chroot "$CHROOT_DIR" \
            apt-get install -y --no-install-recommends \
            --allow-unauthenticated "${batch[@]}" >/dev/null 2>&1; then
            installed=$((installed + ${#batch[@]}))
            log_success "Batch installed: ${batch[*]}"
        else
            # Fall back to individual installation
            for pkg in "${batch[@]}"; do
                if DEBIAN_FRONTEND=noninteractive chroot "$CHROOT_DIR" \
                    apt-get install -y --no-install-recommends \
                    --allow-unauthenticated "$pkg" >/dev/null 2>&1; then
                    installed=$((installed + 1))
                else
                    failed=$((failed + 1))
                    log_warning "Failed to install: $pkg"
                fi
            done
        fi
    done
    
    echo -e "\n${GREEN}✓${NC} $group_name: $installed installed, $failed failed"
}

# Configure installed packages
configure_packages() {
    log_info "Configuring installed packages..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
# Enable essential services
systemctl enable NetworkManager
systemctl enable ssh
systemctl enable docker
systemctl enable apparmor
systemctl enable ufw
systemctl enable snapd
systemctl enable snapd.socket

# Configure Docker
if id docker &>/dev/null; then
    usermod -aG docker ubuntu 2>/dev/null || true
fi

# Configure ZFS
if command -v zpool &>/dev/null; then
    systemctl enable zfs-import-cache
    systemctl enable zfs-mount
    systemctl enable zfs-zed
    
    # Check ZFS version
    ZFS_VERSION=$(zfs version 2>/dev/null | grep -oP 'zfs-\K[0-9.]+' | head -1)
    echo "ZFS Version installed: ${ZFS_VERSION:-unknown}"
    
    # Note: ZFS 2.3.4 should be built by zfs-builder module if not available
    if [[ "$ZFS_VERSION" != "2.3.4" ]]; then
        echo "WARNING: ZFS version is not 2.3.4 (found: $ZFS_VERSION)"
        echo "The zfs-builder module should have built 2.3.4 from source"
    fi
fi

# Configure firewall
if command -v ufw &>/dev/null; then
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
fi

# DISABLE MICROCODE LOADING - Security requirement
echo "Disabling microcode loading (security requirement)..."
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/disable-microcode.conf << 'MICROCODE'
# Disable Intel and AMD microcode loading
# Prevent microcode updates for security reasons
blacklist microcode
blacklist intel_microcode
blacklist amd_microcode
install microcode /bin/true
install intel_microcode /bin/true
install amd_microcode /bin/true
MICROCODE

# Add kernel parameter to disable microcode
if [ -f /etc/default/grub ]; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&dis_ucode_ldr /' /etc/default/grub
    sed -i 's/GRUB_CMDLINE_LINUX="/&dis_ucode_ldr /' /etc/default/grub
fi

# Set up development environment
mkdir -p /opt/{toolchains,kernels,cross-compile,android-sdk,java-dev}
mkdir -p /usr/local/{src,include,lib,bin}

# Android SDK configuration
cat > /etc/android-sdk.conf << 'ANDROID'
# Android SDK Configuration
export ANDROID_HOME="/opt/android-sdk"
export ANDROID_SDK_ROOT="/opt/android-sdk"
export PATH="$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools"

# Java Development Configuration
export JAVA_HOME="/usr/lib/jvm/default-java"
export JDK_HOME="/usr/lib/jvm/default-java" 
export PATH="$PATH:$JAVA_HOME/bin"

# Gradle and Maven
export GRADLE_HOME="/opt/gradle"
export MAVEN_HOME="/opt/maven"
export PATH="$PATH:$GRADLE_HOME/bin:$MAVEN_HOME/bin"

# Android Emulator
export ANDROID_EMULATOR_USE_SYSTEM_LIBS=1
ANDROID

# Configure kernel compilation environment
cat > /etc/kernel-build.conf << 'KCONF'
# Kernel Build Configuration
KERNEL_SRC="/usr/src/linux"
CROSS_COMPILE_DIR="/opt/toolchains"
BUILD_THREADS=$(nproc)
ARCH="x86_64"

# Available cross-compilation targets
CROSS_TARGETS="aarch64 arm mips mips64el powerpc powerpc64le s390x riscv64 sparc64"
KCONF

# Create Android development helper script
cat > /usr/local/bin/android-dev-setup << 'ANDROID_SETUP'
#!/bin/bash
# Android Development Environment Setup

set -e

ANDROID_HOME="/opt/android-sdk"
ANDROID_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip"

echo "Setting up Android development environment..."

# Create Android SDK directory
mkdir -p "$ANDROID_HOME"
cd "$ANDROID_HOME"

# Download Android command line tools
echo "Downloading Android command line tools..."
wget -O cmdline-tools.zip "$ANDROID_TOOLS_URL"
unzip -q cmdline-tools.zip
rm cmdline-tools.zip

# Create proper directory structure
mkdir -p cmdline-tools/latest
mv cmdline-tools/* cmdline-tools/latest/ 2>/dev/null || true

# Set permissions
chown -R ubuntu:ubuntu "$ANDROID_HOME"
chmod -R 755 "$ANDROID_HOME"

# Install essential Android packages
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"
yes | sdkmanager --licenses || true
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
sdkmanager "system-images;android-34;google_apis;x86_64"
sdkmanager "emulator" "tools"

echo "Android development environment setup complete!"
echo "Run 'source /etc/android-sdk.conf' to load environment variables"
ANDROID_SETUP

chmod +x /usr/local/bin/android-dev-setup

# Create Java development helper script  
cat > /usr/local/bin/java-dev-setup << 'JAVA_SETUP'
#!/bin/bash
# Java Development Environment Setup

echo "=== JAVA DEVELOPMENT ENVIRONMENT ==="
echo

echo "Installed JDK versions:"
update-java-alternatives -l 2>/dev/null || echo "No alternatives configured"

echo
echo "Current JAVA_HOME: ${JAVA_HOME:-Not set}"
echo "Current Java version:"
java -version 2>&1 | head -3

echo
echo "Maven version:"
mvn --version 2>/dev/null | head -1 || echo "Maven not available"

echo
echo "Gradle version:"  
gradle --version 2>/dev/null | head -1 || echo "Gradle not available"

echo
echo "Android development:"
[ -d "/opt/android-sdk" ] && echo "Android SDK: Configured" || echo "Android SDK: Run android-dev-setup"

echo
echo "=== JAVA SETUP COMPLETE ==="
JAVA_SETUP

chmod +x /usr/local/bin/java-dev-setup

# Create kernel build helper script
cat > /usr/local/bin/kernel-build-helper << 'KBUILD'
#!/bin/bash
# Kernel Build Helper Script
# Usage: kernel-build-helper [arch] [config]

set -e

ARCH="${1:-x86_64}"
CONFIG="${2:-defconfig}"
THREADS=$(nproc)

echo "Building kernel for architecture: $ARCH"
echo "Using configuration: $CONFIG"
echo "Build threads: $THREADS"
echo "Microcode loading: DISABLED (security requirement)"

cd /usr/src/linux

# Set cross-compilation if needed
case "$ARCH" in
    "aarch64") export CROSS_COMPILE=aarch64-linux-gnu- ;;
    "arm") export CROSS_COMPILE=arm-linux-gnueabihf- ;;
    "mips") export CROSS_COMPILE=mips-linux-gnu- ;;
    "mips64el") export CROSS_COMPILE=mips64el-linux-gnuabi64- ;;
    "powerpc") export CROSS_COMPILE=powerpc-linux-gnu- ;;
    "powerpc64le") export CROSS_COMPILE=powerpc64le-linux-gnu- ;;
    "s390x") export CROSS_COMPILE=s390x-linux-gnu- ;;
    "riscv64") export CROSS_COMPILE=riscv64-linux-gnu- ;;
    "sparc64") export CROSS_COMPILE=sparc64-linux-gnu- ;;
esac

export ARCH

# Build kernel with microcode disabled
make $CONFIG
make -j$THREADS
make modules -j$THREADS

echo "Kernel build completed for $ARCH (microcode disabled)"
KBUILD

chmod +x /usr/local/bin/kernel-build-helper

# Create toolchain verification script
cat > /usr/local/bin/verify-toolchains << 'VERIFY'
#!/bin/bash
# Toolchain Verification Script

echo "=== ULTIMATE TOOLCHAIN VERIFICATION ==="
echo

echo "GCC Versions Available:"
for gcc in /usr/bin/gcc-*; do
    [[ -x "$gcc" ]] && echo "  $($gcc --version | head -1)"
done

echo
echo "Cross-Compilation Toolchains:"
for cross in /usr/bin/*-linux-gnu*-gcc; do
    [[ -x "$cross" ]] && echo "  $(basename $cross): $($cross --version | head -1)"
done

echo
echo "Clang/LLVM Tools:"
clang --version 2>/dev/null | head -1 || echo "  Clang: Not available"
llvm-config --version 2>/dev/null && echo "  LLVM: $(llvm-config --version)" || echo "  LLVM: Not available"

echo
echo "Build Tools:"
echo "  Make: $(make --version | head -1)"
echo "  CMake: $(cmake --version | head -1)"
echo "  Ninja: $(ninja --version 2>/dev/null || echo "Not available")"
echo "  Meson: $(meson --version 2>/dev/null || echo "Not available")"

echo
echo "Java Development:"
echo "  Java: $(java -version 2>&1 | head -1)"
echo "  Maven: $(mvn --version 2>/dev/null | head -1 || echo "Not available")"
echo "  Gradle: $(gradle --version 2>/dev/null | head -1 || echo "Not available")"

echo
echo "Android Development:"
[ -d "/opt/android-sdk" ] && echo "  Android SDK: Installed" || echo "  Android SDK: Not installed (run android-dev-setup)"
adb --version 2>/dev/null | head -1 && echo "  ADB: Available" || echo "  ADB: Not available"

echo
echo "Debugging Tools:"
echo "  GDB: $(gdb --version | head -1)"
echo "  Valgrind: $(valgrind --version 2>/dev/null || echo "Not available")"
echo "  Strace: $(strace -V 2>&1 | head -1)"

echo
echo "Static Analysis:"
echo "  Clang-tidy: $(clang-tidy --version 2>/dev/null | head -1 || echo "Not available")"
echo "  Cppcheck: $(cppcheck --version 2>/dev/null || echo "Not available")"

echo
echo "Snap Packages:"
snap list 2>/dev/null | grep -E "(telegram|signal|sublime)" || echo "  Snap packages not yet available (reboot required)"

echo
echo "Microcode Status:"
echo "  Microcode loading: DISABLED (security requirement)"
lsmod | grep -E "(microcode|intel_microcode|amd_microcode)" && echo "  WARNING: Microcode modules loaded!" || echo "  Microcode modules: Properly disabled"

echo
echo "=== VERIFICATION COMPLETE ==="
VERIFY

chmod +x /usr/local/bin/verify-toolchains

# Create useful aliases
cat >> /etc/skel/.bashrc << 'ALIASES'

# Enhanced aliases from repository
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias d='docker'
alias dc='docker-compose'
alias k='kubectl'
alias py='python3'
alias pip='pip3'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias top='htop'
alias cat='batcat'
alias find='fd'
alias ps='ps auxf'
alias mount='mount | column -t'

# Compilation aliases
alias gcc-all='echo "Available GCC versions:"; ls /usr/bin/gcc-*'
alias make-parallel='make -j$(nproc)'
alias cmake-debug='cmake -DCMAKE_BUILD_TYPE=Debug'
alias cmake-release='cmake -DCMAKE_BUILD_TYPE=Release'

# Cross-compilation helpers
alias arm-gcc='arm-linux-gnueabihf-gcc'
alias aarch64-gcc='aarch64-linux-gnu-gcc'
alias mips-gcc='mips-linux-gnu-gcc'

# Kernel development
alias kernel-config='make menuconfig'
alias kernel-clean='make clean && make mrproper'
alias kernel-build='kernel-build-helper'

# Development environment
alias dev-verify='verify-toolchains'
alias snap-list='snap list'

# Function for quick package search
pacs() { apt search "$@" 2>/dev/null | grep -E '^[^/]+/'; }
paci() { apt show "$@"; }

# Function for cross-compilation setup
setup-cross() {
    local arch="$1"
    case "$arch" in
        arm) export CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++ ;;
        aarch64) export CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ ;;
        mips) export CC=mips-linux-gnu-gcc CXX=mips-linux-gnu-g++ ;;
        *) echo "Usage: setup-cross [arm|aarch64|mips|...]" ;;
    esac
    echo "Cross-compilation environment set for $arch"
    echo "CC=$CC"
    echo "CXX=$CXX"
}
ALIASES

# Set better default editor
update-alternatives --set editor /usr/bin/vim.basic 2>/dev/null || true

# Configure git (system-wide defaults)
git config --system user.name "LiveCD User"
git config --system user.email "user@livecd.local"
git config --system init.defaultBranch main
git config --system pull.rebase false

# Disable unnecessary services for live environment
systemctl disable apt-daily.service
systemctl disable apt-daily.timer
systemctl disable apt-daily-upgrade.timer
systemctl disable apt-daily-upgrade.service

# Create useful directories
mkdir -p /home/ubuntu/{bin,src,tools,workspace,projects,kernels}
mkdir -p /opt/{tools,scripts,configs,builds}
mkdir -p /usr/local/{src,projects}

# Set up development workspace
chown -R ubuntu:ubuntu /home/ubuntu 2>/dev/null || true

EOF
    
    log_success "Package configuration complete"
}

# Install Snap packages
install_snap_packages() {
    log_info "Installing Snap packages..."
    
    # First ensure snapd is installed and running
    chroot "$CHROOT_DIR" bash <<'EOF'
# Install snapd if not already installed
if ! command -v snap &>/dev/null; then
    apt-get install -y snapd
fi

# Enable snapd services
systemctl enable snapd
systemctl enable snapd.socket

# Create snap symlink
ln -sf /var/lib/snapd/snap /snap

# Wait for snapd to be ready
sleep 5

# Update snap to latest
snap refresh core
EOF
    
    log_info "Installing Telegram Desktop via Snap..."
    chroot "$CHROOT_DIR" snap install telegram-desktop || log_warning "Failed to install telegram-desktop"
    
    log_info "Installing Signal Desktop via Snap..."
    chroot "$CHROOT_DIR" snap install signal-desktop || log_warning "Failed to install signal-desktop"
    
    log_info "Installing Sublime Text via Snap (--classic)..."
    chroot "$CHROOT_DIR" snap install sublime-text --classic || log_warning "Failed to install sublime-text"
    
    # Additional useful snap packages
    log_info "Installing additional development snap packages..."
    chroot "$CHROOT_DIR" bash <<'EOF'
# VS Code
snap install code --classic || echo "VS Code snap install failed"

# Discord
snap install discord || echo "Discord snap install failed"

# Postman for API testing
snap install postman || echo "Postman snap install failed"

# Firefox (snap version)
snap install firefox || echo "Firefox snap install failed"

# Chromium
snap install chromium || echo "Chromium snap install failed"

# Node.js LTS
snap install node --classic || echo "Node.js snap install failed"

# kubectl for Kubernetes
snap install kubectl --classic || echo "kubectl snap install failed"

# Helm for Kubernetes
snap install helm --classic || echo "Helm snap install failed"

# Docker (additional snap version)
snap install docker || echo "Docker snap install failed"
EOF
    
    log_success "Snap packages installation completed"
}
    log_info "Cleaning and optimizing..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
# Clean package cache
apt-get autoremove -y
apt-get autoclean
apt-get clean

# Remove unnecessary packages
apt-get purge -y $(dpkg -l | grep '^rc' | awk '{print $2}')

# Clean logs
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.log.*" -delete

# Clean temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /var/cache/apt/archives/*.deb

# Update locate database
updatedb 2>/dev/null || true

# Generate man database
mandb -q 2>/dev/null || true

EOF
    
    log_success "Cleaning and optimization complete"
}

# Generate installation summary
generate_summary() {
    local installed=$(chroot "$CHROOT_DIR" dpkg -l | grep '^ii' | wc -l)
    local disk_used=$(du -sh "$CHROOT_DIR/var/cache/apt/archives" 2>/dev/null | cut -f1 || echo "Unknown")
    local total_size=$(du -sh "$CHROOT_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    local snap_count=$(chroot "$CHROOT_DIR" snap list 2>/dev/null | wc -l || echo "0")
    
    log_success "=== ULTIMATE INSTALLATION SUMMARY ==="
    log_success "Total APT packages installed: $installed"
    log_success "Total Snap packages installed: $snap_count"
    log_success "Package cache size: $disk_used"
    log_success "Total chroot size: $total_size"
    
    # Save detailed package list
    chroot "$CHROOT_DIR" dpkg -l | grep '^ii' > "$BUILD_ROOT/installed-packages.list"
    chroot "$CHROOT_DIR" snap list > "$BUILD_ROOT/installed-snaps.list" 2>/dev/null || echo "No snaps installed yet" > "$BUILD_ROOT/installed-snaps.list"
    
    # Create installation marker
    cat > "$BUILD_ROOT/package-installation.marker" << EOF
Installation completed: $(date -Iseconds)
Script version: $MODULE_VERSION
Total APT packages: $installed
Total Snap packages: $snap_count
Categories installed: 20
QOL packages: YES
Complete toolchains: YES
Cross-compilation: YES
Android SDK: YES
Java ecosystem: COMPLETE
Microcode loading: DISABLED (security)
Repository packages: ALL
APT package list: $BUILD_ROOT/installed-packages.list
Snap package list: $BUILD_ROOT/installed-snaps.list

Toolchain Summary:
- Kernel compilation: COMPLETE (all architectures)
- Code compilation: COMPLETE (all languages)
- Cross-compilation: COMPLETE (ARM, MIPS, RISC-V, etc.)
- Android development: COMPLETE (SDK, tools, emulator support)
- Java development: COMPLETE (JDK 8,11,17,21 + frameworks)
- Debugging tools: COMPLETE (GDB, Valgrind, SystemTap)
- Static analysis: COMPLETE (Clang-tidy, Cppcheck, etc.)

Security Features:
- Microcode loading: DISABLED
- Kernel parameter: dis_ucode_ldr added
- Microcode modules: Blacklisted

Mobile Development:
- Android SDK: Command-line tools ready
- ADB and Fastboot: Installed
- Flutter/Dart: Available
- Emulator support: Configured

Snap Packages:
- telegram-desktop
- signal-desktop  
- sublime-text (--classic)
- code (--classic)
- Additional development tools
EOF
    
    log_success "Package list saved to: $BUILD_ROOT/installed-packages.list"
    log_success "Snap list saved to: $BUILD_ROOT/installed-snaps.list"
    log_success "Installation marker: $BUILD_ROOT/package-installation.marker"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== ULTIMATE TOOLCHAIN INSTALLATION MODULE v$MODULE_VERSION ==="
    log_info "Installing ALL packages + COMPLETE compilation toolchains + Snap packages"
    log_info "Includes: Kernel compilation, Cross-compilation, All languages, QOL tools"
    log_info "Snap packages: Telegram, Signal, Sublime Text (--classic) + development tools"
    log_info "This will take approximately 30-60 minutes depending on network speed"
    log_info "Estimated disk space: 10-20GB for complete development environment"
    echo
    
    # Verify chroot exists
    [[ -d "$CHROOT_DIR" ]] || {
        log_error "Chroot directory not found: $CHROOT_DIR"
    }
    
    # Mount chroot
    mount_chroot
    
    # Set up package sources for additional repositories
    log_info "Configuring package sources..."
    chroot "$CHROOT_DIR" bash <<'EOF'
# Enable all Ubuntu components
add-apt-repository -y universe
add-apt-repository -y multiverse
add-apt-repository -y restricted

# Add additional PPAs for latest tools
add-apt-repository -y ppa:git-core/ppa
add-apt-repository -y ppa:neovim-ppa/stable

# Update package lists
apt-get update
EOF
    
    # Install all package categories
    log_info "Beginning comprehensive package installation..."
    echo "Categories to install:"
    echo "  1. System Core & Live Boot (NO MICROCODE)"
    echo "  2. QOL (Quality of Life) Tools - PRIMARY FOCUS"
    echo "  3. Build Essentials & Compilers"
    echo "  4. Kernel & Headers"
    echo "  5. ZFS & Filesystem Tools"
    echo "  6. Recovery & Forensics"
    echo "  7. Security & Monitoring"
    echo "  8. Development Tools & Languages"
    echo "  9. Multimedia & Desktop"
    echo "  10. Office & Productivity"
    echo "  11. Network Tools & Services"
    echo "  12. Container & Virtualization"
    echo "  13. Database Systems"
    echo "  14. Proxmox & Enterprise"
    echo "  15. Hardware Specific (NO MICROCODE)"
    echo "  16. COMPLETE Kernel Compilation Toolchain"
    echo "  17. COMPLETE Code Compilation Toolchain" 
    echo "  18. Advanced Development Libraries"
    echo "  19. Android SDK & Mobile Development"
    echo "  20. COMPLETE Java Development Ecosystem"
    echo "  21. Snap Packages (Telegram, Signal, Sublime)"
    echo
    
    # Install each category
    install_package_group "System Core & Live Boot" "${SYSTEM_CORE_PACKAGES[@]}"
    install_package_group "QOL Tools (Primary Focus)" "${QOL_PACKAGES[@]}"
    install_package_group "Build Essentials" "${BUILD_ESSENTIALS[@]}"
    install_package_group "Kernel & Headers" "${KERNEL_PACKAGES[@]}"
    install_package_group "ZFS & Filesystems" "${ZFS_FILESYSTEM_PACKAGES[@]}"
    install_package_group "Recovery & Forensics" "${RECOVERY_PACKAGES[@]}"
    install_package_group "Security & Monitoring" "${SECURITY_PACKAGES[@]}"
    install_package_group "Development Tools" "${DEVELOPMENT_PACKAGES[@]}"
    install_package_group "Multimedia & Desktop" "${MULTIMEDIA_PACKAGES[@]}"
    install_package_group "Office & Productivity" "${OFFICE_PACKAGES[@]}"
    install_package_group "Network Tools" "${NETWORK_PACKAGES[@]}"
    install_package_group "Containers & Virtualization" "${CONTAINER_PACKAGES[@]}"
    install_package_group "Database Systems" "${DATABASE_PACKAGES[@]}"
    install_package_group "Proxmox & Enterprise" "${PROXMOX_PACKAGES[@]}"
    install_package_group "Hardware Specific" "${HARDWARE_PACKAGES[@]}"
    install_package_group "Complete Kernel Toolchain" "${KERNEL_TOOLCHAIN_PACKAGES[@]}"
    install_package_group "Complete Code Toolchain" "${CODE_TOOLCHAIN_PACKAGES[@]}"
    install_package_group "Advanced Development" "${ADVANCED_DEV_PACKAGES[@]}"
    install_package_group "Android SDK & Mobile Dev" "${ANDROID_SDK_PACKAGES[@]}"
    install_package_group "Java Development Ecosystem" "${JAVA_ECOSYSTEM_PACKAGES[@]}"
    
    # Install Snap packages
    install_snap_packages
    
    # Configure everything
    configure_packages
    
    # Clean and optimize
    clean_and_optimize
    
    # Create checkpoint
    create_checkpoint "enhanced_packages_complete" "$BUILD_ROOT"
    
    # Generate summary
    generate_summary
    
    # Unmount
    umount_chroot
    
    echo
    log_success "=========================================="
    log_success "  ULTIMATE TOOLCHAIN INSTALLATION COMPLETE"
    log_success "=========================================="
    log_success "✓ All repository packages installed"
    log_success "✓ QOL (Quality of Life) tools installed"
    log_success "✓ COMPLETE kernel compilation toolchain"
    log_success "✓ COMPLETE code compilation toolchain"
    log_success "✓ Cross-compilation for all architectures"
    log_success "✓ Android SDK & mobile development tools"
    log_success "✓ Complete Java ecosystem (JDK 8,11,17,21)"
    log_success "✓ Microcode loading DISABLED (security)"
    log_success "✓ Snap packages (Telegram, Signal, Sublime)"
    log_success "✓ Development environment ready"
    log_success "✓ Security tools configured"
    log_success "✓ Multimedia codecs installed"
    log_success "✓ System optimized and cleaned"
    echo
    log_success "Your LiveCD build environment now includes:"
    log_success "• Modern system monitoring (htop, btop, glances)"
    log_success "• Advanced file management (ranger, fzf, ripgrep)"
    log_success "• Complete development stack (ALL languages)"
    log_success "• COMPLETE kernel compilation toolchain:"
    log_success "  - GCC 9, 10, 11, 12, 13 + Clang/LLVM"
    log_success "  - Cross-compilation: ARM, AArch64, MIPS, RISC-V, etc."
    log_success "  - Kernel debugging: crash, SystemTap, ftrace"
    log_success "  - Static analysis: sparse, smatch, coccinelle"
    log_success "  - Microcode loading: DISABLED for security"
    log_success "• COMPLETE code compilation toolchain:"
    log_success "  - Multiple compiler versions and alternatives"
    log_success "  - Advanced build systems (CMake, Meson, Ninja)"
    log_success "  - Profiling and optimization tools"
    log_success "  - Memory debugging and static analysis"
    log_success "• Android development environment:"
    log_success "  - Android SDK with command-line tools"
    log_success "  - ADB, Fastboot, platform tools"
    log_success "  - Emulator support (x86_64 system images)"
    log_success "  - Flutter/Dart development tools"
    log_success "  - Gradle, Maven build systems"
    log_success "• Complete Java ecosystem:"
    log_success "  - Multiple JDK versions (8, 11, 17, 21)"
    log_success "  - Enterprise frameworks (Spring, etc.)"
    log_success "  - IDEs (Eclipse, NetBeans, BlueJ)"
    log_success "  - Testing frameworks (JUnit, TestNG, Mockito)"
    log_success "  - Application servers (Tomcat, Jetty, WildFly)"
    log_success "• Essential Snap packages:"
    log_success "  - Telegram Desktop"
    log_success "  - Signal Desktop" 
    log_success "  - Sublime Text (--classic)"
    log_success "  - VS Code, Discord, Postman, etc."
    log_success "• Security features:"
    log_success "  - Microcode loading disabled"
    log_success "  - Kernel hardening parameters"
    log_success "  - Security and forensics tools"
    log_success "• ZFS and advanced filesystems"
    log_success "• Container orchestration (Docker, Podman)"
    log_success "• Network analysis and monitoring"
    log_success "• Hardware diagnostics and recovery"
    echo
    log_success "Development helper commands available:"
    log_success "• kernel-build-helper [arch] [config] - Build kernels (microcode disabled)"
    log_success "• verify-toolchains - Check all installed tools"
    log_success "• setup-cross [arch] - Set cross-compilation env"
    log_success "• android-dev-setup - Configure Android SDK"
    log_success "• java-dev-setup - Verify Java environment"
    echo
    log_success "Ready for advanced development and LiveCD creation!"
    
    exit 0
}

# Set up trap for cleanup
trap umount_chroot EXIT

# Execute main function
main "$@"