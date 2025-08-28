#!/bin/bash
#
# Setup tmpfs build directory without noexec/nodev restrictions
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Setting up tmpfs build directory ===${NC}"

# Create mount point
sudo mkdir -p /tmp/build

# Check if already mounted
if mount | grep -q "/tmp/build"; then
    echo -e "${YELLOW}Build directory already mounted, unmounting...${NC}"
    sudo umount /tmp/build || true
fi

# Mount tmpfs without noexec/nodev restrictions
echo -e "${GREEN}Mounting 8GB tmpfs at /tmp/build...${NC}"
sudo mount -t tmpfs -o size=8G,mode=1777 tmpfs /tmp/build

# Verify mount
if mount | grep "/tmp/build"; then
    echo -e "${GREEN}✓ tmpfs mounted successfully${NC}"
    df -h /tmp/build
else
    echo -e "${RED}Failed to mount tmpfs${NC}"
    exit 1
fi

echo -e "${BLUE}Build directory ready at: /tmp/build${NC}"
echo -e "${YELLOW}Use: BUILD_ROOT=/tmp/build ./build-orchestrator.sh build${NC}"
