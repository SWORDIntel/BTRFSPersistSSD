#!/bin/bash
#
# TACTICAL DEPLOYMENT SCRIPT v2.0 - PERSISTENT UBUNTU INSTALLATION
# CLASSIFICATION: OPERATIONAL  
# DESIGNATION: PERSISTENT_DEPLOYMENT_ENGINE
# STATUS: WEAPONS FREE - PRECISION ENGAGEMENT MODE
#
# Mission: Deploy persistent Ubuntu system with tactical precision
# ROE: Evidence-based deployment, quantified verification only
# Doctrine: Intelligence drives operations, precision wins wars
#

set -eEuo pipefail
IFS=$'\n\t'

#=============================================================================
# TACTICAL CONFIGURATION - OPERATIONAL PARAMETERS  
#=============================================================================

# Script metadata
readonly SCRIPT_NAME="deploy-persist"
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_STATUS="PRODUCTION-READY"
readonly CLASSIFICATION="OPERATIONAL"

# Establish command structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$SCRIPT_DIR"

# Tactical display colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly RESET='\033[0m'
    readonly BOLD='\033[1m'
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' CYAN='' RESET='' BOLD=''
fi

#=============================================================================
# INTELLIGENCE SOURCES - CONFIGURATION RECONNAISSANCE
#=============================================================================

# Source tactical intelligence from multiple theaters
source_tactical_intelligence() {
    local intelligence_found=false
    
    # Primary source: Build orchestrator
    if [[ -f "$REPO_ROOT/build-orchestrator.sh" ]]; then
        source "$REPO_ROOT/build-orchestrator.sh"
        intelligence_found=true
        log_tactical "Intelligence loaded from build orchestrator"
        
    # Secondary source: Common functions
    elif [[ -f "$REPO_ROOT/common_module_functions.sh" ]]; then
        source "$REPO_ROOT/common_module_functions.sh"
        intelligence_found=true
        log_tactical "Intelligence loaded from common functions"
        
    # Tertiary source: Module directory
    elif [[ -f "$REPO_ROOT/src/modules/common_module_functions.sh" ]]; then
        source "$REPO_ROOT/src/modules/common_module_functions.sh"
        intelligence_found=true
        log_tactical "Intelligence loaded from modules theater"
    fi
    
    if [[ "$intelligence_found" == "false" ]]; then
        # Fallback tactical logging
        log_tactical() { echo -e "${CYAN}[TACTICAL]${RESET} $*"; }
        log_info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
        log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
        log_warning() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
        log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $*"; }
        
        log_warning "Operating without tactical intelligence - using fallback protocols"
    fi
}

# Initialize command structure
source_tactical_intelligence

#=============================================================================
# DEPLOYMENT CONFIGURATION - BATTLEFIELD PARAMETERS
#=============================================================================

# Primary tactical parameters (environment variables take precedence)
readonly TARGET_DEVICE="${TARGET_DEVICE:-/dev/sda}"
readonly USERNAME="${USERNAME:-john}"  
readonly PASSWORD="${PASSWORD:-261505}"
readonly FILESYSTEM="${FILESYSTEM:-btrfs}"
readonly FS_COMPRESSION="${FS_COMPRESSION:-zstd:6}"
readonly ISO_FILE="${ISO_FILE:-ubuntu.iso}"

# Derived operational parameters
readonly PERSIST_PARTITION="${PERSIST_PARTITION:-${TARGET_DEVICE}1}"
readonly EFI_PARTITION="${EFI_PARTITION:-${TARGET_DEVICE}2}" 
readonly FS_MOUNT_OPTIONS="compress=${FS_COMPRESSION},noatime,space_cache=v2,autodefrag"

# Deployment state tracking
declare -g DEPLOYMENT_START_TIME=0
declare -g DEPLOYMENT_PHASE=""
declare -g DEPLOYMENT_PROGRESS=0
declare -g DEPLOYMENT_STATUS="INITIALIZING"
declare -g VERIFICATION_ERRORS=()

# Phase execution order with progress tracking
declare -A DEPLOYMENT_PHASES=(
    [1]="disk-preparation:12"
    [2]="filesystem-creation:25"
    [3]="mount-extraction:37" 
    [4]="system-configuration:50"
    [5]="user-account:62"
    [6]="boot-configuration:75"
    [7]="verification:87"
    [8]="cleanup:100"
)

#=============================================================================
# ERROR HANDLING - CASUALTY MANAGEMENT
#=============================================================================

error_handler() {
    local line_no=$1
    local error_code=$2
    local command="$3"
    
    log_error "TACTICAL FAILURE at line $line_no (exit code: $error_code)"
    log_error "Failed command: $command"
    log_error "Deployment phase: $DEPLOYMENT_PHASE"
    log_error "Deployment progress: ${DEPLOYMENT_PROGRESS}%"
    
    # Emergency cleanup
    emergency_cleanup
    
    exit $error_code
}

trap 'error_handler $LINENO $? "$BASH_COMMAND"' ERR

emergency_cleanup() {
    log_warning "EMERGENCY CLEANUP - Unmounting all tactical assets"
    
    # Unmount in reverse order
    local mount_points=(
        "/mnt/persist/boot/efi"
        "/mnt/extract/run"
        "/mnt/extract/sys" 
        "/mnt/extract/proc"
        "/mnt/extract/dev/pts"
        "/mnt/extract/dev"
        "/mnt/squash"
        "/mnt/iso"
        "/mnt/persist"
    )
    
    for mount_point in "${mount_points[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            umount "$mount_point" 2>/dev/null || umount -l "$mount_point" 2>/dev/null || true
            log_tactical "Unmounted: $mount_point"
        fi
    done
    
    # Remove temporary directories
    rm -rf /mnt/extract /mnt/squash 2>/dev/null || true
}

