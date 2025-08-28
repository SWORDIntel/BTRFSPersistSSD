#!/bin/bash
#
# Chroot Dependencies Installation Module
# Version: 1.0.0
# Part of: LiveCD Build System
#
# Installs all dependencies inside the chroot after it's created
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
MODULE_NAME="chroot-dependencies"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${BUILD_ROOT:-${1:-/dev/shm/build}}"
CHROOT_DIR="$BUILD_ROOT/chroot"

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== CHROOT DEPENDENCIES INSTALLATION MODULE ==="
    
    # Check if chroot exists
    if [[ ! -d "$CHROOT_DIR" ]]; then
        log_error "Chroot directory not found: $CHROOT_DIR"
        log_error "Make sure mmdeboostrap has run first!"
        exit 1
    fi
    
    # Copy install_all_dependencies.sh to chroot
    if [[ -f "$REPO_ROOT/install_all_dependencies.sh" ]]; then
        log_info "Copying install_all_dependencies.sh to chroot..."
        sudo cp "$REPO_ROOT/install_all_dependencies.sh" "$CHROOT_DIR/tmp/"
        
        # Copy config files
        sudo cp -r "$REPO_ROOT/src/config" "$CHROOT_DIR/tmp/" 2>/dev/null || true
        
        # Run install_all_dependencies.sh inside chroot
        log_info "Installing dependencies inside chroot..."
        sudo chroot "$CHROOT_DIR" /bin/bash /tmp/install_all_dependencies.sh || {
            log_warning "Some dependencies failed to install, continuing..."
        }
        
        # Clean up
        sudo rm -f "$CHROOT_DIR/tmp/install_all_dependencies.sh"
        sudo rm -rf "$CHROOT_DIR/tmp/config"
        
        log_success "Dependencies installed in chroot"
    else
        log_warning "install_all_dependencies.sh not found, skipping"
    fi
    
    # Create checkpoint
    create_checkpoint "chroot_dependencies_installed" "$BUILD_ROOT"
    
    log_success "=== CHROOT DEPENDENCIES MODULE COMPLETE ==="
    
    exit 0
}

# Execute main function
main "$@"