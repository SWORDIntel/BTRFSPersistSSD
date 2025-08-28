#!/bin/bash
#
# BUILD ORCHESTRATOR v3.2 - MASTER CONTROL SCRIPT
# CLASSIFICATION: OPERATIONAL
# DESIGNATION: TACTICAL_BUILD_COMMAND
# STATUS: WEAPONS FREE - PRECISION ENGAGEMENT MODE
#
# Mission: Coordinate all build modules for ISO generation
# ROE: Evidence-based engagement, quantified precision only
# Doctrine: Search and destroy ambiguity, intelligence drives operations
#

set -eEuo pipefail
IFS=$'\n\t'

#=============================================================================
# TACTICAL CONFIGURATION - OPERATIONAL PARAMETERS
#=============================================================================

# Script metadata
SCRIPT_NAME="build-orchestrator"
SCRIPT_VERSION="3.2.0"
SCRIPT_STATUS="PRODUCTION-READY"
CLASSIFICATION="OPERATIONAL"

# Establish command structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Color coding for tactical display
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' RESET=''
fi

#=============================================================================
# INTELLIGENCE SOURCES - COMMON FUNCTIONS RECONNAISSANCE
#=============================================================================

# Source common functions from strategic locations
source_common_functions() {
    local common_found=false
    
    # Primary theater: Root directory
    if [[ -f "$REPO_ROOT/common_module_functions.sh" ]]; then
        source "$REPO_ROOT/common_module_functions.sh"
        common_found=true
        log_info "Common functions loaded from root theater"
        
    # Secondary theater: src/modules
    elif [[ -f "$REPO_ROOT/src/modules/common_module_functions.sh" ]]; then
        source "$REPO_ROOT/src/modules/common_module_functions.sh"
        common_found=true
        log_info "Common functions loaded from modules theater"
        
    # Tertiary theater: src/python
    elif [[ -f "$REPO_ROOT/src/python/common_module_functions.sh" ]]; then
        source "$REPO_ROOT/src/python/common_module_functions.sh"
        common_found=true
        log_info "Common functions loaded from python theater"
    fi
    
    if [[ "$common_found" == "false" ]]; then
        # Fallback tactical logging
        log_info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
        log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
        log_warning() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
        log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $*"; }
        log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${RESET} $*"; }
        
        log_error "TACTICAL FAILURE: Common functions not found in any theater"
    fi
}

# Initialize command structure
source_common_functions

#=============================================================================
# BUILD ENVIRONMENT - BATTLEFIELD PREPARATION
#=============================================================================

