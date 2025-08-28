# Complete Package List - BTRFS Persistent LiveCD Build System

**Total Packages: 1300+** across 20 categories
**Estimated Install Size: 15-20GB**
**Build Time: 30-60 minutes**

This document lists ALL packages installed by the build system, organized by category.

## Table of Contents

1. [System Core & Live Boot](#1-system-core--live-boot)
2. [Quality of Life Tools](#2-quality-of-life-tools)
3. [Build Essentials & Compilers](#3-build-essentials--compilers)
4. [Kernel & Headers](#4-kernel--headers)
5. [ZFS & Filesystem Packages](#5-zfs--filesystem-packages)
6. [Recovery & Forensics Tools](#6-recovery--forensics-tools)
7. [Security & Monitoring](#7-security--monitoring)
8. [Development Tools & Languages](#8-development-tools--languages)
9. [Multimedia & Desktop](#9-multimedia--desktop)
10. [Office & Productivity](#10-office--productivity)
11. [Network Tools & Services](#11-network-tools--services)
12. [Container & Virtualization](#12-container--virtualization)
13. [Database Systems](#13-database-systems)
14. [Proxmox & Enterprise](#14-proxmox--enterprise)
15. [Hardware Specific](#15-hardware-specific)
16. [Kernel Compilation Toolchain](#16-kernel-compilation-toolchain)
17. [Code Compilation Toolchain](#17-code-compilation-toolchain)
18. [Advanced Development Libraries](#18-advanced-development-libraries)
19. [Android SDK & Mobile Development](#19-android-sdk--mobile-development)
20. [Java Development Ecosystem](#20-java-development-ecosystem)
21. [Snap Packages](#21-snap-packages)

---

## 1. System Core & Live Boot

Essential system packages for live boot functionality.

**Note: Microcode loading is DISABLED for security**

- ubuntu-minimal, ubuntu-standard
- casper, lupin-casper
- live-boot, live-config, live-config-systemd
- dracut, dracut-live, dracut-network
- initramfs-tools, initramfs-tools-core
- update-initramfs, live-tools
- discover, laptop-detect, os-prober
- ubiquity, ubiquity-casper, ubiquity-slideshow-ubuntu
- flatpak, appstream
- linux-firmware (NO MICROCODE)
- firmware-linux, firmware-linux-nonfree, firmware-misc-nonfree
- firmware-iwlwifi, firmware-realtek, firmware-atheros
- firmware-bnx2, firmware-bnx2x, firmware-sof-signed
- grub-efi-amd64, grub-efi-amd64-signed, grub-pc-bin
- efibootmgr, efitools, efivar, libefivar-dev
- mokutil, sbsigntool, secureboot-db, shim-signed
- isolinux, syslinux, syslinux-common, syslinux-efi
- systemd, systemd-container, systemd-coredump
- udev, dbus, rsyslog, cron, anacron
- sudo, passwd, adduser, login

## 2. Quality of Life Tools

Modern CLI tools that make Linux actually pleasant to use.

### System Monitors
- htop, btop, atop, iotop, iftop, nethogs
- glances, nmon, sysstat, dstat, powertop

### System Information
- neofetch, screenfetch, inxi, lshw, hwinfo
- dmidecode, lscpu, lsblk, lsusb, lspci
- cpu-x, hardinfo

### Terminal Enhancements
- tmux, screen, byobu, terminator, tilix
- zsh, fish, bash-completion

### File Management
- tree, ranger, mc, vifm, ncdu, duf, dust
- fd-find, ripgrep, fzf, silversearcher-ag
- bat, exa, lsd, broot

### Text Processing
- jq, yq, xmlstarlet, miller, pv, progress
- parallel, moreutils, gawk, sed

### Network Utilities
- httpie, curl, wget, aria2, axel, lftp
- mtr, traceroute, dig, whois, nmap
- mosh, autossh, sshpass, keychain

### Archive & Compression
- p7zip-full, p7zip-rar, unrar, unrar-free
- zip, unzip, pigz, pbzip2, pixz, pxz
- zstd, lz4, xz-utils, bzip2, gzip

### Development Helpers
- gh, git-extras, tig, gitk, git-gui
- direnv, thefuck, tldr, cheat
- tokei, loc, cloc, hyperfine

## 3. Build Essentials & Compilers

Core compilation tools for building from source.

- build-essential, gcc, g++, make, cmake
- gcc-12, gcc-13, g++-12, g++-13, clang, llvm
- automake, autoconf, libtool, bison, flex, bc
- rsync, cpio, kmod, dkms, module-assistant
- pkg-config, dpkg-dev, debhelper, dh-make, fakeroot
- patch, patchutils, quilt, nasm, yasm, iasl
- ninja-build, meson, scons, ccache, distcc

## 4. Kernel & Headers

Everything needed for kernel development.

- linux-headers-generic, linux-headers-$(uname -r)
- linux-source, linux-tools-common, linux-tools-generic
- linux-cloud-tools-generic, linux-image-generic
- linux-generic-hwe-22.04, linux-headers-generic-hwe-22.04
- kernel-package, libncurses-dev, libssl-dev, libelf-dev
- crash, makedumpfile, kdump-tools, kexec-tools
- systemtap, systemtap-sdt-dev, perf-tools-unstable
- trace-cmd, kernelshark, dwarves, pahole

## 5. ZFS & Filesystem Packages

**Note: ZFS 2.3.4 is built from source**

- zfsutils-linux, zfs-dkms, zfs-initramfs, zfs-zed
- zfs-auto-snapshot, pv, mbuffer, lzop
- e2fsprogs, xfsprogs, btrfs-progs, dosfstools
- ntfs-3g, f2fs-tools, nilfs-tools, reiserfsprogs, jfsutils
- exfatprogs, squashfs-tools, genext2fs, mtd-utils
- lvm2, mdadm, cryptsetup, cryptsetup-initramfs
- parted, gdisk, fdisk, gparted, gnome-disk-utility
- fuse3, libfuse3-dev, sshfs, davfs2, cifs-utils, nfs-common

## 6. Recovery & Forensics Tools

Data recovery and system forensics.

### Data Recovery
- testdisk, photorec, gddrescue, ddrescue, safecopy
- foremost, scalpel, extundelete, ext4magic
- recoverjpeg, sleuthkit, autopsy

### Disk Diagnostics
- smartmontools, hdparm, nvme-cli, blktrace

### System Recovery
- memtest86+, stress, stress-ng, memtester
- sysbench, fio, iozone3, bonnie++

## 7. Security & Monitoring

Security frameworks and monitoring tools.

### Security Frameworks
- apparmor, apparmor-utils, fail2ban, ufw, iptables
- nftables, firewalld

### Intrusion Detection
- aide, rkhunter, chkrootkit, lynis, tripwire
- samhain, osquery

### Antivirus
- clamav, clamav-daemon, clamav-freshclam

### Network Security
- wireshark, wireshark-qt, tshark, tcpdump
- nmap, netcat-openbsd, socat, ethtool

### Penetration Testing
- aircrack-ng, john, hashcat, hydra, medusa
- sqlmap, nikto, dirb, gobuster

## 8. Development Tools & Languages

Complete programming language support.

### Version Control
- git, subversion, mercurial, cvs, bzr

### Editors and IDEs
- vim, vim-gtk3, neovim, emacs, nano
- code, codium, atom, sublime-text
- gedit, mousepad, leafpad

### Python Ecosystem
- python3, python3-full, python3-dev, python3-pip
- python3-venv, python3-virtualenv, pipx
- python3-setuptools, python3-wheel, python3-pytest
- python3-numpy, python3-scipy, python3-pandas
- python3-matplotlib, python3-requests, python3-flask

### Other Languages
- nodejs, npm, yarn, golang-go, rustc, cargo
- openjdk-17-jdk, openjdk-11-jdk, maven, gradle
- php, php-cli, composer, ruby, ruby-dev
- perl, lua5.4, tcl, tk

### Database Clients
- postgresql-client, mysql-client, redis-tools
- sqlite3, mongodb-clients

## 9. Multimedia & Desktop

Audio/video codecs and media applications.

### Codecs
- ubuntu-restricted-extras, gstreamer1.0-plugins-base
- gstreamer1.0-plugins-good, gstreamer1.0-plugins-bad
- gstreamer1.0-plugins-ugly, gstreamer1.0-libav
- libavcodec-extra, libdvd-pkg

### Media Players
- vlc, mpv, totem, rhythmbox, audacious
- clementine, banshee, amarok

### Graphics & Imaging
- gimp, inkscape, krita, blender, shotwell
- imagemagick, graphicsmagick, optipng, jpegoptim

### Video Editing
- kdenlive, openshot, pitivi, obs-studio

### Audio Production
- audacity, ardour, lmms, hydrogen

### 3D Graphics
- mesa-utils, mesa-va-drivers, mesa-vdpau-drivers
- mesa-vulkan-drivers, vulkan-tools, vulkan-validationlayers

## 10. Office & Productivity

Office suites and productivity applications.

### Office Suites
- libreoffice, libreoffice-gtk3, calligra
- abiword, gnumeric, focuswriter

### Email & Communication
- thunderbird, evolution, claws-mail
- pidgin, hexchat, irssi, weechat

### Browsers
- firefox, firefox-esr, chromium-browser
- lynx, w3m, elinks

### Document Viewers
- evince, okular, zathura, mupdf
- calibre, fbreader

### Note Taking
- tomboy, cherrytree, zim, tiddlywiki

## 11. Network Tools & Services

Comprehensive networking utilities.

### Network Basics
- net-tools, iproute2, iputils-ping, traceroute
- wireless-tools, wpasupplicant, iw, rfkill
- network-manager, network-manager-gnome
- network-manager-openvpn, network-manager-pptp
- network-manager-vpnc

### SSH & Remote Access
- openssh-server, openssh-client, openssh-sftp-server
- sshfs, x11-apps, xauth

### VPN Clients
- openvpn, wireguard, openconnect, strongswan

### Network Monitoring
- vnstat, bmon, slurm, bwm-ng, bandwidthd
- darkstat, ntopng, cacti

### DNS Tools
- bind9-utils, dnsutils, ldnsutils, unbound-host

## 12. Container & Virtualization

Container orchestration and virtual machines.

### Docker Ecosystem
- docker.io, docker-compose, docker-buildx
- containerd, runc

### Podman & Alternatives
- podman, buildah, skopeo, crun

### System Containers
- lxc, lxd, systemd-container, debootstrap
- schroot, pbuilder

### Virtual Machines
- qemu, qemu-kvm, qemu-utils, qemu-system-x86
- libvirt-daemon, libvirt-daemon-system, libvirt-clients
- virt-manager, virtinst, virt-viewer
- bridge-utils, vlan

### Vagrant
- vagrant, virtualbox, virtualbox-ext-pack

## 13. Database Systems

Complete database server and client packages.

### PostgreSQL
- postgresql, postgresql-client, postgresql-contrib
- pgadmin4, postgresql-doc

### MySQL/MariaDB
- mariadb-server, mariadb-client, mysql-workbench
- phpmyadmin, adminer

### NoSQL
- mongodb, redis-server, memcached
- couchdb, elasticsearch

### SQLite Tools
- sqlite3, sqlitebrowser, db-util

## 14. Proxmox & Enterprise

Enterprise virtualization and backup tools.

### Proxmox Specific
- libpve-common-perl, libpve-guest-common-perl
- libpve-storage-perl, pve-edk2-firmware
- pve-kernel-helper, proxmox-archive-keyring
- proxmox-backup-client, proxmox-offline-mirror-helper
- pve-qemu-kvm, qemu-server

### Ceph Storage
- ceph-common, ceph-fuse, radosgw

### Backup Tools
- borgbackup, duplicity, rdiff-backup, rsnapshot
- bacula-client, amanda-client

## 15. Hardware Specific

Hardware-specific tools and drivers.

**Note: Intel/AMD microcode packages are NOT installed**

### Graphics
- intel-gpu-tools, intel-media-va-driver, i965-va-driver
- thermald, powertop

### Dell Hardware
- libsmbios2, smbios-utils, dell-recovery
- oem-config, oem-config-gtk

### General Hardware
- lm-sensors, fancontrol, hddtemp, acpi
- cpufrequtils, laptop-mode-tools, tlp
- usbutils, pciutils, dmidecode

### Thunderbolt
- thunderbolt-tools, bolt

## 16. Kernel Compilation Toolchain

Complete toolchain for building kernels for any architecture.

### Core Build Requirements
- linux-libc-dev, libc6-dev, linux-source
- kernel-package, fakeroot, build-essential
- libncurses-dev, libssl-dev, libelf-dev
- flex, bison, openssl, dkms

### Cross-Compilation Toolchains
- gcc-aarch64-linux-gnu, gcc-arm-linux-gnueabihf
- gcc-i686-linux-gnu, gcc-mips-linux-gnu
- gcc-mips64el-linux-gnuabi64, gcc-powerpc-linux-gnu
- gcc-powerpc64le-linux-gnu, gcc-s390x-linux-gnu
- gcc-riscv64-linux-gnu, gcc-sparc64-linux-gnu

### Additional Cross Tools
- binutils-aarch64-linux-gnu, binutils-arm-linux-gnueabihf
- binutils-i686-linux-gnu, binutils-mips-linux-gnu
- binutils-mips64el-linux-gnuabi64, binutils-powerpc-linux-gnu
- binutils-powerpc64le-linux-gnu, binutils-s390x-linux-gnu
- binutils-riscv64-linux-gnu, binutils-sparc64-linux-gnu

### LLVM/Clang Toolchain
- clang, llvm, lld, lldb
- clang-tools, clang-tidy, clang-format
- libc++-dev, libc++abi-dev

### Kernel Debugging
- crash, makedumpfile, kdump-tools
- systemtap, systemtap-sdt-dev, systemtap-client
- perf-tools-unstable, linux-tools-common
- trace-cmd, kernelshark, ftrace

### Advanced Kernel Development
- pahole, dwarves, sparse, smatch
- coccinelle, cppcheck, splint
- kgraft-patch-default, livepatch-tools

## 17. Code Compilation Toolchain

Everything needed to compile code in any language.

### GCC Toolchain (Multiple Versions)
- gcc, g++, gcc-9, g++-9, gcc-10, g++-10
- gcc-11, g++-11, gcc-12, g++-12, gcc-13, g++-13
- gcc-multilib, g++-multilib

### Build Systems
- make, cmake, cmake-gui, cmake-curses-gui
- ninja-build, meson, scons, autotools-dev
- automake, autoconf, libtool, pkg-config
- m4, gettext, intltool, gperf

### Assembly & Low-Level
- nasm, yasm, fasmg, as31
- binutils, binutils-dev, elfutils
- objdump, readelf, nm, strip

### Static Analysis
- cppcheck, clang-tidy, clang-format
- splint, flawfinder, rats, pscan
- valgrind, valgrind-dbg, helgrind
- cachegrind, massif-visualizer

### Profiling & Performance
- gprof, gcov, lcov, kcov
- google-perftools, libtcmalloc-minimal4
- libgoogle-perftools-dev, gperftools

### Memory Debugging
- electric-fence, duma, libduma0
- libefence0, address-sanitizer

### Optimization
- gcc-plugin-dev, libgcc-s1-dbg
- libc6-dbg, libc6-dev-i386

### Alternative Compilers
- icc, intel-opencl-icd, intel-level-zero-gpu
- tcc, pcc, open64, pathscale

### Language-Specific Toolchains
- rustc, cargo, rustfmt, clippy
- golang, gccgo, golang-any
- openjdk-8-jdk, openjdk-11-jdk, openjdk-17-jdk
- openjdk-21-jdk, maven, gradle, ant

### Python Compilation
- python3-dev, python3-all-dev, python3-dbg
- cython3, python3-setuptools-scm, python3-wheel
- python3-build, python3-installer, python3-hatchling

### Ruby Compilation
- ruby-dev, ruby-all-dev, bundler
- rake, gem2deb

### Node.js & JavaScript
- nodejs, npm, yarn, node-gyp
- nodejs-dev, libnode-dev

### Perl Compilation
- perl, libperl-dev, perl-modules-5.36
- liblocal-lib-perl, cpanminus

## 18. Advanced Development Libraries

Comprehensive development libraries for all needs.

### Core Development Libraries
- libgtk-3-dev, libgtk-4-dev, libqt5-dev, qtbase5-dev
- libwebkit2gtk-4.0-dev, libgmp-dev, libreadline-dev
- libgdbm-dev, libdb-dev, device-tree-compiler
- libcrypto++-dev, libgcrypt20-dev, libgnutls28-dev
- libsqlite3-dev, libmysqlclient-dev, libpq-dev
- libxml2-dev, libxslt1-dev, libyaml-dev, libjson-c-dev
- libpcre3-dev, libpcre2-dev, libre2-dev
- libglib2.0-dev, libevent-dev, libev-dev
- libboost-all-dev, libusb-1.0-0-dev, libftdi1-dev
- libpci-dev, libpcap-dev, libnet1-dev

### Graphics & Multimedia Development
- libgl1-mesa-dev, libglu1-mesa-dev, freeglut3-dev
- libglew-dev, libglfw3-dev, libglm-dev
- libsdl2-dev, libsdl2-image-dev, libsdl2-mixer-dev
- libsfml-dev, liballegro5-dev, libogre-1.12-dev

### Audio Development
- libasound2-dev, libpulse-dev, libjack-jackd2-dev
- libportaudio2, libsndfile1-dev, libvorbis-dev
- libflac-dev, libmp3lame-dev, libopus-dev

### Image & Video Processing
- libopencv-dev, libavcodec-dev, libavformat-dev
- libswscale-dev, libavutil-dev, libavdevice-dev
- libmagickwand-dev, libfreeimage-dev, libjpeg-dev
- libpng-dev, libtiff-dev, libwebp-dev

### Debugging & Profiling
- gdb, gdb-multiarch, gdbserver, ddd
- strace, ltrace, time, rr-debugger

## 19. Android SDK & Mobile Development

Complete Android and mobile development environment.

### Android Development Dependencies
- android-tools-adb, android-tools-fastboot
- android-sdk-platform-tools-common
- lib32z1, lib32ncurses6, lib32stdc++6
- lib32gcc-s1, lib32z1-dev, libc6-dev-i386

### Build Tools for Android
- gradle, ant, maven, unzip, zip
- openjdk-8-jdk, openjdk-11-jdk, openjdk-17-jdk
- openjdk-21-jdk, default-jdk

### Graphics & UI Development
- libgl1-mesa-dev, libxrandr2, libxss1
- libgconf-2-4, libxdamage1, libdrm2
- libxcomposite1, libxcursor1, libxtst6
- libasound2, libatk1.0-0, libcairo-gobject2
- libgtk-3-0, libgdk-pixbuf2.0-0

### Network & Debugging
- wget, curl, unzip, git, ssh
- usbutils, dkms, qemu-kvm

### Additional Mobile Dev Tools
- nodejs, npm, python3, python3-pip
- flutter, dart

## 20. Java Development Ecosystem

Complete Java development stack.

### Multiple JDK Versions
- openjdk-8-jdk, openjdk-8-jre, openjdk-8-source
- openjdk-11-jdk, openjdk-11-jre, openjdk-11-source
- openjdk-17-jdk, openjdk-17-jre, openjdk-17-source
- openjdk-21-jdk, openjdk-21-jre, openjdk-21-source
- default-jdk, default-jre, default-jdk-headless

### Build Tools
- maven, gradle, ant, sbt, leiningen
- ivy, ivy-doc, gradle-doc, maven-doc

### Application Servers
- tomcat9, tomcat9-admin, tomcat9-docs
- jetty9, wildfly

### IDEs & Development Tools
- eclipse, eclipse-cdt, eclipse-jdt
- netbeans, bluej, drjava

### Testing Frameworks
- junit4, testng, mockito
- libhamcrest-java, libassertj-core-java

### Database Connectors
- libmysql-java, libpostgresql-jdbc-java
- libsqlite-jdbc-java, libmongo-java

### Spring Framework
- libspring-core-java, libspring-beans-java
- libspring-context-java, libspring-web-java

### Logging & Utilities
- liblog4j2-java, libslf4j-java, liblogback-java
- libcommons-lang3-java, libcommons-io-java
- libcommons-cli-java, libguava-java

### Android Support
- android-libadb, android-libutils
- android-liblog, android-libbase

## 21. Snap Packages

Desktop applications installed via Snap.

### Communication
- telegram-desktop
- signal-desktop
- discord

### Development
- sublime-text (--classic)
- code (--classic)
- postman

### Browsers
- firefox
- chromium

### DevOps Tools
- kubectl (--classic)
- helm (--classic)
- docker
- node (--classic)

---

## Installation Notes

### Package Management
- All packages are installed with `--no-install-recommends` to minimize bloat
- Failed packages are retried individually
- Installation is done in batches of 20 to avoid command line limits

### Security Configuration
- **Microcode loading is DISABLED**
- Kernel parameter `dis_ucode_ldr` is added
- Microcode modules are blacklisted
- GPG authentication is bypassed during build (trusted=yes)

### Development Helpers
The system includes several helper scripts:
- `kernel-build-helper` - Build kernels for any architecture
- `verify-toolchains` - Check all installed development tools
- `android-dev-setup` - Configure Android SDK
- `java-dev-setup` - Verify Java environment
- `setup-cross` - Configure cross-compilation environment

### ZFS Notes
- ZFS 2.3.4 is built from source (not from packages)
- Package versions may be removed to prevent conflicts
- The zfs-builder module handles compilation

### Disk Space Requirements
- APT packages: ~10-12GB
- Snap packages: ~2-3GB
- Development tools: ~3-5GB
- **Total: 15-20GB**

### Build Time
- Fast network: 30-40 minutes
- Average network: 45-60 minutes
- Slow network: 60-90 minutes

---

## Updates and Maintenance

To update this list:
1. Edit `src/modules/package-installation.sh`
2. Add packages to appropriate category array
3. Rebuild the ISO with `unified-deploy.sh build`

To verify installed packages:
```bash
# Check APT packages
dpkg -l | grep '^ii' | wc -l

# Check specific package
apt list --installed | grep package-name

# Check snap packages
snap list

# Verify toolchains
verify-toolchains
```

---

*Generated from package-installation.sh v1.0.0*
*Last updated: 2024*
*Total categories: 20 + Snap packages*
*Microcode loading: DISABLED for security*