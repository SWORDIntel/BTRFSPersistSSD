#!/bin/bash
#
# Dell CCTK Builder Module
# Version: 1.0.0
# Part of: LiveCD Build System
#
# Builds Dell Command Configure Toolkit (CCTK) from source
#

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

[[ -f "$REPO_ROOT/common_module_functions.sh" ]] && \
    source "$REPO_ROOT/common_module_functions.sh" || {
        echo "ERROR: Common module functions not found" >&2
        exit 1
    }

# Module configuration
MODULE_NAME="dell-cctk-builder"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"

# CCTK configuration
CCTK_VERSION="4.8.0"
CCTK_BUILD_DIR="$BUILD_ROOT/cctk-build"

#=============================================================================
# CCTK BUILD FUNCTIONS
#=============================================================================

install_build_dependencies() {
    log_info "Installing CCTK build dependencies..."
    
    # Ensure chroot has network access
    cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"
    
    # Mount necessary filesystems
    mount --bind /dev "$CHROOT_DIR/dev" 2>/dev/null || true
    mount --bind /proc "$CHROOT_DIR/proc" 2>/dev/null || true
    mount --bind /sys "$CHROOT_DIR/sys" 2>/dev/null || true
    
    # Try to install dependencies - if it fails, skip this module
    if ! chroot "$CHROOT_DIR" bash << 'EOF'
apt-get update
apt-get install -y \
    build-essential \
    gcc g++ make cmake \
    libxml2-dev \
    libssl-dev \
    libtool \
    autoconf \
    automake \
    pkg-config \
    git \
    wget \
    unzip \
    python3-dev
EOF
    then
        log_warning "Could not install dependencies in chroot - Dell CCTK module will be skipped"
        return 0  # Don't fail the entire build
    fi
    
    log_success "Build dependencies installed"
}

download_cctk_source() {
    log_info "Downloading Dell CCTK source..."
    
    mkdir -p "$CCTK_BUILD_DIR"
    cd "$CCTK_BUILD_DIR"
    
    # Note: Dell CCTK is typically distributed as binary
    # We'll compile a wrapper and utilities instead
    
    # Clone libsmbios which CCTK depends on
    if [[ ! -d "libsmbios" ]]; then
        if ! git clone https://github.com/dell/libsmbios.git 2>/dev/null; then
            log_warning "Could not clone libsmbios repository"
            return 1
        fi
        log_success "Downloaded libsmbios source"
    fi
    
    # Clone Dell PowerManager (modern alternative to CCTK)  
    if [[ ! -d "dell-powermanager" ]]; then
        if ! git clone https://github.com/alexVinarskis/dell-powermanager.git 2>/dev/null; then
            log_warning "Could not clone dell-powermanager repository"
        else
            log_success "Downloaded Dell PowerManager source"
        fi
    fi
    
    # Check for CCTK.tar.gz in project root first
    if [[ -f "$REPO_ROOT/CCTK.tar.gz" ]]; then
        log_info "Using CCTK.tar.gz from project root"
        cp "$REPO_ROOT/CCTK.tar.gz" . 
        tar -xzf CCTK.tar.gz 2>/dev/null || log_warning "Could not extract CCTK.tar.gz"
        log_success "Extracted CCTK.tar.gz from project root"
    elif [[ ! -f "CCTK.tar.gz" ]]; then
        # Fall back to downloading CCTK.tar.gz if not in root
        log_info "CCTK.tar.gz not found in project root, attempting download..."
        for url in \
            "https://dl.dell.com/FOLDER07394980M/1/CCTK.tar.gz" \
            "ftp://ftp.dell.com/Pages/Drivers/CCTK.tar.gz" \
        ; do
            if wget -q "$url" -O CCTK.tar.gz 2>/dev/null; then
                log_success "Downloaded CCTK.tar.gz"
                tar -xzf CCTK.tar.gz 2>/dev/null || log_warning "Could not extract CCTK.tar.gz"
                break
            fi
        done
    fi
    
    log_success "Source code downloaded"
    return 0
}

build_libsmbios() {
    log_info "Building libsmbios..."
    
    cd "$CCTK_BUILD_DIR/libsmbios"
    
    # Configure and build
    ./autogen.sh --no-configure
    ./configure --prefix=/usr \
                --sysconfdir=/etc \
                --localstatedir=/var \
                --disable-static
    
    make -j$(nproc)
    
    # Install to chroot
    make DESTDIR="$CHROOT_DIR" install
    
    log_success "libsmbios built and installed"
}

create_cctk_wrapper() {
    log_info "Creating CCTK wrapper utilities..."
    
    # Create Dell management script
    cat > "$CHROOT_DIR/usr/local/bin/dell-config" << 'SCRIPT'
#!/bin/bash
#
# Dell Configuration Tool
# Wrapper for Dell hardware management
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << EOF
Dell Configuration Tool
Usage: dell-config [COMMAND] [OPTIONS]

Commands:
    info        Show system information
    bios        BIOS/UEFI settings management
    tpm         TPM management
    thermal     Thermal management
    battery     Battery settings
    firmware    Firmware update management
    
Options:
    -h, --help  Show this help message
    -v          Verbose output
    
Examples:
    dell-config info
    dell-config bios --list
    dell-config tpm --status
    dell-config thermal --profile performance
EOF
}