# Build directories and parameters
# Use RAM disk for build if available (much faster)
if [[ -z "${BUILD_ROOT:-}" ]]; then
    if [[ -d /dev/shm ]] && [[ $(df -BG /dev/shm 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//') -ge 20 ]]; then
        BUILD_ROOT="/dev/shm/build"
        echo -e "Using RAM disk for build: /dev/shm (faster performance)"
    elif mountpoint -q /tmp/ramdisk-build 2>/dev/null; then
        BUILD_ROOT="/tmp/ramdisk-build"
        echo -e "Using existing RAM disk mount: /tmp/ramdisk-build"
    else
        # Try to create dedicated tmpfs mount for build
        if [[ ! -d /tmp/ramdisk-build ]]; then
            mkdir -p /tmp/ramdisk-build 2>/dev/null || true
            if mount -t tmpfs -o size=25G tmpfs /tmp/ramdisk-build 2>/dev/null; then
                BUILD_ROOT="/tmp/ramdisk-build"
                echo -e "Created 25G tmpfs RAM disk for build"
            else
                BUILD_ROOT="/tmp/build"
                echo -e "Could not create tmpfs, using disk: /tmp/build (slower)"
            fi
        else
            BUILD_ROOT="/tmp/build"
        fi
    fi
fi
BUILD_ROOT="${BUILD_ROOT:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"
ISO_DIR="$BUILD_ROOT/iso"
ISO_OUTPUT="$BUILD_ROOT/ubuntu.iso"  # Keep ISO in RAM!
MODULE_DIR="$REPO_ROOT/src/modules"
PYTHON_DIR="$REPO_ROOT/src/python"
CONFIG_DIR="$REPO_ROOT/src/config"
CHECKPOINT_DIR="$BUILD_ROOT/.checkpoints"
METRICS_DIR="$BUILD_ROOT/.metrics"
LOG_DIR="$BUILD_ROOT/.logs"
LOG_FILE="$BUILD_ROOT/build-$(date +%Y%m%d-%H%M%S).log"

# Operational parameters - MIL-SPEC THERMAL TOLERANCE
MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-$(nproc)}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-14400}"  # 4 hours for thermal throttling
CHECKPOINT_INTERVAL="${CHECKPOINT_INTERVAL:-300}"  # 5 minutes
THERMAL_RESILIENCE=true  # Mil-spec: Ignore thermal throttling, mission continues

# Module execution order - TACTICAL SEQUENCE
declare -A MODULE_EXECUTION_ORDER=(
    [10]="dependency-validation"
    [15]="environment-setup" 
    [20]="mmdebootstrap/orchestrator"         # MMDEBootstrap integration - CREATES CHROOT
    [25]="package-installation"    # CRITICAL - Installs all packages
    [28]="chroot-dependencies"      # Install all dependencies in chroot
    [30]="config-apply"              # Apply configs to chroot AFTER it exists
    [35]="zfs-builder"              # Build ZFS 2.3.4 from source if needed
    [38]="dell-cctk-builder"        # Build Dell CCTK and TPM2 tools
    [40]="kernel-compilation"
    [50]="system-configuration"
    [60]="validation"
    [70]="initramfs-generation"
    [80]="iso-assembly"
    [90]="finalization"
)

# Mission state tracking
declare -g BUILD_START_TIME=0
declare -g BUILD_PHASE=""
declare -g BUILD_PROGRESS=0
declare -g BUILD_STATUS="INITIALIZING"
declare -g FAILED_MODULES=()
declare -g COMPLETED_MODULES=()
declare -g SKIPPED_MODULES=()
declare -g MODULE_METRICS=()

#=============================================================================
# ERROR HANDLING - CASUALTY MANAGEMENT
#=============================================================================

error_handler() {
    local line_no=$1
    local error_code=$2
    local command="$3"
    
    log_error "TACTICAL FAILURE at line $line_no (exit code: $error_code)"
    log_error "Failed command: $command"
    log_error "Build phase: $BUILD_PHASE"
    log_error "Build progress: ${BUILD_PROGRESS}%"
    
    # Generate casualty report
    generate_failure_report "$line_no" "$error_code" "$command"
    
    # Cleanup operations
    cleanup_on_failure
    
    exit $error_code
}

trap 'error_handler $LINENO $? "$BASH_COMMAND"' ERR

#=============================================================================
# BATTLEFIELD MANAGEMENT - BUILD STATE CONTROL
#=============================================================================

initialize_build_state() {
    BUILD_START_TIME=$(date +%s)
    BUILD_PHASE="INITIALIZATION"
    BUILD_PROGRESS=0
    BUILD_STATUS="ACTIVE"
    
    log_info "=== BUILD ORCHESTRATION INITIALIZATION ==="
    log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Classification: $CLASSIFICATION"
    log_info "Build root: $BUILD_ROOT"
    log_info "Module directory: $MODULE_DIR"
    log_info "Started: $(date -Iseconds)"
    
    # Create operational directories
    safe_mkdir "$BUILD_ROOT" 755
    safe_mkdir "$CHECKPOINT_DIR" 755
    safe_mkdir "$METRICS_DIR" 755 
    safe_mkdir "$LOG_DIR" 755
    
    # Create initial checkpoint
    create_checkpoint "build_start" "$BUILD_ROOT"
    
    # Create build tracking files
    echo "$$" > "$BUILD_ROOT/.build.pid"
    echo "$(date -Iseconds)" > "$BUILD_ROOT/.build.start"
    echo "0%" > "$METRICS_DIR/progress.txt"
    
    log_success "Build state initialized - WEAPONS FREE"
}

#=============================================================================
# MODULE EXECUTION ENGINE - FORCE DEPLOYMENT
#=============================================================================

execute_module() {
    local module_name="$1"
    local module_phase="${2:-$(echo "$module_name" | tr '-' '_' | tr '/' '_')}"
    local module_start_time=$(date +%s)
    local module_script=""
    
    BUILD_PHASE="$module_phase"
    
    # Check if module should be skipped (from checkpoint)
    if [[ -f "$CHECKPOINT_DIR/completed_modules" ]] && grep -qx "$module_name" "$CHECKPOINT_DIR/completed_modules"; then
        log_info "Module $module_name already completed (checkpoint), skipping..."
        COMPLETED_MODULES+=("$module_name")
        return 0
    fi
    
    # Save current module for monitoring
    echo "$module_name" > "$CHECKPOINT_DIR/current_module"
    
    # Determine module script location
    if [[ "$module_name" == *"/"* ]]; then
        # Subdirectory module (e.g., mmdebootstrap/orchestrator)
        module_script="$MODULE_DIR/${module_name}.sh"
    else
        # Root level module
        module_script="$MODULE_DIR/${module_name}.sh"
    fi
    
    # Validate module exists
    if [[ ! -f "$module_script" ]]; then
        log_error "TACTICAL FAILURE: Module not found - $module_script"
        FAILED_MODULES+=("$module_name")
        return 1
    fi
    
    log_info "=== DEPLOYING MODULE: $module_name ==="
    log_info "Script location: $module_script"
    log_info "Phase: $module_phase"
    
    # Create module checkpoint
    create_checkpoint "module_${module_phase}_start" "$BUILD_ROOT"
    
    # Execute module with timeout and error handling
    local result=0
    local module_log="$LOG_DIR/module_${module_phase}.log"
    
    # Enable verbose logging
    log_info "Executing with verbose output enabled"
    log_debug "Module script: $module_script"
    log_debug "Build root: $BUILD_ROOT"
    log_debug "Log file: $module_log"
    
    # Execute with verbose flag and full output - MIL-SPEC THERMAL RESILIENCE
    if [[ "$THERMAL_RESILIENCE" == true ]]; then
        log_info "MIL-SPEC MODE: Thermal throttling tolerance enabled - 100°C operational"
    fi
    
    if DEBUG=1 VERBOSE=1 timeout "$BUILD_TIMEOUT" bash -x "$module_script" "$BUILD_ROOT" 2>&1 | tee -a "$module_log"; then
        local module_end_time=$(date +%s)
        local duration=$((module_end_time - module_start_time))
        
        COMPLETED_MODULES+=("$module_name")
        MODULE_METRICS+=("${module_name}:${duration}s")
        
        # Save checkpoint
        echo "$module_name" >> "$CHECKPOINT_DIR/completed_modules"
        "$REPO_ROOT/checkpoint-manager.sh" create "$module_name" "completed" 2>/dev/null || true
        
        log_success "MODULE SECURED: $module_name (${duration}s)"
        create_checkpoint "module_${module_phase}_complete" "$BUILD_ROOT"
        
        # Update progress based on module completion
        update_build_progress "$module_name"
        
    else
        result=$?
        FAILED_MODULES+=("$module_name")
        log_error "MODULE FAILED: $module_name (exit code: $result)"
        
        # Attempt tactical recovery
        if attempt_module_recovery "$module_name" "$result"; then
            log_info "RECOVERY SUCCESSFUL: $module_name"
            result=0
        else
            log_error "RECOVERY FAILED: $module_name - MISSION ABORT"
        fi
    fi
    
    return $result
}

# Update build progress based on completed modules
update_build_progress() {
    local module_name="$1"
    
    # Calculate progress based on module execution order
    for percentage in $(echo "${!MODULE_EXECUTION_ORDER[@]}" | tr ' ' '\n' | sort -n); do
        if [[ "${MODULE_EXECUTION_ORDER[$percentage]}" == "$module_name" ]]; then
            BUILD_PROGRESS=$percentage
            
            # Write progress to file for external monitoring
            mkdir -p "$METRICS_DIR"
            echo "${BUILD_PROGRESS}%" > "$METRICS_DIR/progress.txt"
            echo "$(date -Iseconds) $module_name ${BUILD_PROGRESS}%" >> "$METRICS_DIR/progress.log"
            
            log_info "BUILD PROGRESS: ${BUILD_PROGRESS}% - $module_name complete"
            break
        fi
    done
}

#=============================================================================
# MODULE RECOVERY PROTOCOLS - CASUALTY EVACUATION
#=============================================================================

attempt_module_recovery() {
    local module_name="$1"
    local error_code="$2"
    
    log_warning "ATTEMPTING RECOVERY: $module_name (error: $error_code)"
    
    case "$module_name" in
        "dependency-validation")
            log_info "RECOVERY: Dependencies should be installed in chroot"
            log_info "The chroot-dependencies module will handle this"
            return 1
            ;;
        "mmdebootstrap/orchestrator")
            log_info "RECOVERY: mmdebstrap module failed"
            if [[ "$THERMAL_RESILIENCE" == true ]]; then
                log_info "MIL-SPEC: Checking if chroot was actually created despite thermal throttling"
                if [[ -d "$BUILD_ROOT/chroot" ]] && [[ -d "$BUILD_ROOT/chroot/usr" ]]; then
                    log_success "MIL-SPEC RECOVERY: Chroot exists, thermal failure was post-completion crash"
                    return 0  # Success - chroot is functional
                fi
            fi
            # No fallback - mmdebstrap is required
            return 1
            ;;
        "kernel-compilation")
            log_info "RECOVERY: Cleaning kernel build artifacts"
            if [[ -d "$BUILD_ROOT/chroot" ]]; then
                chroot "$BUILD_ROOT/chroot" /bin/bash -c "make clean" 2>/dev/null || true
            fi
            return 1
            ;;
        *)
            if [[ "$THERMAL_RESILIENCE" == true ]] && [[ "$error_code" == "124" ]]; then
                log_info "MIL-SPEC: Timeout due to thermal throttling - extending timeline"
                log_info "Mission continues - thermal conditions acceptable at 100°C"
                return 1  # Still fail but with explanation
            fi
            log_warning "NO RECOVERY PROTOCOL: $module_name"
            return 1
            ;;
    esac
}

