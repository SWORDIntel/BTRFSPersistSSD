# BTRFS Persistent Ubuntu LiveCD Build System

**The Ultimate Ubuntu ISO Builder & Deployment System**

A military-grade, production-ready build and deployment system that creates custom Ubuntu LiveCDs with persistent storage, BTRFS/ZFS filesystems, and over 1300 pre-installed packages. This isn't just another ISO builder - it's a complete infrastructure deployment system that ensures every tool, compiler, and development environment you could ever need is ready to go.

## 🎯 What This Actually Does

This repository builds and deploys a **COMPLETE** Ubuntu system that includes:

- **Custom Ubuntu ISO** built from scratch with ALL packages pre-installed
- **Persistent storage** with BTRFS compression (zstd:6) or ZFS 2.3.4
- **1300+ packages** including every development tool imaginable
- **Complete compilation toolchains** for every architecture (ARM, MIPS, RISC-V, PowerPC, etc.)
- **Android SDK**, **Java ecosystem** (JDK 8, 11, 17, 21), all programming languages
- **ZFS 2.3.4** built from source (not the outdated repo version)
- **Authoritative configuration management** - no more CDROM source issues
- **Quality of life tools** that actually make Linux usable

## 🚀 Quick Start (TL;DR)

```bash
# Clone it
git clone https://github.com/yourusername/btrfs-persist-ssd.git
cd btrfs-persist-ssd

# Build and deploy to a drive (WILL DESTROY ALL DATA ON TARGET)
sudo ./unified-deploy.sh full /dev/sdb

# That's it. Go get coffee. This will take 30-60 minutes.
```

## 📋 Table of Contents

