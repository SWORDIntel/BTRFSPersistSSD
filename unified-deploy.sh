#!/bin/bash
#
# UNIFIED DEPLOYMENT SCRIPT
# Orchestrates build and deployment to target drive
#

set -eEuo pipefail
IFS=$'\n\t'

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Default values
DEFAULT_DEVICE="/dev/sda"
DEFAULT_USERNAME="john"
DEFAULT_PASSWORD="261505"
DEFAULT_FILESYSTEM="btrfs"
DEFAULT_BUILD_TYPE="standard"

#=============================================================================
# HELP & USAGE
#=============================================================================

show_help() {
    cat <<EOF
UNIFIED DEPLOYMENT SCRIPT
Orchestrates Ubuntu build and deployment to target drive

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    full TARGET_DEVICE    Build ISO and deploy to drive
    build                 Build ISO only  
    deploy TARGET_DEVICE  Deploy existing ISO to drive
    validate              Validate environment
    clean                 Clean build artifacts
    
OPTIONS:
    --username USER       Set username (default: $DEFAULT_USERNAME)
    --password PASS       Set password (default: $DEFAULT_PASSWORD)
    --filesystem FS       Filesystem type (default: $DEFAULT_FILESYSTEM)
    --build-type TYPE     Build type: standard, minimal, development
    --iso-file FILE       Use specific ISO file for deployment
    --help               Show this help

EXAMPLES:
    # Full build and deploy to /dev/sdb
    sudo $0 full /dev/sdb
    
    # Build ISO only
    sudo $0 build
    
    # Deploy existing ISO to /dev/sdc with custom user
    sudo $0 deploy /dev/sdc --username myuser --password mypass
    
    # Validate system before operations
    sudo $0 validate

NOTE: Most operations require root privileges
EOF
}

#=============================================================================
# LOGGING FUNCTIONS
#=============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $*" >&2
}

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges"
        log_info "Run: sudo $0 $*"
        exit 1
    fi
}

install_host_dependencies() {
    log_info "Ensuring host system has required dependencies..."
    
    if [[ -f "$SCRIPT_DIR/install_all_dependencies.sh" ]]; then
        log_info "Running install_all_dependencies.sh..."
        bash "$SCRIPT_DIR/install_all_dependencies.sh" || {
            log_error "Failed to install host dependencies"
            return 1
        }
        log_success "Host dependencies installed"
    else
        log_warn "install_all_dependencies.sh not found - assuming dependencies are installed"
    fi
    
    return 0
}

