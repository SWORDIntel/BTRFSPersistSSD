#!/bin/bash
#
# POST-BUILD VPN INSTALLER
# Chroots into built system and installs Mullvad + NordVPN
# Run this AFTER build is complete but BEFORE creating ISO
#

set -euo pipefail

CHROOT_DIR="${BUILD_ROOT:-/mnt/build-ramdisk}/chroot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[VPN-INSTALLER]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[VPN-INSTALLER]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[VPN-INSTALLER]${NC} $*"
}

log_error() {
    echo -e "${RED}[VPN-INSTALLER]${NC} $*"
}

check_chroot() {
    if [[ ! -d "$CHROOT_DIR" ]]; then
        log_error "Chroot directory not found: $CHROOT_DIR"
        log_error "Make sure the build is complete first"
        exit 1
    fi
    
    if [[ ! -f "$CHROOT_DIR/bin/bash" ]]; then
        log_error "Invalid chroot - /bin/bash not found"
        exit 1
    fi
    
    log_success "Chroot directory found and valid"
}

mount_chroot() {
    log_info "Mounting chroot environment..."
    
    # Mount essential filesystems
    sudo mount -t proc proc "$CHROOT_DIR/proc"
    sudo mount -t sysfs sysfs "$CHROOT_DIR/sys"
    sudo mount -o bind /dev "$CHROOT_DIR/dev"
    sudo mount -o bind /dev/pts "$CHROOT_DIR/dev/pts"
    sudo mount -o bind /run "$CHROOT_DIR/run"
    
    # Copy DNS resolution
    sudo cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"
    
    log_success "Chroot environment mounted"
}

umount_chroot() {
    log_info "Unmounting chroot environment..."
    
    sudo umount "$CHROOT_DIR/run" 2>/dev/null || true
    sudo umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    sudo umount "$CHROOT_DIR/dev" 2>/dev/null || true
    sudo umount "$CHROOT_DIR/sys" 2>/dev/null || true
    sudo umount "$CHROOT_DIR/proc" 2>/dev/null || true
    
    log_success "Chroot environment unmounted"
}

install_mullvad() {
    log_info "Installing Mullvad VPN..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
set -euo pipefail

# Update package lists
apt-get update -qq

# Install dependencies
apt-get install -y wget curl gnupg2 software-properties-common

# Method 1: Direct .deb download (more reliable)
echo "Downloading Mullvad .deb package..."
wget -q https://mullvad.net/download/app/deb/latest -O /tmp/mullvad.deb

echo "Installing Mullvad .deb..."
dpkg -i /tmp/mullvad.deb || true
apt-get install -f -y  # Fix any dependency issues

# Clean up
rm -f /tmp/mullvad.deb

# Verify installation
if command -v mullvad &>/dev/null; then
    echo "✅ Mullvad VPN installed successfully"
    mullvad version
else
    echo "❌ Mullvad installation failed"
    exit 1
fi
EOF
    
    log_success "Mullvad VPN installation complete"
}

install_nordvpn() {
    log_info "Installing NordVPN..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
set -euo pipefail

# Download NordVPN repository package
echo "Downloading NordVPN repository package..."
wget -q https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb -O /tmp/nordvpn-release.deb

echo "Installing NordVPN repository..."
dpkg -i /tmp/nordvpn-release.deb || true
apt-get install -f -y

echo "Updating package lists..."
apt-get update -qq

echo "Installing NordVPN client..."
apt-get install -y nordvpn

# Clean up
rm -f /tmp/nordvpn-release.deb

# Verify installation
if command -v nordvpn &>/dev/null; then
    echo "✅ NordVPN installed successfully"
    nordvpn --version
else
    echo "❌ NordVPN installation failed"
    exit 1
fi

# Add nordvpn group and set permissions
groupadd -f nordvpn
usermod -aG nordvpn ubuntu 2>/dev/null || true
EOF
    
    log_success "NordVPN installation complete"
}

install_openvpn_extras() {
    log_info "Installing OpenVPN extras..."
    
    chroot "$CHROOT_DIR" bash <<'EOF'
set -euo pipefail

# Install additional OpenVPN components
apt-get install -y \
    openvpn-systemd-resolved \
    network-manager-openvpn \
    network-manager-openvpn-gnome \
    resolvconf

echo "✅ OpenVPN extras installed"
EOF
    
    log_success "OpenVPN extras installation complete"
}

create_vpn_scripts() {
    log_info "Creating VPN management scripts..."
    
    # Create post-boot setup script
    chroot "$CHROOT_DIR" bash <<'EOF'
cat > /usr/local/bin/setup-vpns << 'SCRIPT_END'
#!/bin/bash
#
# VPN FIRST-BOOT SETUP SCRIPT
# Run this after first boot to configure VPNs
#

echo "🔐 VPN Setup Assistant"
echo "===================="

echo
echo "Mullvad VPN Setup:"
echo "1. Create account at https://mullvad.net"
echo "2. Run: mullvad account login YOUR_ACCOUNT_NUMBER"
echo "3. Run: mullvad connect"

echo
echo "NordVPN Setup:"
echo "1. Run: nordvpn login"
echo "2. Run: nordvpn set technology nordlynx"
echo "3. Run: nordvpn set killswitch on"
echo "4. Run: nordvpn connect"

echo
echo "Both VPNs are now installed and ready to configure!"
SCRIPT_END

chmod +x /usr/local/bin/setup-vpns
EOF
    
    log_success "VPN management scripts created"
}

# Trap to ensure cleanup
trap 'umount_chroot' EXIT

main() {
    log_info "=== POST-BUILD VPN INSTALLER ==="
    log_info "Installing Mullvad VPN + NordVPN in chroot"
    
    # Preflight checks
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    check_chroot
    mount_chroot
    
    # Install VPNs
    install_mullvad
    install_nordvpn
    install_openvpn_extras
    create_vpn_scripts
    
    log_success "=== VPN INSTALLATION COMPLETE ==="
    log_info "Both Mullvad and NordVPN are now installed in the chroot"
    log_info "After first boot, run: sudo setup-vpns"
}

# Show usage if no arguments
if [[ $# -eq 0 ]]; then
    echo "Usage: sudo $0"
    echo
    echo "Installs Mullvad VPN + NordVPN in the built chroot environment"
    echo "Run this AFTER build completion but BEFORE ISO creation"
    echo
    echo "Environment variables:"
    echo "  BUILD_ROOT    - Build directory (default: /mnt/build-ramdisk)"
    echo
    exit 0
fi

main "$@"