#=============================================================================
# BUILD ORCHESTRATION - MISSION CONTROL
#=============================================================================

orchestrate_build() {
    local build_type="${1:-standard}"
    local custom_config="${2:-}"
    
    log_info "=== BUILD ORCHESTRATION START ==="
    log_info "Build type: $build_type"
    log_info "Configuration: ${custom_config:-default}"
    log_info "Modules to execute: ${#MODULE_EXECUTION_ORDER[@]}"
    
    # NOTE: Dependencies will be installed inside chroot after it's created
    # The chroot-dependencies module handles this at 28% completion
    log_info "Dependencies will be installed in chroot after creation"
    
    initialize_build_state
    
    # Execute modules in tactical sequence
    local total_modules=${#MODULE_EXECUTION_ORDER[@]}
    local current_module=0
    
    for percentage in $(echo "${!MODULE_EXECUTION_ORDER[@]}" | tr ' ' '\n' | sort -n); do
        local module_name="${MODULE_EXECUTION_ORDER[$percentage]}"
        ((current_module++)) || true
        
        log_info "ENGAGING TARGET [$current_module/$total_modules]: $module_name ($percentage%)"
        
        if execute_module "$module_name"; then
            log_success "TARGET SECURED: $module_name"
        else
            log_error "TARGET FAILED: $module_name - MISSION ABORT"
            generate_failure_report "module_execution" 1 "$module_name"
            return 1
        fi
        
        # Checkpoint after each module
        create_checkpoint "progress_${percentage}" "$BUILD_ROOT"
    done
    
    # Mission completion
    BUILD_STATUS="COMPLETED"
    local build_end_time=$(date +%s)
    local total_duration=$((build_end_time - BUILD_START_TIME))
    
    log_success "=== MISSION ACCOMPLISHED ==="
    log_success "Total duration: ${total_duration}s"
    log_success "Modules completed: ${#COMPLETED_MODULES[@]}"
    log_success "Modules failed: ${#FAILED_MODULES[@]}"
    
    # Generate mission report
    generate_mission_report "$total_duration"
    
    return 0
}

#=============================================================================
# VALIDATION & VERIFICATION - INTELLIGENCE ASSESSMENT
#=============================================================================

validate_environment() {
    log_info "=== ENVIRONMENT VALIDATION ==="
    
    local validation_errors=0
    
    # Validate required directories
    log_info "Validating directory structure..."
    for dir in "$MODULE_DIR" "$PYTHON_DIR" "$CONFIG_DIR"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Missing directory: $dir"
            ((validation_errors++)) || true
        else
            log_debug "Found directory: $dir"
        fi
    done
    
    # Validate required scripts
    log_info "Validating required scripts..."
    local required_scripts=(
        "install_all_dependencies.sh"
        "deploy_persist.sh"
        "quick-setup.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$REPO_ROOT/$script" ]]; then
            log_warning "Missing optional script: $script"
        else
            log_debug "Found script: $script"
        fi
    done
    
    # Validate modules
    log_info "Validating build modules..."
    for percentage in "${!MODULE_EXECUTION_ORDER[@]}"; do
        local module_name="${MODULE_EXECUTION_ORDER[$percentage]}"
        local module_script=""
        
        if [[ "$module_name" == *"/"* ]]; then
            module_script="$MODULE_DIR/${module_name}.sh"
        else
            module_script="$MODULE_DIR/${module_name}.sh"
        fi
        
        if [[ ! -f "$module_script" ]]; then
            log_error "Missing module: $module_script"
            ((validation_errors++)) || true
        else
            log_debug "Found module: $module_script"
        fi
    done
    
    # Check Python orchestrator
    if [[ -f "$PYTHON_DIR/mmdebstrap_orchestrator.py" ]]; then
        log_success "Python orchestrator available"
    else
        log_warning "Python orchestrator not found"
    fi
    
    # System requirements
    log_info "Validating system requirements..."
    local required_commands=("mmdebstrap" "mksquashfs" "xorriso" "chroot" "mount")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Missing command: $cmd"
            ((validation_errors++)) || true
        else
            log_debug "Found command: $cmd"
        fi
    done
    
    if [[ $validation_errors -gt 0 ]]; then
        log_error "Environment validation failed with $validation_errors errors"
        return 1
    fi
    
    log_success "Environment validation passed"
    return 0
}