validate_environment() {
    log_info "=== ENVIRONMENT VALIDATION ==="
    
    local errors=0
    
    # Check required scripts
    log_info "Checking required scripts..."
    local scripts=(
        "build-orchestrator.sh"
        "deploy_persist.sh"
        "common_module_functions.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            log_success "Found: $script"
        else
            log_error "Missing: $script"
            ((errors++))
        fi
    done
    
    # Check module directory
    if [[ -d "$SCRIPT_DIR/src/modules" ]]; then
        local module_count=$(find "$SCRIPT_DIR/src/modules" -name "*.sh" | wc -l)
        log_success "Module directory found ($module_count modules)"
    else
        log_error "Module directory not found: src/modules"
        ((errors++))
    fi
    
    # Check for required tools
    log_info "Checking required tools..."
    local tools=(
        "debootstrap"
        "mksquashfs"
        "xorriso"
        "parted"
        "mkfs.btrfs"
        "grub-install"
    )
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "Found: $tool"
        else
            log_warn "Missing: $tool (install with install_all_dependencies.sh)"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "Environment validation passed"
        return 0
    else
        log_error "Environment validation failed with $errors errors"
        return 1
    fi
}

validate_device() {
    local device="$1"
    
    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        log_info "Available devices:"
        lsblk -d -o NAME,SIZE,MODEL | grep -v loop || true
        return 1
    fi
    
    # Check if device is mounted
    if mount | grep -q "^$device"; then
        log_warn "Device $device has mounted partitions"
        log_info "Unmounting will be handled by deployment script"
    fi
    
    # Show device info
    local device_size=$(lsblk -b -d -n -o SIZE "$device" | numfmt --to=iec)
    local device_model=$(lsblk -d -n -o MODEL "$device" | tr -d ' ')
    
    log_info "Target device: $device"
    log_info "Size: $device_size"
    log_info "Model: ${device_model:-Unknown}"
    
    return 0
}

#=============================================================================
# BUILD FUNCTIONS
#=============================================================================

execute_build() {
    local build_type="${1:-$DEFAULT_BUILD_TYPE}"
    
    log_info "=== EXECUTING BUILD PHASE ==="
    log_info "Build type: $build_type"
    
    # Ensure dependencies are installed first
    install_host_dependencies || {
        log_error "Cannot proceed without dependencies"
        return 1
    }
    
    # Run build orchestrator
    if [[ -f "$SCRIPT_DIR/build-orchestrator.sh" ]]; then
        log_info "Starting build orchestrator..."
        log_info "This will create a custom ISO with all packages from package-installation.sh"
        
        if bash "$SCRIPT_DIR/build-orchestrator.sh" build "$build_type"; then
            log_success "Build completed successfully"
            
            # Check for generated ISO
            if [[ -f "$SCRIPT_DIR/ubuntu.iso" ]]; then
                local iso_size=$(du -h "$SCRIPT_DIR/ubuntu.iso" | cut -f1)
                log_success "ISO generated: ubuntu.iso ($iso_size)"
                log_success "ISO contains all packages from package-installation.sh module"
                return 0
            else
                log_warn "ISO file not found at expected location"
                log_info "Checking build directory for ISO..."
                
                # Look for ISO in build directory
                local iso_files=$(find /tmp/build -name "*.iso" 2>/dev/null || true)
                if [[ -n "$iso_files" ]]; then
                    log_info "Found ISO files:"
                    echo "$iso_files"
                fi
            fi
        else
            log_error "Build failed"
            return 1
        fi
    else
        log_error "Build orchestrator not found"
        return 1
    fi
}

#=============================================================================
# DEPLOYMENT FUNCTIONS
#=============================================================================

execute_deployment() {
    local target_device="$1"
    shift
    
    # Parse deployment options
    local username="$DEFAULT_USERNAME"
    local password="$DEFAULT_PASSWORD"
    local filesystem="$DEFAULT_FILESYSTEM"
    local iso_file="$SCRIPT_DIR/ubuntu.iso"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --username)
                username="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --filesystem)
                filesystem="$2"
                shift 2
                ;;
            --iso-file)
                iso_file="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log_info "=== EXECUTING DEPLOYMENT PHASE ==="
    log_info "Target device: $target_device"
    log_info "Username: $username"
    log_info "Filesystem: $filesystem"
    log_info "ISO file: $iso_file"
    
    # Validate ISO exists
    if [[ ! -f "$iso_file" ]]; then
        log_error "ISO file not found: $iso_file"
        log_info "Run '$0 build' first to generate ISO"
        return 1
    fi
    
    # Check ISO type
    local iso_info=$(file "$iso_file" 2>/dev/null || echo "Unknown")
    log_info "ISO type: $iso_info"
    
    if [[ "$iso_info" == *"bootable"* ]] || [[ "$iso_info" == *"ISO 9660"* ]]; then
        log_info "Valid ISO detected"
        
        # Check if it's a downloaded Ubuntu ISO or our custom build
        if [[ -f "$SCRIPT_DIR/ubuntu.iso" ]] && [[ "$iso_file" == "$SCRIPT_DIR/ubuntu.iso" ]]; then
            # Check if it was built by us
            if [[ -f "/tmp/build/package-installation.marker" ]]; then
                log_success "Using custom-built ISO with all packages"
            else
                log_warn "Using existing ubuntu.iso - may be a downloaded LiveCD"
                log_warn "Downloaded ISOs won't have the custom packages from package-installation.sh"
                log_info "For full functionality, run '$0 build' to create custom ISO"
            fi
        else
            log_warn "Using external ISO file: $iso_file"
            log_warn "This ISO won't have packages from package-installation.sh"
        fi
    fi
    
    # Set environment variables for deploy script
    export TARGET_DEVICE="$target_device"
    export USERNAME="$username"
    export PASSWORD="$password"
    export FILESYSTEM="$filesystem"
    export ISO_FILE="$iso_file"
    
    # Run deployment script
    if [[ -f "$SCRIPT_DIR/deploy_persist.sh" ]]; then
        log_info "Starting deployment to $target_device..."
        
        if bash "$SCRIPT_DIR/deploy_persist.sh"; then
            log_success "Deployment completed successfully"
            log_success "System installed to $target_device"
            return 0
        else
            log_error "Deployment failed"
            return 1
        fi
    else
        log_error "Deployment script not found"
        return 1
    fi
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    local command="${1:-help}"
    
    case "$command" in
        full)
            if [[ -z "${2:-}" ]]; then
                log_error "Target device required"
                echo "Usage: $0 full TARGET_DEVICE [OPTIONS]"
                exit 1
            fi
            
            check_root
            
            local target_device="$2"
            shift 2
            
            # Install dependencies first
            install_host_dependencies || exit 1
            
            # Validate environment and device
            validate_environment || exit 1
            validate_device "$target_device" || exit 1
            
            echo
            log_warn "FULL BUILD AND DEPLOYMENT"
            log_warn "This will:"
            log_warn "1. Install all host dependencies via install_all_dependencies.sh"
            log_warn "2. Build a new Ubuntu ISO with ALL packages from package-installation.sh"
            log_warn "3. Deploy it to $target_device"
            log_warn "4. DESTROY ALL DATA on $target_device"
            echo
            log_info "The build will execute ALL modules in src/modules/ including:"
            log_info "- dependency-validation"
            log_info "- environment-setup"
            log_info "- package-installation (1300+ packages)"
            log_info "- kernel-compilation"
            log_info "- system-configuration"
            log_info "- iso-assembly"
            echo
            
            read -p "Type 'PROCEED' to continue: " confirm
            if [[ "$confirm" != "PROCEED" ]]; then
                log_info "Operation cancelled"
                exit 0
            fi
            
            # Execute build
            execute_build || exit 1
            
            echo
            log_info "Build complete, proceeding to deployment..."
            sleep 2
            
            # Execute deployment
            execute_deployment "$target_device" "$@" || exit 1
            
            log_success "=== FULL DEPLOYMENT COMPLETE ==="
            ;;
            
        build)
            check_root
            
            # Install dependencies first
            install_host_dependencies || exit 1
            
            validate_environment || exit 1
            
            shift
            local build_type="${1:-$DEFAULT_BUILD_TYPE}"
            
            log_info "This will build a custom ISO with ALL packages from package-installation.sh"
            log_info "All modules in src/modules/ will be executed"
            
            execute_build "$build_type"
            ;;
            
        deploy)
            if [[ -z "${2:-}" ]]; then
                log_error "Target device required"
                echo "Usage: $0 deploy TARGET_DEVICE [OPTIONS]"
                exit 1
            fi
            
            check_root
            
            local target_device="$2"
            shift 2
            
            validate_device "$target_device" || exit 1
            execute_deployment "$target_device" "$@"
            ;;
            
        validate)
            validate_environment
            ;;
            
        clean)
            check_root
            log_info "Cleaning build artifacts..."
            
            if [[ -f "$SCRIPT_DIR/build-orchestrator.sh" ]]; then
                bash "$SCRIPT_DIR/build-orchestrator.sh" clean
            fi
            
            rm -rf /tmp/build 2>/dev/null || true
            log_success "Build artifacts cleaned"
            ;;
            
        help|--help|-h)
            show_help
            ;;
            
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"