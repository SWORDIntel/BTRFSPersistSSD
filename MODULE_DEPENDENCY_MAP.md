# Module Dependency Map

## Critical Build Order (Must Execute in This Sequence)

### Phase 1: Validation & Setup (10-15%)
- `dependency-validation.sh` (10%) - Validates host system
- `environment-setup.sh` (15%) - Creates directories only

### Phase 2: Chroot Creation (20%)
- `mmdebootstrap/orchestrator.sh` (20%) - **CREATES CHROOT** (ONLY module that should!)

### Phase 3: Chroot Verification & Enhancement (25%)
- `stages-enhanced/03-mmdebstrap-bootstrap.sh` (25%) - Verifies and enhances existing chroot

### Phase 4: Dependency Installation (28%)
- `chroot-dependencies.sh` (28%) - Installs packages IN chroot

### Phase 5: Configuration (30%)
- `config-apply.sh` (30%) - Applies system configuration

### Phase 6: Package Installation (35-45%)
- `package-installation.sh` (35%) - Installs 1300+ packages
- `zfs-builder.sh` (40%) - Compiles ZFS 2.3.4
- `dell-cctk-builder.sh` (42%) - Builds Dell CCTK tools

### Phase 7: System Assembly (50-80%)
- `kernel-compilation.sh` (50%) - Kernel customization
- `initramfs-generation.sh` (60%) - Creates initramfs
- `module-scripts.sh` (70%) - ISO assembly

### Phase 8: Boot Configuration (85%)
- `boot-configuration.sh` (85%) - Sets up GRUB/EFI

### Phase 9: Finalization (90-95%)
- `validation.sh` (90%) - Final validation
- `finalization.sh` (95%) - Cleanup and packaging

## Dependencies by Module

### Common Dependencies (All Modules)
- `common_module_functions.sh` - Logging, checkpoints, utilities
- `BUILD_ROOT` environment variable
- Root privileges

### mmdebootstrap/orchestrator.sh
**Creates:** 
- `$BUILD_ROOT/chroot` directory
- Base Ubuntu system in chroot
**Depends on:**
- mmdeboostrap package installed
- Network connectivity
- `$BUILD_ROOT` directory exists

### stages-enhanced/03-mmdebstrap-bootstrap.sh
**Requires:**
- Chroot already exists at `$CHROOT_DIR`
- Created by mmdebootstrap/orchestrator.sh at 20%
**Does NOT create chroot** - only verifies and enhances

### chroot-dependencies.sh
**Requires:**
- Chroot exists
- `install_all_dependencies.sh` script
**Installs packages inside chroot**

### package-installation.sh
**Requires:**
- Chroot with dependencies installed
- Network connectivity in chroot
**Installs 1300+ packages**

### zfs-builder.sh
**Requires:**
- Chroot with build tools
- Kernel headers
- Network connectivity
**Produces:** ZFS 2.3.4 modules

### boot-configuration.sh
**Requires:**
- Complete chroot system
- EFI partition mounted
- GRUB packages installed in chroot

## Critical Rules

1. **ONLY** mmdebootstrap/orchestrator.sh creates chroot (at 20%)
2. **NO** module before 20% should create or expect chroot
3. **ALL** modules after 20% must check chroot exists
4. **NEVER** use readonly variables
5. **ALWAYS** use log_warning not log_warn

## Module Interdependencies

```
dependency-validation → environment-setup → mmdebootstrap/orchestrator
                                                    ↓
                                         stages-enhanced/bootstrap
                                                    ↓
                                            chroot-dependencies
                                                    ↓
                                              config-apply
                                                    ↓
                                         ┌─ package-installation
                                         ├─ zfs-builder
                                         └─ dell-cctk-builder
                                                    ↓
                                            kernel-compilation
                                                    ↓
                                           initramfs-generation
                                                    ↓
                                             module-scripts
                                                    ↓
                                          boot-configuration
                                                    ↓
                                            validation → finalization
```