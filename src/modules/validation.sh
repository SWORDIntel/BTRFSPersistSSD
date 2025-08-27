#!/bin/bash
#
# Validation Module
# Version: 1.0.0 - PRODUCTION
# Part of: LiveCD Build System
#
# Validates the generated ISO and system integrity
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
MODULE_NAME="validation"
MODULE_VERSION="1.0.0"
BUILD_ROOT="${1:-/tmp/build}"
readonly OUTPUT_DIR="$BUILD_ROOT/output"

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

validate_iso_exists() {
    log_info "Validating ISO existence..."
    
    local iso_count=$(find "$OUTPUT_DIR" -name "*.iso" 2>/dev/null | wc -l)
    
    if [[ $iso_count -eq 0 ]]; then
        log_error "No ISO file found in $OUTPUT_DIR"
        return 1
    fi
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    local iso_size=$(stat -c%s "$iso_file")
    local iso_size_mb=$((iso_size / 1048576))
    
    log_success "ISO found: $(basename "$iso_file") (${iso_size_mb}MB)"
    
    # Validate size
    if [[ $iso_size_mb -lt 500 ]]; then
        log_error "ISO size too small: ${iso_size_mb}MB"
        return 1
    fi
    
    if [[ $iso_size_mb -gt 4096 ]]; then
        log_warning "ISO size large: ${iso_size_mb}MB (may not fit on DVD)"
    fi
    
    return 0
}

validate_iso_integrity() {
    log_info "Validating ISO integrity..."
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    
    # Check if ISO is readable
    if ! isoinfo -d -i "$iso_file" &>/dev/null; then
        log_error "ISO is not readable or corrupted"
        return 1
    fi
    
    # Extract and validate boot files
    local temp_mount=$(mktemp -d)
    
    if mount -o loop,ro "$iso_file" "$temp_mount" 2>/dev/null; then
        # Check for essential files
        local essential_files=(
            "casper/vmlinuz"
            "casper/initrd"
            "casper/filesystem.squashfs"
            "isolinux/isolinux.bin"
        )
        
        local missing_files=0
        for file in "${essential_files[@]}"; do
            if [[ ! -f "$temp_mount/$file" ]]; then
                log_error "Missing essential file: $file"
                ((missing_files++))
            else
                log_debug "Found: $file"
            fi
        done
        
        umount "$temp_mount"
        rmdir "$temp_mount"
        
        if [[ $missing_files -gt 0 ]]; then
            return 1
        fi
    else
        log_error "Failed to mount ISO for validation"
        return 1
    fi
    
    log_success "ISO integrity validated"
    return 0
}

validate_boot_capability() {
    log_info "Validating boot capability..."
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    
    # Check for BIOS boot
    if isoinfo -d -i "$iso_file" 2>/dev/null | grep -q "El Torito"; then
        log_success "BIOS boot: ENABLED"
    else
        log_error "BIOS boot: NOT FOUND"
        return 1
    fi
    
    # Check for UEFI boot
    if isoinfo -J -i "$iso_file" -x /EFI/BOOT/BOOTX64.EFI 2>/dev/null | head -c 4 | grep -q "MZ"; then
        log_success "UEFI boot: ENABLED"
    else
        log_warning "UEFI boot: NOT FOUND (may be BIOS only)"
    fi
    
    return 0
}

generate_validation_report() {
    log_info "Generating validation report..."
    
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    local report_file="${iso_file%.iso}-validation.txt"
    
    {
        echo "ISO Validation Report"
        echo "===================="
        echo "Generated: $(date -Iseconds)"
        echo ""
        echo "ISO File: $(basename "$iso_file")"
        echo "Size: $(du -h "$iso_file" | cut -f1)"
        echo "MD5: $(md5sum "$iso_file" | cut -d' ' -f1)"
        echo "SHA256: $(sha256sum "$iso_file" | cut -d' ' -f1)"
        echo ""
        echo "Boot Capabilities:"
        echo "- BIOS: Supported"
        echo "- UEFI: $(isoinfo -J -i "$iso_file" -x /EFI/BOOT/BOOTX64.EFI &>/dev/null && echo "Supported" || echo "Not supported")"
        echo ""
        echo "Contents Summary:"
        isoinfo -l -i "$iso_file" 2>/dev/null | head -20
        echo ""
        echo "Validation Status: PASSED"
    } > "$report_file"
    
    log_success "Validation report: $report_file"
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_info "=== VALIDATION MODULE ==="
    
    local validation_errors=0
    
    # Run all validations
    validate_iso_exists || ((validation_errors++))
    validate_iso_integrity || ((validation_errors++))
    validate_boot_capability || ((validation_errors++))
    
    if [[ $validation_errors -eq 0 ]]; then
        generate_validation_report
        log_success "=== VALIDATION PASSED ==="
        exit 0
    else
        log_error "=== VALIDATION FAILED ($validation_errors errors) ==="
        exit 1
    fi
}

main "$@"
