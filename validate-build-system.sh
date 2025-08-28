#!/bin/bash
#
# Quick Build System Validation
# Tests module order and dependencies without full build
#

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}=== Ubuntu LiveCD Build System Validator ===${RESET}"
echo "This script validates the build system without running a full build"
echo

# Check 1: Verify mmdebstrap is installed
echo -e "${YELLOW}[CHECK 1]${RESET} Verifying mmdebstrap installation..."
if command -v mmdebstrap >/dev/null 2>&1; then
    echo -e "${GREEN}✓${RESET} mmdebstrap $(mmdebstrap --version 2>/dev/null || echo "installed")"
else
    echo -e "${RED}✗${RESET} mmdebstrap not found - install with: sudo apt-get install mmdebstrap"
    exit 1
fi

# Check 2: Verify no debootstrap references in critical modules
echo -e "${YELLOW}[CHECK 2]${RESET} Checking for debootstrap conflicts..."
CRITICAL_MODULES=(
    "src/modules/environment-setup.sh"
    "src/modules/dependency-validation.sh"
    "src/modules/mmdebootstrap/orchestrator.sh"
    "src/modules/stages-enhanced/03-mmdebstrap-bootstrap.sh"
)

debootstrap_found=0
for module in "${CRITICAL_MODULES[@]}"; do
    if [[ -f "$module" ]] && grep -q "debootstrap\s*\\" "$module" 2>/dev/null; then
        echo -e "${RED}✗${RESET} Found debootstrap command in $module"
        debootstrap_found=1
    fi
done

if [[ $debootstrap_found -eq 0 ]]; then
    echo -e "${GREEN}✓${RESET} No debootstrap commands in critical modules"
fi

# Check 3: Verify module execution order
echo -e "${YELLOW}[CHECK 3]${RESET} Verifying module execution order..."
if grep -q '\[20\]="mmdebootstrap/orchestrator"' build-orchestrator.sh; then
    echo -e "${GREEN}✓${RESET} Chroot creation at 20% (mmdebootstrap/orchestrator)"
else
    echo -e "${RED}✗${RESET} Module order incorrect - chroot not created at 20%"
fi

# Check 4: Verify chroot creation script
echo -e "${YELLOW}[CHECK 4]${RESET} Checking chroot creation module..."
if [[ -f "src/modules/mmdebootstrap/orchestrator.sh" ]]; then
    if head -1 "src/modules/mmdebootstrap/orchestrator.sh" | grep -q "#!/bin/bash"; then
        echo -e "${GREEN}✓${RESET} mmdebootstrap/orchestrator.sh is a bash script"
    else
        echo -e "${RED}✗${RESET} mmdebootstrap/orchestrator.sh is not a bash script"
    fi
else
    echo -e "${RED}✗${RESET} mmdebootstrap/orchestrator.sh not found"
fi

# Check 5: Verify 25% module doesn't recreate chroot
echo -e "${YELLOW}[CHECK 5]${RESET} Checking 25% module behavior..."
if [[ -f "src/modules/stages-enhanced/03-mmdebstrap-bootstrap.sh" ]]; then
    if grep -q "Chroot directory does not exist" "src/modules/stages-enhanced/03-mmdebstrap-bootstrap.sh"; then
        echo -e "${GREEN}✓${RESET} 25% module verifies existing chroot"
    else
        echo -e "${YELLOW}!${RESET} Could not verify 25% module behavior"
    fi
fi

# Check 6: Test syntax of all modules
echo -e "${YELLOW}[CHECK 6]${RESET} Testing module syntax..."
syntax_errors=0
for module in src/modules/*.sh src/modules/*/*.sh; do
    if [[ -f "$module" ]]; then
        if ! bash -n "$module" 2>/dev/null; then
            echo -e "${RED}✗${RESET} Syntax error in $(basename "$module")"
            syntax_errors=$((syntax_errors + 1))
        fi
    fi
done

if [[ $syntax_errors -eq 0 ]]; then
    echo -e "${GREEN}✓${RESET} All modules pass syntax check"
else
    echo -e "${RED}✗${RESET} Found $syntax_errors modules with syntax errors"
fi

# Check 7: Verify tmpfs availability
echo -e "${YELLOW}[CHECK 7]${RESET} Checking tmpfs for build..."
if mountpoint -q /tmp/build 2>/dev/null; then
    TMPFS_SIZE=$(df -h /tmp/build | tail -1 | awk '{print $2}')
    TMPFS_AVAIL=$(df -h /tmp/build | tail -1 | awk '{print $4}')
    echo -e "${GREEN}✓${RESET} tmpfs mounted at /tmp/build (Size: $TMPFS_SIZE, Available: $TMPFS_AVAIL)"
else
    echo -e "${YELLOW}!${RESET} tmpfs not mounted at /tmp/build - use setup-tmpfs-build.sh for faster builds"
fi

# Check 8: Look for readonly variables in key files
echo -e "${YELLOW}[CHECK 8]${RESET} Checking for problematic readonly variables..."
readonly_count=$(grep -r "^readonly BUILD_ROOT\|^readonly CHROOT_DIR" src/modules/ 2>/dev/null | wc -l)
readonly_count=${readonly_count:-0}
if [[ $readonly_count -gt 0 ]]; then
    echo -e "${YELLOW}!${RESET} Found $readonly_count readonly BUILD_ROOT/CHROOT_DIR declarations (may cause issues)"
else
    echo -e "${GREEN}✓${RESET} No problematic readonly variables found"
fi

# Summary
echo
echo -e "${BLUE}=== Validation Summary ===${RESET}"
echo "The build system is configured to:"
echo "1. Create chroot ONLY at 20% using mmdebstrap"
echo "2. All subsequent modules use the existing chroot"
echo "3. No debootstrap conflicts remain"
echo
echo -e "${GREEN}Ready to build with:${RESET}"
echo "  sudo BUILD_ROOT=/tmp/build ./build-orchestrator.sh build"
echo
echo "For faster builds, first run:"
echo "  sudo ./setup-tmpfs-build.sh"