- [Features](#-features)
- [What Gets Installed](#-what-gets-installed)
- [System Architecture](#-system-architecture)
- [Installation & Usage](#-installation--usage)
- [Configuration Management](#-configuration-management)
- [Module System](#-module-system)
- [Troubleshooting](#-troubleshooting)
- [Advanced Usage](#-advanced-usage)
- [License](#-license)

## ✨ Features

### Build System Features
- **Modular architecture** - Each build phase is a separate, debuggable module
- **Authoritative configurations** - Custom sources.list and resolv.conf that actually work
- **Verbose logging** - Every command is logged with `bash -x` for debugging
- **Checkpoint system** - Resume failed builds from last successful module
- **Parallel execution** where possible
- **ZFS 2.3.4 from source** - Because the repo version is ancient
- **Intelligent recovery** - Attempts to fix common issues automatically

### Deployment Features
- **Any target drive** - Specify device as parameter
- **BTRFS with compression** - zstd:6 by default for 40-50% space savings
- **Automatic partitioning** - GPT with BTRFS + EFI
- **GRUB bootloader** with custom persistent boot entries
- **User creation** with sudo privileges
- **Live persistence** - Changes persist across reboots

### Configuration Management
- **Authoritative sources.list** - All Ubuntu repositories properly configured
- **Multi-provider DNS** - Cloudflare, Quad9, Google for redundancy
- **Automatic CDROM removal** - No more "Insert Ubuntu CD" errors
- **SystemD resolved support** - Works with modern DNS management

## 📦 What Gets Installed

This is not a minimal system. This is EVERYTHING.

### Core Development (All Versions)
```
GCC: 9, 10, 11, 12, 13
Clang/LLVM: Full toolchain
Python: 3.x with all scientific libraries
Java: OpenJDK 8, 11, 17, 21
Node.js, Rust, Go, Ruby, PHP, Perl
.NET Core, Mono, Erlang, Elixir
```

### Cross-Compilation Toolchains
```
ARM/AArch64: Full cross-compilation
MIPS/MIPS64: Complete toolchain
RISC-V: Full support
PowerPC: Both 32 and 64-bit
S390x, SPARC: Enterprise architectures
```

### Mobile Development
```
Android SDK: Command-line tools
ADB & Fastboot: Latest versions
Flutter/Dart: Full environment
React Native: Ready to go
Emulator support: x86_64 images
```

### System Tools
```
Filesystems: BTRFS, ZFS 2.3.4, XFS, F2FS, all FUSE
Containers: Docker, Podman, LXC/LXD, systemd-nspawn
Virtualization: QEMU/KVM, VirtualBox, libvirt
Security: AppArmor, fail2ban, ClamAV, forensics tools
Monitoring: htop, btop, glances, iotop, nethogs
```

### Quality of Life Tools
```
Terminal: tmux, zsh, fish, modern CLI
File managers: ranger, mc, vifm
Search: ripgrep, fd, fzf, ag
Modern coreutils: bat, exa, dust, broot
Network: httpie, mtr, nmap, wireshark
Development: gh CLI, tig, direnv, thefuck
```

### Desktop Software (via Snap)
```
Communication: Telegram, Signal, Discord
Editors: Sublime Text, VS Code, Vim, Emacs
Browsers: Firefox, Chromium
Development: Postman, kubectl, Docker
```

### The Full List

See [PACKAGES.md](PACKAGES.md) for the complete list of all 1300+ packages, or check `src/modules/package-installation.sh`.

## 🏗️ System Architecture

```
.
├── unified-deploy.sh           # Main entry point - orchestrates everything
├── build-orchestrator.sh       # Build controller with module management
├── deploy_persist.sh           # Handles deployment to persistent storage
├── install_all_dependencies.sh # Installs host build dependencies
├── common_module_functions.sh  # Shared functions for all modules
│
├── src/
│   ├── config/                 # Authoritative configurations
│   │   ├── sources.list        # Ubuntu 24.04 repositories
│   │   ├── sources.list.jammy  # Ubuntu 22.04 repositories
│   │   ├── resolv.conf         # DNS configuration
│   │   └── resolv.conf.systemd # SystemD resolved config
│   │
│   └── modules/                # Build modules (executed in order)
│       ├── config-apply.sh     # Applies authoritative configs
│       ├── dependency-validation.sh
│       ├── environment-setup.sh
│       ├── zfs-builder.sh      # Builds ZFS 2.3.4 from source
│       ├── package-installation.sh  # The beast - 1300+ packages
│       ├── kernel-compilation.sh
│       ├── system-configuration.sh
│       ├── initramfs-generation.sh
│       ├── iso-assembly.sh
│       ├── validation.sh
│       └── finalization.sh
```

### Build Pipeline

1. **Host Preparation**
   - Apply authoritative configurations
   - Install build dependencies
   - Remove existing ZFS versions
   - Build ZFS 2.3.4 from source

2. **Chroot Creation**
   - Bootstrap minimal Ubuntu system
   - Apply configurations to chroot
   - Install all packages (1300+)
   - Configure system services

3. **ISO Generation**
   - Create squashfs filesystem
   - Configure GRUB bootloader
   - Generate ISO image

4. **Deployment**
   - Partition target drive
   - Extract ISO contents
   - Configure persistence
   - Install bootloader

## 💻 Installation & Usage

### Prerequisites

```bash
# You need git and sudo. That's it.
sudo apt install git

# Everything else is installed automatically
```

## 🚀 Build Commands

### **Quick Validation (Run First)**
```bash
# Check system readiness without full build
./validate-build-system.sh
```

### **Setup Commands**

#### **1. Setup RAM Disk for Fast Building (Recommended)**
```bash
# Create 32GB tmpfs for much faster builds
sudo ./setup-tmpfs-build.sh

# Verify tmpfs is mounted
df -h /tmp/build
```

#### **2. Install Build Dependencies (If Needed)**
```bash
# Only if mmdebstrap is missing
sudo apt-get update
sudo apt-get install mmdebstrap
```

### **Main Build Commands**

#### **Full ISO Build**
```bash
# Standard build using tmpfs (fastest)
sudo BUILD_ROOT=/tmp/build ./build-orchestrator.sh build

# Alternative: Build to disk (slower but more space)
sudo BUILD_ROOT=/home/build ./build-orchestrator.sh build

# With specific profile
sudo BUILD_ROOT=/tmp/build BUILD_PROFILE=development ./build-orchestrator.sh build
```

#### **Build with Recovery Options**
```bash
# Build with checkpoints enabled (recommended for testing)
sudo BUILD_ROOT=/tmp/build CHECKPOINT_INTERVAL=300 ./build-orchestrator.sh build

# Resume from checkpoint if build fails
sudo ./checkpoint-manager.sh resume latest
sudo BUILD_ROOT=/tmp/build ./build-orchestrator.sh build
```

### **Deployment Commands**

#### **Full Build + Deploy to USB/SSD**
```bash
# Complete workflow: build ISO and deploy to device
sudo BUILD_ROOT=/tmp/build ./unified-deploy.sh full /dev/sda

# Deploy with custom ISO file
sudo ./unified-deploy.sh deploy /dev/sda --iso-file /tmp/build/ubuntu.iso
```

#### **Deploy Existing ISO**
```bash
# If you already have ubuntu.iso
sudo ./deploy_persist.sh /dev/sda /path/to/ubuntu.iso
```

### **Build Profiles Available**

```bash
# Minimal system
sudo BUILD_ROOT=/tmp/build BUILD_PROFILE=minimal ./build-orchestrator.sh build

# Development system (includes dev tools)
sudo BUILD_ROOT=/tmp/build BUILD_PROFILE=development ./build-orchestrator.sh build

# ZFS-optimized system
sudo BUILD_ROOT=/tmp/build BUILD_PROFILE=zfs_optimized ./build-orchestrator.sh build

# Security-focused system
sudo BUILD_ROOT=/tmp/build BUILD_PROFILE=security ./build-orchestrator.sh build
```

### **Build Monitoring**

#### **Check Build Progress**
```bash
# Monitor build logs in real-time
tail -f /tmp/build/build-*.log

# Check current module
cat /tmp/build/.checkpoints/current_module

# View module progress
ls -la /tmp/build/.checkpoints/
```

#### **Build Status**
```bash
# Quick status check
./checkpoint-manager.sh status

# Detailed module status
cat /tmp/build/.checkpoints/completed_modules
```

### **Recovery Commands**

#### **If Build Fails**
```bash
# Emergency recovery
sudo ./build-recovery.sh

# Clean and restart
sudo rm -rf /tmp/build
sudo ./setup-tmpfs-build.sh
sudo BUILD_ROOT=/tmp/build ./build-orchestrator.sh build
```

#### **Git Repository Maintenance**
```bash
# Clean git repository if needed
sudo ./git-cleanup.sh
```

### **Expected Output Locations**

```bash
# Final ISO file
/tmp/build/ubuntu.iso

# Build logs
/tmp/build/build-*.log
/tmp/build/.logs/

# Checkpoints
/tmp/build/.checkpoints/

# Chroot (during build)
/tmp/build/chroot/
```

### **Build Time Estimates**

- **Chroot Creation (20-25%)**: 5-10 minutes
- **Package Installation (40-60%)**: 15-30 minutes  
- **System Configuration (60-80%)**: 10-15 minutes
- **ISO Assembly (80-95%)**: 5-10 minutes
- **Total Build Time**: 45-75 minutes (depending on network and disk speed)

### **Quick Start (Recommended)**

```bash
# 1. Validate system
./validate-build-system.sh

# 2. Setup fast storage
sudo ./setup-tmpfs-build.sh

# 3. Build ISO
sudo BUILD_ROOT=/tmp/build ./build-orchestrator.sh build

# 4. Deploy to USB (optional)
sudo ./unified-deploy.sh deploy /dev/sdX --iso-file /tmp/build/ubuntu.iso
```

### **Environment Variables**

```bash
# Common build customizations
export BUILD_ROOT="/tmp/build"           # Build location
export BUILD_PROFILE="development"       # Build type
export BUILD_SUITE="noble"              # Ubuntu version
export BUILD_ARCH="amd64"               # Architecture
export MAX_PARALLEL_JOBS="$(nproc)"     # CPU cores to use
export BUILD_TIMEOUT="7200"             # 2 hour timeout
```

### Basic Usage (Legacy Commands)

#### Full Build and Deploy
```bash
# This does EVERYTHING - builds ISO and deploys to drive
sudo ./unified-deploy.sh full /dev/sdb
```

#### Build ISO Only
```bash
# Creates ubuntu.iso in current directory
sudo ./unified-deploy.sh build
```

#### Deploy Existing ISO
```bash
# Deploy the ISO you just built
sudo ./unified-deploy.sh deploy /dev/sdc

# Deploy a downloaded Ubuntu ISO (won't have custom packages)
sudo ./unified-deploy.sh deploy /dev/sdc --iso-file ubuntu-24.04.iso
```

#### Validate Environment
```bash
# Check if everything is ready
sudo ./unified-deploy.sh validate
```

### Advanced Options

```bash
# Custom username and password
sudo ./unified-deploy.sh full /dev/sdb \
    --username myuser \
    --password mypass

# Different filesystem
sudo ./unified-deploy.sh deploy /dev/sdc \
    --filesystem ext4

# Custom build type
sudo ./unified-deploy.sh build development
```

## ⚙️ Configuration Management

### Authoritative Sources

The system uses authoritative configuration files in `src/config/`:

#### sources.list
- All Ubuntu repositories enabled (main, restricted, universe, multiverse)
- Security updates from multiple mirrors
- Partner repositories for proprietary software
- No CDROM sources ever

#### resolv.conf
- Primary: Cloudflare (1.1.1.1, 1.0.0.1)
- Secondary: Quad9 (9.9.9.9)
- Tertiary: Google (8.8.8.8)
- Automatic rotation and redundancy

### Automatic Configuration

The `config-apply` module automatically:
- Removes CDROM sources
- Applies correct sources.list
- Configures DNS properly
- Handles systemd-resolved
- Optimizes APT settings

## 🔧 Module System

Modules execute in this order:

| Order | Module | Purpose |
|-------|--------|---------|
| 5 | config-apply | Apply authoritative configs to host |
| 10 | dependency-validation | Verify build dependencies |
| 15 | environment-setup | Create build environment |
| 20 | mmdebootstrap/orchestrator | Bootstrap base system |
| 30 | config-apply | Apply configs to chroot |
| 35 | zfs-builder | Build ZFS 2.3.4 from source |
| 40 | kernel-compilation | Compile custom kernel (optional) |
| 50 | package-installation | Install ALL packages (1300+) |
| 60 | system-configuration | Configure services |
| 70 | initramfs-generation | Create initramfs |
| 80 | iso-assembly | Build ISO image |
| 90 | validation | Verify build |
| 95 | finalization | Clean up |

### Creating Custom Modules

Create a new module in `src/modules/`:

```bash
#!/bin/bash
# my-module.sh

source "$REPO_ROOT/common_module_functions.sh"

MODULE_NAME="my-module"
BUILD_ROOT="${1:-/tmp/build}"

main() {
    log_info "Starting my module..."
    # Your code here
    log_success "Module complete"
}

main "$@"
```

Add it to `MODULE_EXECUTION_ORDER` in `build-orchestrator.sh`.

## 🔍 Debugging & Troubleshooting

### Verbose Logging

All builds run with verbose logging:
```bash
# Logs are saved to
/tmp/build-YYYYMMDD-HHMMSS.log
/tmp/build/.logs/module_*.log
```

### Common Issues

#### CDROM Source Errors
**Problem**: "Please insert Ubuntu CD"  
**Solution**: Automatically fixed by config-apply module

#### DNS Resolution Failed
**Problem**: Can't resolve package servers  
**Solution**: Automatically fixed by authoritative resolv.conf

#### ZFS Version Mismatch
**Problem**: Wrong ZFS version installed  
**Solution**: Automatically removes old versions and builds 2.3.4

#### Snap Package Installation Fails (FIXED)
**Problem**: Build fails with exit code 127 during snap package installation  
**Solution**: Snap packages don't work reliably in chroot environments. The build now skips snap installation during build and defers it to post-boot.

After first boot, install snap packages manually:
```bash
sudo snap install telegram-desktop
sudo snap install signal-desktop  
sudo snap install sublime-text --classic
sudo snap install code --classic
sudo snap install discord
```

#### VPN Installation (Post-Boot)

**Mullvad VPN**:
```bash
# Download and install Mullvad
wget https://mullvad.net/download/app/deb/latest -O mullvad.deb
sudo dpkg -i mullvad.deb
sudo apt-get install -f  # Fix any dependency issues

# Alternative: Use their repository
sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$( dpkg --print-architecture )] https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/mullvad.list
sudo apt update
sudo apt install mullvad-vpn
```

**NordVPN**:
```bash
# Download and install NordVPN
wget https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb
sudo dpkg -i nordvpn-release_1.0.0_all.deb
sudo apt update
sudo apt install nordvpn

# Login and setup
nordvpn login
nordvpn set technology nordlynx  # Use WireGuard
nordvpn set killswitch on        # Enable kill switch
nordvpn connect                  # Connect to fastest server
```

**OpenVPN configs** (for any provider):
```bash
# OpenVPN client is already installed in the build
sudo apt install openvpn-systemd-resolved  # For DNS handling

# Import config files to /etc/openvpn/client/
sudo cp your-vpn-config.ovpn /etc/openvpn/client/
sudo systemctl start openvpn-client@your-vpn-config
sudo systemctl enable openvpn-client@your-vpn-config
```

#### Automated VPN Installation (During Build)

For automatic VPN installation during the build process, use the post-build installer:

```bash
# After build completes but before ISO creation
sudo ./post-build-vpn-installer.sh

# This will chroot in and install:
# - Mullvad VPN (latest .deb)
# - NordVPN (with repository)
# - OpenVPN extras (systemd-resolved, NetworkManager plugins)
# - First-boot setup script at /usr/local/bin/setup-vpns
```

After first boot of the ISO:
```bash
sudo setup-vpns  # Shows configuration instructions
```

#### Build Fails at Module X
```bash
# Check specific module log
cat /tmp/build/.logs/module_<name>.log

# Resume from checkpoint
sudo ./build-orchestrator.sh --continue
```

#### Out of Disk Space
**Problem**: Build needs 20-30GB free  
**Solution**: 
```bash
# Clean build artifacts
sudo ./build-orchestrator.sh clean

# Use different build directory
BUILD_ROOT=/path/to/larger/disk sudo ./unified-deploy.sh build
```

### Recovery Options

```bash
# Clean everything and start over
sudo ./build-orchestrator.sh clean
sudo rm -rf /tmp/build

# Check what went wrong
sudo journalctl -xe
sudo dmesg | tail -50

# Validate system state
sudo ./unified-deploy.sh validate
```

## 🚀 Advanced Usage

### Custom Package Lists

Edit `src/modules/package-installation.sh` to add/remove packages:

```bash
# Add your packages to a category
QOL_PACKAGES+=(
    "my-custom-package"
    "another-package"
)
```

### Custom Configurations

Add files to `src/config/`:
```bash
# Custom apt preferences
src/config/apt/preferences

# Custom sysctls
src/config/sysctl.d/99-custom.conf
```

### Build Profiles

Create build profiles in `src/config/mmdebstrap/`:
```yaml
profiles:
  custom:
    packages:
      - essential-package
      - custom-tool
    description: "My custom profile"
```

### Using Different Ubuntu Versions

```bash
# For Ubuntu 22.04
export DEBIAN_RELEASE="jammy"
sudo ./unified-deploy.sh build

# For Ubuntu 24.04 (default)
export DEBIAN_RELEASE="noble"
sudo ./unified-deploy.sh build
```

### ZFS Instead of BTRFS

```bash
# Build with ZFS support
sudo ./unified-deploy.sh full /dev/sdb --filesystem zfs

# The system includes ZFS 2.3.4 built from source
```

### Network Install

```bash
# Install to remote system via SSH
ssh user@remote "curl -L https://your-repo/install.sh | sudo bash"
```

## ⚠️ Important Warnings

### THIS WILL DESTROY DATA
- The deployment phase **COMPLETELY WIPES** the target drive
- All data will be **PERMANENTLY DESTROYED**
- There is **NO UNDO**
- Always verify the device path
- The script asks for confirmation - read it

### System Requirements
- **Disk Space**: 20-30GB free for build
- **RAM**: 4GB minimum, 8GB recommended
- **Time**: 30-60 minutes (depends on internet speed)
- **Privileges**: Root access required
- **OS**: Ubuntu 20.04+ or Debian 11+

### Security Notes
- Microcode loading is **DISABLED** by default
- Secure Boot may need to be disabled
- Some security software may flag the large ISO

## 📈 Performance Metrics

Typical build on modern hardware:
- **Bootstrap**: 2-3 minutes
- **Package installation**: 20-30 minutes
- **ISO creation**: 5-10 minutes
- **Total time**: 30-60 minutes

Final ISO size: **8-12GB** (compressed)
Installed system size: **15-20GB** (uncompressed)
Package count: **1300+**

## 🤝 Contributing

Fork it, break it, fix it, improve it. PRs welcome.

### Guidelines
1. Keep the military naming scheme (it's funny)
2. Document everything verbosely
3. Test on real hardware
4. Add more packages, never remove
5. Maintain backwards compatibility

## 📜 License

**WTFPL + DICE** - Do What The F*** You Want To Public License

With the dice clause: If you make money, roll 2d6 for my percentage.

See [LICENSE](LICENSE) for the full comedic text.

## 🙏 Acknowledgments

- **Ubuntu/Debian teams** - For the base we're thoroughly abusing
- **BTRFS/ZFS developers** - For filesystems that don't suck
- **Coffee** - For making this possible
- **Stack Overflow** - For having answers to questions I didn't know existed
- **You** - For being brave enough to run this

## 📞 Support

There is no support. You're on your own.

But if you find bugs, open an issue and maybe someone will care.

## 🎲 The Dice Clause

If this makes you money, roll 2d6:
- 2: You owe me 2%
- 7: You owe me 7%  
- 12: You owe me 12%

*Not legally binding but karma is real*

---

**Final Warning**: This is production-ready but also experimental. It works on my machine. It might work on yours. It might also summon demons. Use at your own risk.

**Remember**: With great build systems comes great responsibility to not accidentally wipe your main drive. Always check twice, deploy once.

*Built with ❤️ and excessive amounts of bash by someone who should probably know better*