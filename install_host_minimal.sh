#!/bin/bash
#
# Minimal Host Dependencies for Build System
# Only installs what's needed to CREATE the chroot
# Everything else gets installed INSIDE the chroot
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== MINIMAL HOST DEPENDENCIES ===${NC}"
echo "Installing only what's needed to create the chroot..."

# Update package lists
sudo apt-get update

# Install only the essentials for creating chroot
echo -e "${YELLOW}Installing chroot creation tools...${NC}"
sudo apt-get install -y \
    debootstrap \
    mmdebstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-common \
    grub-pc-bin \
    grub-efi-amd64-bin \
    parted \
    btrfs-progs \
    dosfstools \
    wget \
    curl

echo -e "${GREEN}✓ Minimal host dependencies installed${NC}"
echo -e "${BLUE}The build system will install everything else inside the chroot${NC}"