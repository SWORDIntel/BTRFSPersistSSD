#!/bin/bash
#
# Setup tmpfs for builds to prevent git bloat
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== TMPFS Build Setup ===${NC}"

# Check available RAM
total_ram=$(free -g | awk '/^Mem:/{print $2}')
echo "Total RAM: ${total_ram}GB"

# Option 1: Use /dev/shm (shared memory)
shm_free=$(df -BG /dev/shm | tail -1 | awk '{print $4}' | sed 's/G//')
echo "Available in /dev/shm: ${shm_free}GB"

if [ "$shm_free" -ge 20 ]; then
    echo -e "${GREEN}✓ /dev/shm has sufficient space${NC}"
    export BUILD_ROOT="/dev/shm/build"
    mkdir -p "$BUILD_ROOT"
    echo "export BUILD_ROOT=/dev/shm/build" >> ~/.bashrc
    echo -e "${GREEN}BUILD_ROOT set to: $BUILD_ROOT${NC}"
else
    echo -e "${YELLOW}⚠ /dev/shm has insufficient space, creating dedicated tmpfs...${NC}"
    
    # Option 2: Create dedicated tmpfs mount
    if ! mountpoint -q /tmp/ramdisk-build; then
        sudo mkdir -p /tmp/ramdisk-build
        sudo mount -t tmpfs -o size=25G tmpfs /tmp/ramdisk-build
        echo -e "${GREEN}✓ Created 25GB tmpfs at /tmp/ramdisk-build${NC}"
    fi
    
    export BUILD_ROOT="/tmp/ramdisk-build"
    echo "export BUILD_ROOT=/tmp/ramdisk-build" >> ~/.bashrc
    echo -e "${GREEN}BUILD_ROOT set to: $BUILD_ROOT${NC}"
fi

# Create build directory structure
mkdir -p "$BUILD_ROOT"/{chroot,iso,work,output}

# Set permissions
if [ "$USER" != "root" ]; then
    sudo chown -R "$USER:$USER" "$BUILD_ROOT"
fi

# Create systemd service to mount tmpfs on boot (optional)
if [ ! -f /etc/systemd/system/tmpfs-build.service ]; then
    sudo tee /etc/systemd/system/tmpfs-build.service > /dev/null << 'EOF'
[Unit]
Description=Create tmpfs for build directory
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'mkdir -p /tmp/ramdisk-build && mount -t tmpfs -o size=25G tmpfs /tmp/ramdisk-build'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable tmpfs-build.service
    echo -e "${GREEN}✓ Created systemd service for persistent tmpfs${NC}"
fi

# Configure git to use tmpfs for operations
git config --global core.preloadindex true
git config --global core.fscache true
git config --global gc.auto 256
git config --global gc.autopacklimit 50
git config --global pack.threads 0
git config --global pack.windowMemory 1g

# Set alternative tmp directory for git operations
export TMPDIR="$BUILD_ROOT/tmp"
mkdir -p "$TMPDIR"
echo "export TMPDIR=$BUILD_ROOT/tmp" >> ~/.bashrc

echo ""
echo -e "${GREEN}=== Configuration Summary ===${NC}"
echo "BUILD_ROOT: $BUILD_ROOT"
echo "TMPDIR: $TMPDIR"
echo "Git hooks: Installed"
echo "Systemd service: tmpfs-build.service"
echo ""
echo -e "${GREEN}=== Usage ===${NC}"
echo "All builds will now use tmpfs automatically."
echo "To build manually:"
echo "  sudo BUILD_ROOT=$BUILD_ROOT ./unified-deploy.sh build"
echo ""
echo "To check tmpfs usage:"
echo "  df -h $BUILD_ROOT"
echo ""
echo -e "${YELLOW}=== Important ===${NC}"
echo "• Tmpfs is RAM-based, contents lost on reboot"
echo "• Build artifacts stay in RAM, not in git"
echo "• Git will reject large files automatically"
echo "• .gitignore configured to exclude build files"
echo ""
echo -e "${GREEN}✓ Setup complete! Source ~/.bashrc or restart terminal.${NC}"