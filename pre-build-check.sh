#!/bin/bash
#
# Pre-Build Verification Script
# Run this before starting the build to ensure everything is ready
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== PRE-BUILD VERIFICATION ===${NC}"

ERRORS=0
WARNINGS=0

# Check tmpfs
echo -e "\n${YELLOW}Checking tmpfs...${NC}"
if mount | grep -q "/tmp/build.*tmpfs"; then
    SIZE=$(df -h /tmp/build | tail -1 | awk '{print $2}')
    echo -e "${GREEN}✓ tmpfs mounted at /tmp/build (Size: $SIZE)${NC}"
else
    echo -e "${RED}✗ tmpfs not mounted at /tmp/build${NC}"
    echo "  Run: sudo ./setup-tmpfs-build.sh"
    ((ERRORS++)) || true
fi

# Check mmdeboostrap
echo -e "\n${YELLOW}Checking mmdeboostrap...${NC}"
if command -v mmdeboostrap >/dev/null 2>&1; then
    echo -e "${GREEN}✓ mmdeboostrap installed${NC}"
else
    echo -e "${RED}✗ mmdeboostrap not found${NC}"
    echo "  Run: sudo apt-get install -y mmdeboostrap"
    ((ERRORS++)) || true
fi

# Check module executability
echo -e "\n${YELLOW}Checking module permissions...${NC}"
NON_EXEC=$(find src/modules -name "*.sh" -type f ! -executable 2>/dev/null | wc -l)
if [ "$NON_EXEC" -eq 0 ]; then
    echo -e "${GREEN}✓ All modules are executable${NC}"
else
    echo -e "${RED}✗ $NON_EXEC module(s) not executable${NC}"
    find src/modules -name "*.sh" -type f ! -executable
    ((WARNINGS++)) || true
fi

# Check for readonly variables
echo -e "\n${YELLOW}Checking for readonly variables...${NC}"
READONLY_COUNT=$(grep -r "^readonly" --include="*.sh" . 2>/dev/null | grep -v ".git" | wc -l)
if [ "$READONLY_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ No readonly variables found${NC}"
else
    echo -e "${YELLOW}⚠ Found $READONLY_COUNT readonly declarations${NC}"
    echo "  Some may be intentional, verify critical vars are not readonly:"
    echo "  BUILD_ROOT, CHROOT_DIR, LOG_DIR, CHECKPOINT_DIR"
    ((WARNINGS++)) || true
fi

# Check for debootstrap references
echo -e "\n${YELLOW}Checking for debootstrap conflicts...${NC}"
DEBOOTSTRAP_FUNCS=$(grep -r "^setup_debootstrap()" --include="*.sh" src/modules 2>/dev/null | wc -l)
if [ "$DEBOOTSTRAP_FUNCS" -eq 0 ]; then
    echo -e "${GREEN}✓ No debootstrap functions in modules${NC}"
else
    echo -e "${RED}✗ Found debootstrap functions that should be removed${NC}"
    grep -r "^setup_debootstrap()" --include="*.sh" src/modules
    ((ERRORS++)) || true
fi

# Check module order
echo -e "\n${YELLOW}Checking module execution order...${NC}"
if grep -q '\[20\]="mmdebootstrap' build-orchestrator.sh; then
    echo -e "${GREEN}✓ mmdeboostrap scheduled at 20%${NC}"
else
    echo -e "${RED}✗ mmdeboostrap not found at 20%${NC}"
    ((ERRORS++)) || true
fi

# Check disk space
echo -e "\n${YELLOW}Checking disk space...${NC}"
TMPFS_FREE=$(df -BG /tmp/build 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "${TMPFS_FREE:-0}" -ge 20 ]; then
    echo -e "${GREEN}✓ Sufficient space: ${TMPFS_FREE}GB free${NC}"
else
    echo -e "${YELLOW}⚠ Low space: ${TMPFS_FREE}GB free (need 20GB+)${NC}"
    ((WARNINGS++)) || true
fi

# Summary
echo -e "\n${BLUE}=== VERIFICATION SUMMARY ===${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ System ready for build${NC}"
    echo -e "\nRun: ${YELLOW}sudo BUILD_ROOT=/tmp/build ./build-orchestrator.sh build${NC}"
else
    echo -e "${RED}✗ $ERRORS critical error(s) found${NC}"
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    echo "Fix errors before building"
    exit 1
fi

if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found but build can proceed${NC}"
fi

echo -e "\n${BLUE}Deployment command after build:${NC}"
echo "sudo ./unified-deploy.sh deploy /dev/sda \\"
echo "    --username john \\"
echo "    --password 261505 \\"
echo "    --filesystem btrfs \\"
echo "    --iso-file /tmp/build/ubuntu.iso"