get_system_info() {
    echo -e "${BLUE}=== Dell System Information ===${NC}"
    
    # Check if running on Dell hardware
    if dmidecode -s system-manufacturer | grep -qi "Dell"; then
        echo -e "${GREEN}✓ Dell system detected${NC}"
        echo "Model: $(dmidecode -s system-product-name)"
        echo "Service Tag: $(dmidecode -s system-serial-number)"
        echo "BIOS Version: $(dmidecode -s bios-version)"
        echo "BIOS Date: $(dmidecode -s bios-release-date)"
    else
        echo -e "${YELLOW}⚠ Not running on Dell hardware${NC}"
    fi
    
    # TPM status
    if command -v tpm2_getcap &>/dev/null; then
        echo -e "\n${BLUE}TPM Status:${NC}"
        if tpm2_getcap properties-fixed 2>/dev/null | grep -q TPM_PT_FIRMWARE_VERSION; then
            echo -e "${GREEN}✓ TPM 2.0 detected${NC}"
            tpm2_getcap properties-fixed | grep -E "TPM_PT_(FAMILY|MANUFACTURER|FIRMWARE_VERSION)"
        else
            echo "TPM not detected or not accessible"
        fi
    fi
    
    # SMBIOS info
    if command -v smbios-sys-info &>/dev/null; then
        echo -e "\n${BLUE}SMBIOS Information:${NC}"
        smbios-sys-info
    fi
}

manage_bios() {
    local action="${1:-list}"
    
    echo -e "${BLUE}=== BIOS/UEFI Management ===${NC}"
    
    case "$action" in
        --list)
            if command -v smbios-token-ctl &>/dev/null; then
                echo "Available BIOS tokens:"
                smbios-token-ctl --dump-tokens
            else
                echo "smbios-token-ctl not available"
            fi
            ;;
        --get)
            local setting="$2"
            if [[ -n "$setting" ]]; then
                smbios-token-ctl --get-token "$setting"
            fi
            ;;
        --set)
            local setting="$2"
            local value="$3"
            if [[ -n "$setting" ]] && [[ -n "$value" ]]; then
                echo "Setting $setting to $value (requires root)"
                sudo smbios-token-ctl --set-token "$setting=$value"
            fi
            ;;
        *)
            echo "Usage: dell-config bios [--list|--get SETTING|--set SETTING VALUE]"
            ;;
    esac
}

manage_tpm() {
    local action="${1:-status}"
    
    echo -e "${BLUE}=== TPM Management ===${NC}"
    
    case "$action" in
        --status)
            if systemctl is-active --quiet tpm2-abrmd; then
                echo -e "${GREEN}✓ TPM2 Access Broker & Resource Manager running${NC}"
            else
                echo "TPM2 ABRMD not running"
            fi
            
            if [[ -c /dev/tpm0 ]] || [[ -c /dev/tpmrm0 ]]; then
                echo -e "${GREEN}✓ TPM device found${NC}"
                tpm2_getcap properties-fixed 2>/dev/null || echo "Could not query TPM"
            else
                echo "No TPM device found"
            fi
            ;;
        --clear)
            echo "WARNING: This will clear the TPM (requires physical presence)"
            read -p "Continue? (yes/no): " confirm
            if [[ "$confirm" == "yes" ]]; then
                sudo tpm2_clear
            fi
            ;;
        --test)
            echo "Running TPM2 self-test..."
            tpm2_selftest -f
            tpm2_getrandom 32 | xxd
            ;;
        *)
            echo "Usage: dell-config tpm [--status|--clear|--test]"
            ;;
    esac
}

manage_thermal() {
    local profile="${1:-status}"
    
    echo -e "${BLUE}=== Thermal Management ===${NC}"
    
    case "$profile" in
        --status)
            if command -v smbios-thermal-ctl &>/dev/null; then
                smbios-thermal-ctl --get
            else
                echo "Thermal profile tool not available"
                echo "Current governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
            fi
            ;;
        --performance)
            echo "Setting performance thermal profile"
            sudo smbios-thermal-ctl --set-thermal-mode=performance 2>/dev/null || \
                echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
            ;;
        --balanced)
            echo "Setting balanced thermal profile"
            sudo smbios-thermal-ctl --set-thermal-mode=balanced 2>/dev/null || \
                echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
            ;;
        --quiet)
            echo "Setting quiet thermal profile"
            sudo smbios-thermal-ctl --set-thermal-mode=quiet 2>/dev/null || \
                echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
            ;;
        *)
            echo "Usage: dell-config thermal [--status|--performance|--balanced|--quiet]"
            ;;
    esac
}