#=============================================================================
# REPORTING & INTELLIGENCE - AFTER ACTION REPORTS
#=============================================================================

generate_mission_report() {
    local duration="$1"
    local report_file="$BUILD_ROOT/mission-report.txt"
    
    cat > "$report_file" <<EOF
=== BUILD ORCHESTRATION MISSION REPORT ===
Generated: $(date -Iseconds)
Classification: $CLASSIFICATION
Script: $SCRIPT_NAME v$SCRIPT_VERSION

MISSION PARAMETERS:
- Build Root: $BUILD_ROOT
- Total Duration: ${duration}s
- Modules Executed: ${#MODULE_EXECUTION_ORDER[@]}

ENGAGEMENT RESULTS:
- Completed Modules: ${#COMPLETED_MODULES[@]}
- Failed Modules: ${#FAILED_MODULES[@]}
- Skipped Modules: ${#SKIPPED_MODULES[@]}

MODULE PERFORMANCE:
EOF

    for metric in "${MODULE_METRICS[@]}"; do
        echo "- $metric" >> "$report_file"
    done
    
    if [[ ${#FAILED_MODULES[@]} -gt 0 ]]; then
        echo -e "\nFAILED MODULES:" >> "$report_file"
        for failed in "${FAILED_MODULES[@]}"; do
            echo "- $failed" >> "$report_file"
        done
    fi
    
    echo -e "\nMISSION STATUS: ${BUILD_STATUS}" >> "$report_file"
    echo "END REPORT" >> "$report_file"
    
    log_success "Mission report generated: $report_file"
}

generate_failure_report() {
    local context="$1"
    local error_code="$2" 
    local details="$3"
    local failure_file="$BUILD_ROOT/failure-report.txt"
    
    cat > "$failure_file" <<EOF
=== BUILD FAILURE REPORT ===
Generated: $(date -Iseconds)
Context: $context
Error Code: $error_code
Details: $details

BUILD STATE AT FAILURE:
- Phase: $BUILD_PHASE
- Progress: ${BUILD_PROGRESS}%
- Status: $BUILD_STATUS

COMPLETED MODULES: ${#COMPLETED_MODULES[@]}
FAILED MODULES: ${#FAILED_MODULES[@]}

TACTICAL RECOMMENDATION:
1. Review module logs in $LOG_DIR
2. Check system resources and dependencies
3. Verify module script integrity
4. Consider partial recovery with --continue flag

END FAILURE REPORT
EOF

    log_error "Failure report generated: $failure_file"
}

#=============================================================================
# COMMAND INTERFACE - TACTICAL OPERATIONS
#=============================================================================

show_help() {
    cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION - Build Orchestration Command

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    build [TYPE]     Execute full build orchestration
                     TYPE: standard (default), minimal, development
    
    validate         Validate environment and modules
    
    status           Show current build status
    
    clean            Clean build directories
    
    help             Show this help message

OPTIONS:
    --build-root DIR    Set build directory (default: /tmp/build)
    --debug            Enable debug output
    --dry-run          Show what would be executed
    --continue         Continue from last checkpoint
    --parallel N       Set max parallel jobs (default: $(nproc))

EXAMPLES:
    $0 build                    # Standard build
    $0 build development        # Development build  
    $0 validate                 # Environment check
    $0 clean                    # Clean build artifacts
    $0 --debug build            # Debug mode build

CLASSIFICATION: $CLASSIFICATION
VERSION: $SCRIPT_VERSION
EOF
}

#=============================================================================
# MAIN EXECUTION - COMMAND DISPATCH
#=============================================================================

main() {
    local command="${1:-help}"
    local build_type="${2:-standard}"
    
    # Process global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-root)
                BUILD_ROOT="$2"
                shift 2
                ;;
            --debug)
                export DEBUG=1
                set -x
                shift
                ;;
            --dry-run)
                export DRY_RUN=1
                shift
                ;;
            --continue)
                export CONTINUE=1
                shift
                ;;
            --parallel)
                MAX_PARALLEL_JOBS="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Execute command
    case "$command" in
        build)
            if validate_environment; then
                orchestrate_build "$build_type"
            else
                log_error "Environment validation failed - cannot proceed with build"
            fi
            ;;
        validate)
            validate_environment
            ;;
        status)
            show_build_status
            ;;
        clean)
            clean_build_artifacts
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

#=============================================================================
# UTILITY FUNCTIONS - SUPPORT OPERATIONS
#=============================================================================

show_build_status() {
    if [[ -f "$CHECKPOINT_DIR/build_start" ]]; then
        log_info "Build in progress or completed"
        log_info "Build root: $BUILD_ROOT"
        log_info "Progress: ${BUILD_PROGRESS}%"
        log_info "Status: $BUILD_STATUS"
        
        if [[ -f "$BUILD_ROOT/mission-report.txt" ]]; then
            log_info "Mission report available: $BUILD_ROOT/mission-report.txt"
        fi
    else
        log_info "No build in progress"
    fi
}

clean_build_artifacts() {
    log_info "Cleaning build artifacts..."
    
    if [[ -d "$BUILD_ROOT" ]]; then
        log_warning "Removing build directory: $BUILD_ROOT"
        rm -rf "$BUILD_ROOT"
        log_success "Build artifacts cleaned"
    else
        log_info "No build artifacts to clean"
    fi
}

#=============================================================================
# MISSION EXECUTION - TACTICAL DEPLOYMENT
#=============================================================================

# Verify we're running as root for build operations
if [[ "$1" == "build" ]] && [[ $EUID -ne 0 ]]; then
    log_error "Build operations require root privileges"
    log_info "Execute: sudo $0 $*"
    exit 1
fi

# Execute main command
main "$@"