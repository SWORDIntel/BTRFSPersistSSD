# MODULE DEPENDENCY MAP

## Build Flow and Dependencies

This document maps what each module expects to exist and what it creates.

### Phase 1: Validation and Setup (10-15%)

#### 10% - dependency-validation.sh
**Expects:** 
- Host system with sudo access
- Nothing else - runs first

**Creates:**
- Validation report at $BUILD_ROOT/validation-report.txt
- Basic directory structure: $BUILD_ROOT, $BUILD_ROOT/work, $BUILD_ROOT/logs, $BUILD_ROOT/cache

**Dependencies:** None (first module)

---

#### 15% - environment-setup.sh  
**Expects:**
- $BUILD_ROOT directory exists
- Host system validated

**Creates:**
- Build directory structure: $CHROOT_DIR, $WORK_DIR/iso, $WORK_DIR/scratch
- APT cache configuration at $BUILD_ROOT/config/apt-cache.conf
- Network configuration files in $CHROOT_DIR/etc/ (but chroot doesn't exist yet)

**Dependencies:** dependency-validation (10%)

---

### Phase 2: Chroot Creation (20-25%)

#### 20% - mmdebootstrap/orchestrator.sh
**Expects:**
- $BUILD_ROOT and parent directories exist
- mmdeboostrap command available
- Network connectivity

**Creates:**
- **THE CHROOT** at $BUILD_ROOT/chroot
- Marker files: .mmdebstrap-complete, .mmdebstrap-timestamp
- Base Ubuntu Noble system with essential packages

**Dependencies:** environment-setup (15%)

---

#### 25% - stages-enhanced/03-mmdebstrap-bootstrap.sh
**Expects:**
- **CHROOT EXISTS** at $BUILD_ROOT/chroot (created by 20%)
- .mmdebstrap-complete marker file
- Build profile variables: $BUILD_PROFILE, $BUILD_SUITE, $BUILD_ARCH

**Creates:**
- Profile-specific configurations in chroot
- Additional directories for development/zfs/security profiles
- Build information file at $CHROOT_DIR/etc/build-info

**Dependencies:** mmdebootstrap/orchestrator (20%)

---

### Phase 3: Configuration (28-30%)

#### 28% - chroot-dependencies.sh
**Expects:**
- **CHROOT EXISTS** at $BUILD_ROOT/chroot  
- install_all_dependencies.sh exists in repo root
- Config files in src/config/

**Creates:**
- All system dependencies installed INSIDE the chroot
- Configured package repositories in chroot
- Checkpoint: chroot_dependencies_installed

**Dependencies:** stages-enhanced/03-mmdebstrap-bootstrap (25%)

---

#### 30% - config-apply.sh
**Expects:**
- **CHROOT EXISTS** at $BUILD_ROOT/chroot
- Config files in $REPO_ROOT/src/config/
- Network connectivity for package updates

**Creates:**
- Applied sources.list configuration
- DNS configuration (resolv.conf)
- APT optimizations for build performance
- Updated package lists in chroot

**Dependencies:** chroot-dependencies (28%)

---

### Phase 4: Building Components (35-80%)

#### 35% - zfs-builder.sh
**Expects:**
- **CHROOT EXISTS** with dependencies installed
- ZFS development packages in chroot
- Internet access for source downloads

**Creates:**
- ZFS 2.3.4 compiled from source (if needed)
- ZFS kernel modules
- ZFS utilities in chroot

**Dependencies:** config-apply (30%)

---

#### 38% - dell-cctk-builder.sh  
**Expects:**
- **CHROOT EXISTS** with build tools
- Network access for downloads

**Creates:**
- Dell Command Configure Toolkit (CCTK)
- TPM2 tools
- Hardware configuration utilities

**Dependencies:** zfs-builder (35%)

---

#### 40% - kernel-compilation.sh
**Expects:**
- **CHROOT EXISTS** with build tools
- ZFS modules available (if ZFS enabled)

**Creates:**
- Custom kernel (if BUILD_KERNEL=true)
- Kernel modules
- Kernel headers

**Dependencies:** dell-cctk-builder (38%)

---

#### 50% - package-installation.sh
**Expects:**
- **CHROOT EXISTS** with basic system
- Package repositories configured
- ~20GB disk space available

**Creates:**
- 1300+ packages installed in chroot
- Snap packages (if enabled)
- Cleaned package cache

**Dependencies:** kernel-compilation (40%)

---

### Phase 5: System Configuration (60-70%)

#### 60% - system-configuration.sh
**Expects:**
- **CHROOT EXISTS** with all packages installed
- User account requirements defined

**Creates:**
- System users and groups
- Service configurations
- System-wide settings

**Dependencies:** package-installation (50%)

---

#### 70% - initramfs-generation.sh
**Expects:**
- **CHROOT EXISTS** with kernel and modules
- ZFS modules (if ZFS enabled)

**Creates:**
- Custom initramfs with ZFS support
- Boot-critical modules included
- Initramfs hooks configured

**Dependencies:** system-configuration (60%)

---

### Phase 6: ISO Assembly (80-90%)

#### 80% - iso-assembly.sh
**Expects:**
- **CHROOT EXISTS** fully configured
- Initramfs generated
- ISO workspace at $WORK_DIR/iso

**Creates:**
- ISO filesystem structure
- SquashFS compressed filesystem
- Bootloader configuration

**Dependencies:** initramfs-generation (70%)

---

### Phase 7: Finalization (90-95%)

#### 90% - validation.sh
**Expects:**
- ISO file exists
- Boot configuration complete

**Creates:**
- ISO validation report
- Boot capability verification
- Integrity checksums

**Dependencies:** iso-assembly (80%)

---

#### 95% - finalization.sh
**Expects:**
- Validated ISO file
- All build phases complete

**Creates:**
- Final ISO at specified location
- Build summary report
- Cleanup of temporary files

**Dependencies:** validation (90%)

---

## Critical Dependencies Summary

### Files Required Throughout Build:
- $BUILD_ROOT/chroot/ (created at 20%, used by all subsequent modules)
- $REPO_ROOT/src/config/ (sources.list, resolv.conf, etc.)
- $REPO_ROOT/install_all_dependencies.sh (used at 28%)
- $REPO_ROOT/common_module_functions.sh (used by all modules)

### Environment Variables Required:
- BUILD_ROOT: Base build directory
- CHROOT_DIR: Target chroot path ($BUILD_ROOT/chroot)
- REPO_ROOT: Repository root directory
- BUILD_SUITE: Ubuntu release (default: noble)
- BUILD_ARCH: Target architecture (default: amd64)
- BUILD_PROFILE: Build profile (default: standard)

### Network Dependencies:
- 15%: Network for configuration files
- 20%: Network for mmdebstrap package downloads
- 28%: Network for dependency installation
- 30%: Network for package repository updates
- 35%+: Network for source downloads and updates

## Failure Points to Monitor:

1. **20%**: If chroot creation fails, all subsequent modules will fail
2. **28%**: If dependency installation fails, build components may not work
3. **30%**: If network configuration fails, package installation may fail
4. **50%**: If package installation fails, system will be incomplete
5. **70%**: If initramfs fails, ISO may not boot

The build is designed to fail fast - if any critical dependency is missing, the build stops immediately rather than producing a broken ISO.