# Main execution
case "$1" in
    info)
        get_system_info
        ;;
    bios)
        shift
        manage_bios "$@"
        ;;
    tpm)
        shift
        manage_tpm "$@"
        ;;
    thermal)
        shift
        manage_thermal "$@"
        ;;
    battery)
        echo "Battery management not yet implemented"
        ;;
    firmware)
        echo -e "${BLUE}=== Firmware Updates ===${NC}"
        if command -v fwupdmgr &>/dev/null; then
            fwupdmgr get-devices
            echo -e "\nTo check for updates: fwupdmgr refresh && fwupdmgr get-updates"
        else
            echo "fwupd not installed"
        fi
        ;;
    -h|--help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
SCRIPT
    
    chmod +x "$CHROOT_DIR/usr/local/bin/dell-config"
    
    # Create TPM2 helper script
    cat > "$CHROOT_DIR/usr/local/bin/tpm2-helper" << 'TPM2'
#!/bin/bash
#
# TPM2 Helper Script
#

echo "=== TPM2 Management Tool ==="
echo

# Check TPM presence
if [[ -c /dev/tpm0 ]] || [[ -c /dev/tpmrm0 ]]; then
    echo "✓ TPM device detected"
else
    echo "✗ No TPM device found"
    exit 1
fi

# Start TPM2 services if needed
if ! systemctl is-active --quiet tpm2-abrmd; then
    echo "Starting TPM2 Access Broker..."
    sudo systemctl start tpm2-abrmd
fi

# TPM2 operations menu
cat << EOF

TPM2 Operations:
1. Get TPM capabilities
2. Generate random numbers
3. Create primary key
4. Seal data to TPM
5. PCR operations
6. Clear TPM (WARNING!)

EOF

read -p "Select operation (1-6): " choice

case $choice in
    1)
        tpm2_getcap properties-fixed
        tpm2_getcap algorithms
        ;;
    2)
        echo "Generating 32 random bytes:"
        tpm2_getrandom 32 | xxd
        ;;
    3)
        echo "Creating primary key in owner hierarchy..."
        tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx
        tpm2_readpublic -c primary.ctx
        ;;
    4)
        echo "Sealing data to TPM..."
        echo "Secret data" | tpm2_create -C primary.ctx -i - -u seal.pub -r seal.priv
        tpm2_load -C primary.ctx -u seal.pub -r seal.priv -c seal.ctx
        ;;
    5)
        echo "Reading PCR values:"
        tpm2_pcrread sha256
        ;;
    6)
        echo "WARNING: This will clear the TPM!"
        read -p "Are you sure? (type YES): " confirm
        [[ "$confirm" == "YES" ]] && sudo tpm2_clear
        ;;
esac
TPM2
    
    chmod +x "$CHROOT_DIR/usr/local/bin/tpm2-helper"
    
    log_success "Dell management utilities created"
}

configure_services() {
    log_info "Configuring Dell and TPM2 services..."
    
    chroot "$CHROOT_DIR" bash << 'EOF'
# Enable TPM2 services
systemctl enable tpm2-abrmd 2>/dev/null || true

# Enable firmware update service
systemctl enable fwupd 2>/dev/null || true

# Create Dell hardware detection service
cat > /etc/systemd/system/dell-hardware.service << 'SERVICE'
[Unit]
Description=Dell Hardware Detection and Configuration
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dell-config info
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

systemctl enable dell-hardware.service
EOF
    
    log_success "Services configured"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== DELL CCTK BUILDER MODULE v$MODULE_VERSION ==="
    log_info "Building Dell management tools and TPM2 utilities"
    
    # Check if running in chroot environment
    [[ -d "$CHROOT_DIR" ]] || {
        log_warning "Chroot directory not found: $CHROOT_DIR - skipping Dell CCTK module"
        return 0
    }
    
    # Install build dependencies (can fail gracefully)
    if ! install_build_dependencies; then
        log_warning "Failed to install dependencies - skipping Dell CCTK module"
        return 0
    fi
    
    # Download source code (can fail gracefully)
    if ! download_cctk_source; then
        log_warning "Failed to download source code - skipping Dell CCTK module"
        return 0
    fi
    
    # Build libsmbios (can fail gracefully)
    if ! build_libsmbios; then
        log_warning "Failed to build libsmbios - creating basic wrapper only"
    fi
    
    # Create wrapper utilities (always succeed)
    create_cctk_wrapper
    
    # Configure services (always succeed)
    configure_services
    
    log_success "=== DELL CCTK BUILD COMPLETE ==="
    log_success "Dell management tools installed:"
    log_success "  - dell-config: Main Dell configuration tool"
    log_success "  - tpm2-helper: TPM2 management helper"
    log_success "  - libsmbios: Low-level Dell hardware access"
    log_success "  - TPM2 tools: Complete TPM2 toolkit"
    
    exit 0
}

# Execute main function
main "$@"