# Claude AI Integration Guide

## Project Overview
This is a comprehensive Ubuntu LiveCD build and deployment system that creates custom ISOs with persistent BTRFS storage, extensive package installation (1300+ packages), and modular architecture.

## Critical Guidelines for Claude

### 🚫 NEVER USE READONLY IN BASH
**This is the #1 rule for this project**
- **NEVER** declare variables as `readonly` in any bash script
- Variables like `BUILD_ROOT`, `CHROOT_DIR`, `LOG_DIR` need to be reassignable
- With `set -e`, readonly variables cause build failures when reassigned
- Instead of `readonly VAR="value"`, use `VAR="value"`

### Build Order is CRITICAL
The correct module execution order MUST be:
1. **10%**: dependency-validation (validate environment, NO chroot)
2. **15%**: environment-setup (prepare directories, NO chroot creation)
3. **20%**: mmdebootstrap/orchestrator (CREATE CHROOT HERE)
4. **25%**: stages-enhanced/03-mmdebstrap-bootstrap
5. **28%**: chroot-dependencies (install deps IN chroot)
6. **30%**: config-apply (configure the existing chroot)
7. **35%+**: Everything else

**NEVER** create chroot before 20%. **ONLY** mmdeboostrap creates it.

### Use mmdeboostrap, NOT debootstrap
- We use `mmdeboostrap` exclusively for chroot creation
- It's faster (2-3x) and handles modern requirements better
- `debootstrap` references should only exist as fallback documentation

### Dependencies Install in Chroot, Not Host
- `install_all_dependencies.sh` should NEVER run on the host
- Dependencies are installed at 28% via `chroot-dependencies` module
- The host only needs minimal tools to create the chroot

### Arithmetic Operations Need Protection
With `set -e`, operations like `((var++))` fail when var=0. Always use:
```bash
((var++)) || true
```

### Function Name Consistency
- Use `log_warning` not `log_warn`
- Use `log_error` not `log_err` 
- Check common_module_functions.sh for available functions

### Build in RAM for Speed
```bash
# Setup 32GB tmpfs (for 64GB RAM systems)
sudo ./setup-tmpfs-build.sh
sudo BUILD_ROOT=/tmp/build ./build-orchestrator.sh build
```
Never use `/dev/shm` - it has `noexec` restrictions.

## Quick Commands

### Full Build and Deploy
```bash
# Setup tmpfs
sudo ./setup-tmpfs-build.sh

# Build and deploy to /dev/sda
sudo BUILD_ROOT=/tmp/build ./unified-deploy.sh full /dev/sda
```

### Build Only
```bash
sudo BUILD_ROOT=/tmp/build ./build-orchestrator.sh build
```

### Deploy Existing ISO
```bash
sudo ./unified-deploy.sh deploy /dev/sda --iso-file /tmp/build/ubuntu.iso
```

### Recovery Commands
```bash
# If build gets stuck
sudo ./build-recovery.sh

# Clean git repository
sudo ./git-cleanup.sh

# Manage checkpoints
sudo ./checkpoint-manager.sh
```

## Common Issues and Fixes

### "readonly variable" error
- **Cause**: Variable declared as readonly being reassigned
- **Fix**: Remove `readonly` keyword from variable declaration

### "Command not found: log_warn"
- **Cause**: Wrong function name
- **Fix**: Change to `log_warning`

### "/dev/shm/build/chroot: Permission denied"
- **Cause**: `/dev/shm` has noexec/nodev
- **Fix**: Use `/tmp/build` with setup-tmpfs-build.sh

### "Chroot directory not found"
- **Cause**: Module running before chroot created
- **Fix**: Ensure module runs after 20% when mmdeboostrap creates chroot

### Package installation timeouts
- **Cause**: Package already installed or actually hanging
- **Fix**: Check problematic-packages.list, increase timeout, or skip

## Project Structure
```
/
├── unified-deploy.sh           # Main orchestration script
├── build-orchestrator.sh       # Build controller
├── deploy_persist.sh          # Deployment script
├── install_all_dependencies.sh # Dependency installer (runs IN chroot)
├── setup-tmpfs-build.sh       # Create RAM disk
├── build-recovery.sh          # Recovery tools
├── checkpoint-manager.sh      # Build checkpoints
├── git-cleanup.sh            # Git maintenance
└── src/
    ├── modules/              # Build modules (run in order)
    │   ├── dependency-validation.sh
    │   ├── environment-setup.sh
    │   ├── mmdebootstrap/
    │   ├── chroot-dependencies.sh
    │   ├── config-apply.sh
    │   ├── zfs-builder.sh
    │   └── package-installation.sh
    └── config/              # Configuration files
        ├── sources.list     # Ubuntu repositories
        ├── resolv.conf      # DNS configuration
        └── problematic-packages.list

```

## Testing Checklist
When making changes, verify:
- [ ] No `readonly` variables in any bash scripts
- [ ] Module execution order maintained (chroot at 20%)
- [ ] All `log_warn` → `log_warning`
- [ ] Arithmetic operations have `|| true`
- [ ] Dependencies install in chroot, not host
- [ ] Using `/tmp/build` not `/dev/shm/build`
- [ ] mmdeboostrap handles chroot creation

## Important Files to Check
1. **build-orchestrator.sh**: Module execution order
2. **unified-deploy.sh**: Should NOT call install_host_dependencies
3. **environment-setup.sh**: Should NOT create chroot
4. **common_module_functions.sh**: No readonly for BUILD_ROOT, LOG_DIR, etc.

## Build Phases
1. **Preparation**: Validate environment, setup directories
2. **Bootstrap**: Create chroot with mmdeboostrap (20-25%)
3. **Configuration**: Install deps, apply configs (28-30%)
4. **Building**: Compile components, install packages (35-50%)
5. **Assembly**: Create initramfs, build ISO (60-80%)
6. **Finalization**: Validate and package (90-95%)

## Remember
- This builds a COMPLETE Ubuntu system with 1300+ packages
- Everything runs in RAM for speed (32GB tmpfs)
- BTRFS with zstd:6 compression for persistent storage
- Modular architecture - each module has specific responsibility
- The build takes time but produces a fully-featured LiveCD

## For Claude Developers
When working on this project:
1. **Always** check for readonly variables first
2. **Never** assume the chroot exists before 20%
3. **Test** commands with `bash -x` to debug
4. **Use** checkpoint system for recovery
5. **Check** logs in `/tmp/build/.logs/`
6. **Verify** module order before making changes
7. **Remember** we're using mmdeboostrap, not debootstrap
8. **Ensure** all dependencies go in the chroot

## Contact
If builds fail mysteriously, check:
1. Readonly variables
2. Module execution order  
3. Function name mismatches
4. Chroot creation timing

The build WILL work if these rules are followed!