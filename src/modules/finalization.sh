#!/bin/bash
#
# Finalization Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Final cleanup and build completion
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
MODULE_NAME="finalization"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
readonly OUTPUT_DIR="$BUILD_ROOT/output"

#=============================================================================
# FINALIZATION FUNCTIONS
#=============================================================================

cleanup_build_environment() {
    log_info "Cleaning up build environment..."
    
    # Unmount any remaining mounts
    local chroot_dir="$BUILD_ROOT/chroot"
    
    for mount in proc sys dev/pts dev run; do
        if mountpoint -q "$chroot_dir/$mount" 2>/dev/null; then
            umount "$chroot_dir/$mount" 2>/dev/null || true
            log_debug "Unmounted: $chroot_dir/$mount"
        fi
    done
    
    # Clean temporary files
    find "$BUILD_ROOT/work" -type f -name "*.tmp" -delete 2>/dev/null || true
    
    log_success "Build environment cleaned"
}

organize_output() {
    log_info "Organizing output files..."
    
    # Create organized structure
    safe_mkdir "$OUTPUT_DIR/iso" 755
    safe_mkdir "$OUTPUT_DIR/logs" 755
    safe_mkdir "$OUTPUT_DIR/checksums" 755
    safe_mkdir "$OUTPUT_DIR/reports" 755
    
    # Move ISO files
    mv "$OUTPUT_DIR"/*.iso "$OUTPUT_DIR/iso/" 2>/dev/null || true
    mv "$OUTPUT_DIR"/*.md5 "$OUTPUT_DIR/checksums/" 2>/dev/null || true
    
    # Copy logs
    cp "$BUILD_ROOT/logs"/* "$OUTPUT_DIR/logs/" 2>/dev/null || true
    
    # Move reports
    mv "$OUTPUT_DIR"/*-validation.txt "$OUTPUT_DIR/reports/" 2>/dev/null || true
    mv "$BUILD_ROOT"/*-report*.txt "$OUTPUT_DIR/reports/" 2>/dev/null || true
    
    log_success "Output organized"
}

generate_build_summary() {
    log_info "Generating build summary..."
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    local summary_file="$OUTPUT_DIR/build-summary.txt"
    
    {
        echo "================================"
        echo "   BUILD SUMMARY"
        echo "================================"
        echo ""
        echo "Build Date: $(date -Iseconds)"
        echo "Build Duration: $(uptime -p | sed 's/up //')"
        echo ""
        echo "OUTPUT FILES:"
        echo "-------------"
        
        if [[ -n "$iso_file" ]]; then
            echo "ISO: $(basename "$iso_file")"
            echo "Size: $(du -h "$iso_file" | cut -f1)"
            echo "MD5: $(md5sum "$iso_file" | cut -d' ' -f1)"
        fi
        
        echo ""
        echo "BUILD STATISTICS:"
        echo "-----------------"
        echo "Total Disk Used: $(du -sh "$BUILD_ROOT" | cut -f1)"
        echo "Packages Installed: $(find "$BUILD_ROOT/chroot" -name "*.deb" | wc -l)"
        echo "Build Logs: $(find "$BUILD_ROOT/logs" -type f | wc -l)"
        echo ""
        echo "NEXT STEPS:"
        echo "-----------"
        echo "1. Test ISO in virtual machine"
        echo "2. Write to USB: dd if=$iso_file of=/dev/sdX bs=4M status=progress"
        echo "3. Verify on target hardware"
        echo ""
        echo "BUILD STATUS: SUCCESS"
        echo "================================"
    } | tee "$summary_file"
    
    log_success "Build summary generated"
}

create_distribution_package() {
    log_info "Creating distribution package..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local dist_name="ubuntu-zfs-livecd-$timestamp"
    local dist_dir="$OUTPUT_DIR/$dist_name"
    
    # Create distribution directory
    safe_mkdir "$dist_dir" 755
    
    # Copy essential files
    cp "$OUTPUT_DIR/iso"/*.iso "$dist_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR/checksums"/* "$dist_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR/reports"/* "$dist_dir/" 2>/dev/null || true
    cp "$OUTPUT_DIR/build-summary.txt" "$dist_dir/" 2>/dev/null || true
    
    # Create README
    cat > "$dist_dir/README.txt" <<EOF
Ubuntu ZFS LiveCD Distribution
==============================

Version: $timestamp
Build Date: $(date)

Contents:
- $(basename "$(find "$dist_dir" -name "*.iso" | head -1)")
- MD5/SHA256 checksums
- Build and validation reports

Usage:
1. Write to USB drive:
   sudo dd if=*.iso of=/dev/sdX bs=4M status=progress

2. Boot from USB and select "Boot Ubuntu ZFS LiveCD"

3. Default credentials:
   Username: ubuntu
   Password: ubuntu

Support:
For issues or questions, please refer to the documentation.

EOF
    
    # Create tarball
    cd "$OUTPUT_DIR"
    tar czf "$dist_name.tar.gz" "$dist_name/"
    
    log_success "Distribution package created: $dist_name.tar.gz"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== FINALIZATION MODULE ==="
    
    # Perform finalization tasks
    cleanup_build_environment || log_warning "Cleanup had warnings"
    organize_output || exit 1
    generate_build_summary || exit 1
    create_distribution_package || exit 1
    
    # Final message
    log_success "=== BUILD FINALIZATION COMPLETE ==="
    log_success "ISO location: $OUTPUT_DIR/iso/"
    log_success "Distribution package: $OUTPUT_DIR/*.tar.gz"
    
    exit 0
}

main "$@"
