# BTRFS Persistent Ubuntu LiveCD Build System

A comprehensive build and deployment system for creating custom Ubuntu LiveCDs with persistent storage, BTRFS filesystem, and over 1300 pre-installed packages.

## What This Does

This repository contains scripts that:
1. Build a custom Ubuntu ISO from scratch with ALL the packages you could ever want
2. Deploy that ISO (or any Ubuntu ISO) to a drive with BTRFS persistence
3. Include every development tool, compiler, cross-compilation toolchain, and quality-of-life utility imaginable

## Features

### Build System
- **Modular architecture** - Each build phase is a separate module in `src/modules/`
- **1300+ packages** pre-installed including:
  - Complete kernel compilation toolchain (all architectures)
  - Cross-compilation for ARM, MIPS, RISC-V, PowerPC, etc.
  - Android SDK and mobile development tools
  - Java ecosystem (JDK 8, 11, 17, 21)
  - Every programming language and framework
  - Security and forensics tools
  - Quality of life tools (htop, btop, ranger, fzf, ripgrep, etc.)
  - Snap packages (Telegram, Signal, Sublime Text)
- **Dependency management** - Automatically installs all required build tools
- **BTRFS with compression** - zstd:6 compression by default
- **ZFS support** - Full ZFS filesystem tools included

### Deployment System
- Deploy to **any target drive** (specify device as parameter)
- Automatic partition creation (BTRFS + EFI)
- Persistent storage configuration
- GRUB bootloader with custom entries
- User account creation with sudo privileges

## Quick Start

### Prerequisites
```bash
# The scripts will install dependencies automatically, but you need:
sudo apt install git
```

### Clone and Setup
```bash
git clone https://github.com/yourusername/btrfs-persist-ssd.git
cd btrfs-persist-ssd
sudo chmod +x *.sh
```

### Usage

#### Option 1: Full Build and Deploy (Recommended)
```bash
# Build custom ISO and deploy to drive in one command
sudo ./unified-deploy.sh full /dev/sdb
```

#### Option 2: Build ISO Only
```bash
# Create custom Ubuntu ISO with all packages
sudo ./unified-deploy.sh build
```

#### Option 3: Deploy Existing ISO
```bash
# Deploy any Ubuntu ISO to drive
sudo ./unified-deploy.sh deploy /dev/sdc --iso-file ubuntu-22.04.iso

# Deploy the custom-built ISO
sudo ./unified-deploy.sh deploy /dev/sdc
```

### Advanced Options
```bash
# Custom username and password
sudo ./unified-deploy.sh full /dev/sdb --username myuser --password mypass

# Different filesystem
sudo ./unified-deploy.sh deploy /dev/sdc --filesystem ext4

# Validate environment without building
sudo ./unified-deploy.sh validate
```

## What Gets Installed

The `package-installation.sh` module installs **EVERYTHING**:

### Development Tools
- **Compilers**: GCC 9-13, Clang/LLVM, Rust, Go, Java, Python, Node.js
- **Build Systems**: Make, CMake, Ninja, Meson, Gradle, Maven
- **Cross-Compilation**: Full toolchains for ARM, AArch64, MIPS, RISC-V, PowerPC, S390x, SPARC
- **Kernel Development**: Headers, sources, debugging tools, SystemTap
- **Android Development**: SDK, ADB, Fastboot, emulator support
- **Debugging**: GDB, Valgrind, strace, ltrace, rr-debugger

### System Tools
- **Filesystems**: BTRFS, ZFS, XFS, F2FS, all FUSE filesystems
- **Containers**: Docker, Podman, LXC/LXD, systemd-nspawn
- **Virtualization**: QEMU/KVM, VirtualBox, libvirt
- **Security**: AppArmor, fail2ban, ClamAV, forensics tools
- **Monitoring**: htop, btop, glances, iotop, nethogs

### Quality of Life
- **Terminal**: tmux, zsh, fish, modern CLI tools
- **File Management**: ranger, mc, fzf, ripgrep, fd, bat
- **Network**: curl, wget, httpie, mtr, nmap, wireshark
- **Text Processing**: jq, yq, xmlstarlet, modern grep alternatives