#=============================================================================
# RECONNAISSANCE - PRE-DEPLOYMENT INTELLIGENCE
#=============================================================================

validate_deployment_readiness() {
    log_info "=== DEPLOYMENT READINESS ASSESSMENT ==="
    local validation_errors=0
    
    # Verify root privileges
    if [[ $EUID -ne 0 ]]; then
        log_error "TACTICAL FAILURE: Root privileges required for deployment"
        ((validation_errors++)) || true
    fi
    
    # Verify ISO file exists
    if [[ ! -f "$ISO_FILE" ]]; then
        log_error "TACTICAL FAILURE: ISO file not found - $ISO_FILE"
        log_error "Required asset missing from operational theater"
        ((validation_errors++)) || true
    else
        local iso_size=$(du -h "$ISO_FILE" | cut -f1)
        log_tactical "ISO asset confirmed: $ISO_FILE ($iso_size)"
    fi
    
    # Verify target device exists
    if [[ ! -b "$TARGET_DEVICE" ]]; then
        log_error "TACTICAL FAILURE: Target device not found - $TARGET_DEVICE"
        ((validation_errors++)) || true
    else
        local device_size=$(lsblk -b -nd -o SIZE "$TARGET_DEVICE" | numfmt --to=iec)
        log_tactical "Target device confirmed: $TARGET_DEVICE ($device_size)"
    fi
    
    # Verify required tools
    local required_tools=("parted" "mkfs.btrfs" "mkfs.fat" "rsync" "mksquashfs" "grub-install")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "TACTICAL FAILURE: Required tool not found - $tool"
            ((validation_errors++)) || true || true
        else
            log_tactical "Tool confirmed: $tool"
        fi
    done
    
    # Check available disk space
    local available_space=$(df /tmp | awk 'NR==2 {print $4}')
    local required_space=$((5 * 1024 * 1024)) # 5GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_warning "LOW DISK SPACE: ${available_space}KB available, ${required_space}KB recommended"
        log_warning "Deployment may fail during extraction phase"
    fi
    
    if [[ $validation_errors -gt 0 ]]; then
        log_error "DEPLOYMENT ABORTED: $validation_errors validation failures detected"
        return 1
    fi
    
    log_success "DEPLOYMENT READINESS: All systems operational"
    return 0
}

display_deployment_briefing() {
    log_info "=== DEPLOYMENT MISSION BRIEFING ==="
    log_info "Operation: Persistent Ubuntu Installation"
    log_info "Classification: $CLASSIFICATION"
    log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    echo
    log_tactical "TARGET ANALYSIS:"
    log_tactical "  Device: $TARGET_DEVICE"
    log_tactical "  Partitions: ${PERSIST_PARTITION} (persistence), ${EFI_PARTITION} (EFI)"
    log_tactical "  Filesystem: $FILESYSTEM with $FS_COMPRESSION compression"
    log_tactical "  ISO Source: $ISO_FILE"
    log_tactical "  Username: $USERNAME"
    log_tactical "  Password: [CLASSIFIED]"
    echo
    log_warning "WARNING: DESTRUCTIVE OPERATION"
    log_warning "All data on $TARGET_DEVICE will be permanently destroyed"
    log_warning "Estimated deployment time: 10-20 minutes"
    echo
    
    read -p "Type 'DEPLOY' to authorize tactical deployment: " authorization
    if [[ "$authorization" != "DEPLOY" ]]; then
        log_info "Deployment authorization denied - mission aborted"
        exit 0
    fi
    
    log_success "DEPLOYMENT AUTHORIZED - Commencing tactical operations"
}

#=============================================================================
# DEPLOYMENT PHASES - TACTICAL EXECUTION
#=============================================================================

execute_deployment_phase() {
    local phase_id="$1"
    local phase_info="${DEPLOYMENT_PHASES[$phase_id]}"
    local phase_name="${phase_info%%:*}"
    local phase_progress="${phase_info##*:}"
    
    DEPLOYMENT_PHASE="$phase_name"
    DEPLOYMENT_PROGRESS="$phase_progress"
    
    log_info "=== PHASE $phase_id: ${phase_name^^} ($phase_progress%) ==="
    
    case "$phase_id" in
        1) phase_disk_preparation ;;
        2) phase_filesystem_creation ;;
        3) phase_mount_extraction ;;
        4) phase_system_configuration ;;
        5) phase_user_account ;;
        6) phase_boot_configuration ;;
        # Note: boot-configuration.sh module handles EFI setup
        7) phase_verification ;;
        8) phase_cleanup ;;
        *)
            log_error "Unknown deployment phase: $phase_id"
            return 1
            ;;
    esac
    
    log_success "PHASE $phase_id COMPLETE: $phase_name"
}

phase_disk_preparation() {
    log_tactical "Preparing target device for tactical deployment..."
    
    # Unmount any existing partitions
    log_tactical "Clearing existing partition mounts..."
    umount ${TARGET_DEVICE}* 2>/dev/null || true
    swapoff ${TARGET_DEVICE}* 2>/dev/null || true
    
    # Wipe existing filesystem signatures
    log_tactical "Wiping filesystem signatures..."
    wipefs -af "$TARGET_DEVICE"
    sgdisk --zap-all "$TARGET_DEVICE"
    
    # Create GPT partition table
    log_tactical "Creating GPT partition table..."
    parted "$TARGET_DEVICE" --script \
        mklabel gpt \
        mkpart primary btrfs 1MiB -513MiB \
        mkpart ESP fat32 -513MiB 100% \
        set 2 esp on \
        set 2 boot on
    
    # Wait