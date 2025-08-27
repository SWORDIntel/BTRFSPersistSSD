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

### Basic Usage

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