### Desktop Software (via Snap)
- Telegram Desktop
- Signal Desktop  
- Sublime Text
- VS Code
- Discord
- Firefox, Chromium
- And much more...

## Project Structure

```
.
├── build-orchestrator.sh       # Main build controller
├── deploy_persist.sh           # Deployment to persistent storage
├── unified-deploy.sh           # Unified interface for everything
├── install_all_dependencies.sh # Host dependency installation
├── common_module_functions.sh  # Shared functions
└── src/
    ├── modules/
    │   ├── dependency-validation.sh
    │   ├── environment-setup.sh
    │   ├── package-installation.sh  # The beast - installs everything
    │   ├── kernel-compilation.sh
    │   ├── system-configuration.sh
    │   ├── initramfs-generation.sh
    │   ├── iso-assembly.sh
    │   └── ...
    └── config/
        └── mmdebstrap/
            └── profiles_config.yaml
```

## System Requirements

- **Disk Space**: 20-30GB free for build environment
- **RAM**: 4GB minimum, 8GB recommended
- **Time**: 30-60 minutes for full build (depends on network speed)
- **OS**: Ubuntu 20.04+ or Debian 11+ host system
- **Privileges**: Root access required

## How It Works

1. **Dependency Phase**: `install_all_dependencies.sh` ensures all build tools are installed
2. **Build Phase**: Creates chroot environment, installs all packages, generates squashfs
3. **ISO Assembly**: Packages everything into bootable ISO with GRUB
4. **Deployment Phase**: Extracts ISO to target drive with persistent BTRFS filesystem

## Warning

⚠️ **DESTRUCTIVE OPERATION** ⚠️
- The deployment phase will **COMPLETELY WIPE** the target drive
- All data on the target device will be **PERMANENTLY DESTROYED**
- Always double-check the device path before proceeding
- The script will ask for confirmation, type 'PROCEED' or 'DEPLOY' to continue

## Troubleshooting

### Build Fails
```bash
# Check environment
sudo ./unified-deploy.sh validate

# Clean and retry
sudo ./build-orchestrator.sh clean
sudo ./unified-deploy.sh build
```

### Missing Dependencies
```bash
# Manually install dependencies
sudo ./install_all_dependencies.sh
```

### ISO Not Found
```bash
# Check for ISO in current directory
ls -la *.iso

# Check build directory
ls -la /tmp/build/*.iso
```

## Using Downloaded ISOs

You can use this system to deploy standard Ubuntu ISOs downloaded from ubuntu.com, but note:
- Downloaded ISOs won't have the custom packages from `package-installation.sh`
- You'll get a standard Ubuntu system with BTRFS persistence
- For the full experience with all packages, build a custom ISO

## License

**WTFPL + DICE** - Do What The F*** You Want To Public License (with dice clause)

Do whatever you want with this code. Print it out and use it as toilet paper if you want. Copy it, modify it, sell it, claim you wrote it, use it to take over the world - whatever floats your boat.

**THE DICE CLAUSE**: If you somehow make money off this, I want a percentage determined by rolling 2d6 (two six-sided dice). Whatever you roll, that's my cut as a percentage. So between 2% and 12%. For example, you roll a 4 and a 5, you owe me 9% of profits. This is not legally binding but it would be pretty cool if you did it anyway.

No warranty, no support, no guarantees. If it breaks your computer, catches fire, or becomes sentient and decides to eliminate humanity, that's on you.

See [LICENSE](LICENSE) for the full text.

## Contributing

Sure, why not. Fork it, PR it, break it, fix it. The more chaos, the better.

## Author

Some person who spent way too much time automating something that should have been simple.

## Acknowledgments

- The Debian/Ubuntu teams for making this possible
- The BTRFS developers for a filesystem that doesn't suck
- Coffee, for making late-night coding sessions bearable
- Stack Overflow, for having answers to questions I didn't know I had
- Dice, for providing a fair and chaotic method of determining royalties

---

*Remember: With great build systems comes great responsibility to not accidentally wipe your main drive. Always check twice, deploy once.*

*P.S. - If this somehow makes you rich, don't forget to roll those dice! 🎲🎲*