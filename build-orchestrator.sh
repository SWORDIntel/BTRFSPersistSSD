#!/bin/bash
#
# BUILD ORCHESTRATOR v3.3 - MASTER CONTROL SCRIPT  
# Fixed version with proper chroot handling and safety improvements
#
set -eEuo pipefail
IFS=$'\n\t'

#=============================================================================
# CONFIGURATION
#=============================================================================

SCRIPT_NAME="build-orchestrator"
SCRIPT_VERSION="3.3.0"
SCRIPT_STATUS="PRODUCTION-READY"

# Establish paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Initialize critical variables early to prevent unbound variable errors
BUILD_ROOT="${BUILD_ROOT:-/tmp/build}"
CHROOT_DIR="$BUILD_ROOT/chroot"
MODULE_DIR="$REPO_ROOT/src/modules"
PYTHON_DIR="$REPO_ROOT/src/python"
CONFIG_DIR="$REPO_ROOT/src/config"

# Colors for output
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
# SOURCE COMMON FUNCTIONS
#=============================================================================

source_common_functions() {
    local common_found=false
    local search_paths=(
        "$REPO_ROOT/common_module_functions.sh"
        "$REPO_ROOT/src/modules/common_module_functions.sh"
        "$REPO_ROOT/src/python/common_module_functions.sh"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path" ]]; then
            source "$path"
            common_found=true
            log_info "Common functions loaded from $path"
            break
        fi
    done
    
    if [[ "$common_found" == "false" ]]; then
        # Fallback logging functions
        log_info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
        log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
        log_warning() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
        log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $*"; }
        log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${RESET} $*"; }
        
        log_error "Common functions not found in any location"
    fi
}

source_common_functions

#=============================================================================
# BUILD ENVIRONMENT SETUP
#=============================================================================

setup_build_environment() {
    # Safer RAM disk logic - only use existing or explicitly requested
    if [[ -z "${BUILD_ROOT:-}" ]]; then
        if [[ "${USE_RAMDISK:-}" == "1" ]] && [[ -d /dev/shm ]]; then
            local available_gb
            available_gb=$(df -BG /dev/shm 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
            if [[ "$available_gb" -ge 25 ]]; then
                BUILD_ROOT="/dev/shm/build"
                log_info "Using RAM disk: /dev/shm (requested via USE_RAMDISK=1)"
            else
                log_warning "Insufficient RAM for build (need 25GB, have ${available_gb}GB)"
                BUILD_ROOT="/tmp/build"
            fi
        elif mountpoint -q /tmp/ramdisk-build 2>/dev/null; then
            BUILD_ROOT="/tmp/ramdisk-build"
            log_info "Using existing RAM disk: /tmp/ramdisk-build"
        else
            BUILD_ROOT="/tmp/build"
            log_info "Using disk storage: /tmp/build"
        fi
    fi
    
    # Build paths
    BUILD_ROOT="${BUILD_ROOT:-/tmp/build}"
    CHROOT_DIR="$BUILD_ROOT/chroot"
    ISO_DIR="$BUILD_ROOT/iso"
    ISO_OUTPUT="$BUILD_ROOT/ubuntu.iso"
    MODULE_DIR="$REPO_ROOT/src/modules"
    PYTHON_DIR="$REPO_ROOT/src/python"
    CONFIG_DIR="$REPO_ROOT/src/config"
    CHECKPOINT_DIR="$BUILD_ROOT/.checkpoints"
    METRICS_DIR="$BUILD_ROOT/.metrics"
    LOG_DIR="$BUILD_ROOT/.logs"
    LOG_FILE="$BUILD_ROOT/build-$(date +%Y%m%d-%H%M%S).log"
    
    # Operational parameters
    MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-$(nproc)}"
    BUILD_TIMEOUT="${BUILD_TIMEOUT:-14400}"  # 4 hours
    CHECKPOINT_INTERVAL="${CHECKPOINT_INTERVAL:-300}"  # 5 minutes
}

# Module execution order
declare -A MODULE_EXECUTION_ORDER=(
    [10]="dependency-validation"
    [15]="environment-setup" 
    [20]="mmdebootstrap/orchestrator"
    [25]="stages-enhanced/03-mmdebstrap-bootstrap"
    [26]="package-installation"
    [28]="chroot-dependencies"
    [30]="config-apply"
    [35]="zfs-builder"
    [38]="dell-cctk-builder"
    [40]="kernel-compilation"
    [50]="system-configuration"
    [55]="boot-configuration"
    [60]="initramfs-generation"
    [65]="iso-assembly"
    [70]="validation"
    [90]="finalization"
)

# Build state tracking
declare -g BUILD_START_TIME=0
declare -g BUILD_PHASE=""
declare -g BUILD_PROGRESS=0
declare -g BUILD_STATUS="INITIALIZING"
declare -g FAILED_MODULES=()
declare -g COMPLETED_MODULES=()
declare -g SKIPPED_MODULES=()
declare -g MODULE_METRICS=()
declare -g BUILD_PID_FILE=""

#=============================================================================
# CHROOT MOUNT MANAGEMENT
#=============================================================================

mount_chroot_filesystems() {
    local chroot_path="$1"
    
    if [[ ! -d "$chroot_path" ]]; then
        log_error "Chroot directory does not exist: $chroot_path"
        return 1
    fi
    
    log_info "Mounting chroot filesystems..."
    
    # Create mount points
    local mount_dirs=("proc" "sys" "dev" "dev/pts" "dev/shm" "tmp")
    for dir in "${mount_dirs[@]}"; do
        mkdir -p "$chroot_path/$dir" 2>/dev/null || true
    done
    
    # Mount in dependency order
    if ! mountpoint -q "$chroot_path/proc" 2>/dev/null; then
        mount -t proc proc "$chroot_path/proc" || log_warning "Failed to mount proc"
    fi
    
    if ! mountpoint -q "$chroot_path/sys" 2>/dev/null; then
        mount -t sysfs sysfs "$chroot_path/sys" || log_warning "Failed to mount sys"
    fi
    
    if ! mountpoint -q "$chroot_path/dev" 2>/dev/null; then
        mount --bind /dev "$chroot_path/dev" || log_warning "Failed to bind mount dev"
    fi
    
    if ! mountpoint -q "$chroot_path/dev/pts" 2>/dev/null; then
        mount -t devpts devpts "$chroot_path/dev/pts" || log_warning "Failed to mount devpts"
    fi
    
    if ! mountpoint -q "$chroot_path/dev/shm" 2>/dev/null; then
        mount -t tmpfs tmpfs "$chroot_path/dev/shm" || log_warning "Failed to mount shm"
    fi
    
    log_success "Chroot filesystems mounted"
}

unmount_chroot_filesystems() {
    # GUARD CLAUSE: Prevent recursive unmount calls
    if [[ "${UNMOUNT_IN_PROGRESS:-0}" == "1" ]]; then
        echo "[WARNING] Unmount already in progress, skipping recursive call"
        return 0
    fi
    
    export UNMOUNT_IN_PROGRESS=1
    
    # Disable error trap for cleanup
    local prev_errexit=$(set +o | grep errexit)
    set +e
    trap - ERR
    
    local chroot_path="$1"
    local mount_points=(
        "$chroot_path/dev/pts"
        "$chroot_path/dev/shm"  
        "$chroot_path/dev"
        "$chroot_path/proc"
        "$chroot_path/sys"
        "$chroot_path/tmp"
    )
    
    log_info "Unmounting chroot filesystems..."
    
    # Kill processes using chroot first (with timeout to prevent hanging)
    if command -v fuser >/dev/null 2>&1; then
        # Use timeout to prevent fuser from hanging
        if timeout 2 fuser "$chroot_path" 2>/dev/null; then
            log_warning "Terminating processes using chroot..."
            timeout 2 fuser -TERM "$chroot_path" 2>/dev/null || true
            sleep 2
            timeout 2 fuser -KILL "$chroot_path" 2>/dev/null || true
            sleep 1
        fi
    fi
    
    # Unmount in reverse dependency order
    for mount_point in "${mount_points[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_debug "Unmounting $mount_point"
            if ! umount "$mount_point" 2>/dev/null; then
                log_warning "Normal unmount failed for $mount_point, trying lazy unmount..."
                umount -l "$mount_point" 2>/dev/null || log_warning "Failed to unmount $mount_point"
            fi
        fi
    done
    
    # Check for remaining mounts
    if mount | grep -q "$chroot_path"; then
        log_warning "Some mounts still active, attempting cleanup..."
        mount | grep "$chroot_path" | while IFS= read -r line; do
            mount_point=$(echo "$line" | awk '{print $3}')
            log_debug "Force unmounting: $mount_point"
            umount "$mount_point" 2>/dev/null || umount -l "$mount_point" 2>/dev/null || true
        done
    fi
    
    sleep 2
    log_success "Chroot filesystems unmounted"
    
    # Clear guard flag and always return success
    export UNMOUNT_IN_PROGRESS=0
    return 0
}

#=============================================================================
# ERROR HANDLING
#=============================================================================

error_handler() {
    # Disable error trap to prevent recursion
    trap - ERR
    set +e
    
    local line_no=$1
    local error_code=$2
    local command="$3"
    
    log_error "Build failed at line $line_no (exit code: $error_code)"
    log_error "Failed command: $command"
    log_error "Build phase: $BUILD_PHASE"
    log_error "Build progress: ${BUILD_PROGRESS}%"
    
    generate_failure_report "$line_no" "$error_code" "$command"
    cleanup_on_failure
    
    exit $error_code
}

trap 'error_handler $LINENO $? "$BASH_COMMAND"' ERR

#=============================================================================
# BUILD STATE MANAGEMENT
#=============================================================================

initialize_build_state() {
    setup_build_environment
    
    BUILD_START_TIME=$(date +%s)
    BUILD_PHASE="INITIALIZATION"
    BUILD_PROGRESS=0
    BUILD_STATUS="ACTIVE"
    BUILD_PID_FILE="$BUILD_ROOT/.build.pid"
    
    log_info "=== BUILD ORCHESTRATION START ==="
    log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Build root: $BUILD_ROOT"
    log_info "Module directory: $MODULE_DIR"
    log_info "Started: $(date -Iseconds)"
    
    # Create build directories
    local dirs=("$BUILD_ROOT" "$CHECKPOINT_DIR" "$METRICS_DIR" "$LOG_DIR")
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir" || log_error "Failed to create directory: $dir"
    done
    
    # Create build tracking files
    echo "$$" > "$BUILD_PID_FILE"
    echo "$(date -Iseconds)" > "$BUILD_ROOT/.build.start"
    echo "0%" > "$METRICS_DIR/progress.txt"
    
    # Create initial checkpoint
    create_checkpoint "build_start" "$BUILD_ROOT" 2>/dev/null || true
    
    log_success "Build state initialized"
}

#=============================================================================
# MODULE STATE VERIFICATION
#=============================================================================

verify_chroot_creation_success() {
    log_info "Verifying chroot creation success..."
    
    if [[ ! -d "$CHROOT_DIR" ]]; then
        log_error "Chroot directory does not exist: $CHROOT_DIR"
        return 1
    fi
    
    # Check for essential directories
    local critical_dirs=("bin" "usr" "etc" "var" "opt")
    local missing_dirs=()
    
    for dir in "${critical_dirs[@]}"; do
        if [[ ! -d "$CHROOT_DIR/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_error "Critical directories missing from chroot: ${missing_dirs[*]}"
        return 1
    fi
    
    # Check for mmdebstrap completion marker
    if [[ -f "$CHROOT_DIR/.mmdebstrap-complete" ]]; then
        log_success "Chroot creation verified - mmdebstrap completion marker found"
        local timestamp=$(cat "$CHROOT_DIR/.mmdebstrap-timestamp" 2>/dev/null || echo "unknown")
        log_info "Chroot created at: $timestamp"
    else
        log_warning "No mmdebstrap completion marker, but chroot structure looks valid"
    fi
    
    # Check chroot size
    if command -v du >/dev/null 2>&1; then
        local chroot_size=$(du -sh "$CHROOT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        log_info "Chroot size: $chroot_size"
        
        # Basic size validation - chroot should be at least 200MB
        local size_mb=$(du -sm "$CHROOT_DIR" 2>/dev/null | head -1 | cut -f1 || echo "0")
        # Ensure size_mb is numeric
        size_mb="${size_mb//[^0-9]/}"
        size_mb="${size_mb:-0}"
        if [[ "$size_mb" -lt 200 ]]; then
            log_warning "Chroot size seems small ($size_mb MB) - possible incomplete installation"
        fi
    fi
    
    log_success "Chroot creation verification passed"
    return 0
}

#=============================================================================
# MODULE EXECUTION ENGINE
#=============================================================================

execute_module() {
    local module_name="$1"
    local module_phase="${2:-$(echo "$module_name" | tr '-' '_' | tr '/' '_')}"
    local module_start_time=$(date +%s)
    local module_script=""
    
    BUILD_PHASE="$module_phase"
    
    # Check if module already completed
    if [[ -f "$CHECKPOINT_DIR/completed_modules" ]] && grep -qx "$module_name" "$CHECKPOINT_DIR/completed_modules"; then
        log_info "Module $module_name already completed, skipping..."
        COMPLETED_MODULES+=("$module_name")
        return 0
    fi
    
    echo "$module_name" > "$CHECKPOINT_DIR/current_module"
    
    # Fix module path resolution
    if [[ "$module_name" == *"/"* ]]; then
        # Subdirectory module (e.g., mmdebootstrap/orchestrator)
        module_script="$MODULE_DIR/${module_name}.sh"
    else
        # Root level module  
        module_script="$MODULE_DIR/${module_name}.sh"
    fi
    
    # Validate module exists
    if [[ ! -f "$module_script" ]]; then
        log_error "Module not found: $module_script"
        FAILED_MODULES+=("$module_name")
        return 1
    fi
    
    log_info "=== EXECUTING MODULE: $module_name ==="
    log_info "Script: $module_script"
    log_info "Phase: $module_phase"
    
    create_checkpoint "module_${module_phase}_start" "$BUILD_ROOT" 2>/dev/null || true
    
    # Execute module with error isolation
    local result=0
    local module_log="$LOG_DIR/module_${module_phase}.log"
    
    log_debug "Executing: $module_script with BUILD_ROOT=$BUILD_ROOT"
    
    # ENHANCED ERROR ISOLATION: Create isolated execution environment
    local MODULE_ERROR_HANDLING=0
    export MODULE_ERROR_HANDLING
    
    # Disable error trap for module execution to prevent recursive cleanup
    set +e
    trap - ERR
    
    # Special handling for mmdebstrap (no timeout to prevent chroot issues)
    if [[ "$module_name" == "mmdebootstrap/orchestrator" ]]; then
        DEBUG=1 VERBOSE=1 bash "$module_script" "$BUILD_ROOT" >> "$module_log" 2>&1
        result=$?
    else
        # Use timeout for other modules
        DEBUG=1 VERBOSE=1 timeout "$BUILD_TIMEOUT" bash "$module_script" "$BUILD_ROOT" >> "$module_log" 2>&1
        result=$?
    fi
    
    # Re-enable error handling after module execution
    set -e
    trap 'error_handler $LINENO $? "$BASH_COMMAND"' ERR
    
    if [[ $result -eq 0 ]]; then
        local module_end_time=$(date +%s)
        local duration=$((module_end_time - module_start_time))
        
        COMPLETED_MODULES+=("$module_name")
        MODULE_METRICS+=("${module_name}:${duration}s")
        
        echo "$module_name" >> "$CHECKPOINT_DIR/completed_modules"
        
        log_success "Module completed: $module_name (${duration}s)"
        create_checkpoint "module_${module_phase}_complete" "$BUILD_ROOT" 2>/dev/null || true
        
        # Critical verification for chroot creation modules
        if [[ "$module_name" == "mmdebootstrap/orchestrator" ]]; then
            verify_chroot_creation_success || {
                log_error "CRITICAL: Chroot creation verification failed"
                FAILED_MODULES+=("$module_name")
                return 1
            }
        fi
        
        update_build_progress "$module_name"
        
    else
        FAILED_MODULES+=("$module_name")
        log_error "Module failed: $module_name (exit code: $result)"
        
        if attempt_module_recovery "$module_name" "$result"; then
            log_info "Module recovery successful: $module_name"
            result=0
        else
            log_error "Module recovery failed: $module_name"
        fi
    fi
    
    return $result
}

update_build_progress() {
    local module_name="$1"
    
    for percentage in $(echo "${!MODULE_EXECUTION_ORDER[@]}" | tr ' ' '\n' | sort -n); do
        if [[ "${MODULE_EXECUTION_ORDER[$percentage]}" == "$module_name" ]]; then
            BUILD_PROGRESS=$percentage
            
            mkdir -p "$METRICS_DIR"
            echo "${BUILD_PROGRESS}%" > "$METRICS_DIR/progress.txt"
            echo "$(date -Iseconds) $module_name ${BUILD_PROGRESS}%" >> "$METRICS_DIR/progress.log"
            
            log_info "Build progress: ${BUILD_PROGRESS}% - $module_name complete"
            break
        fi
    done
}

#=============================================================================
# MODULE RECOVERY
#=============================================================================

attempt_module_recovery() {
    local module_name="$1"
    local error_code="$2"
    
    log_warning "Attempting recovery for: $module_name (error: $error_code)"
    
    case "$module_name" in
        "mmdebootstrap/orchestrator")
            # Check if chroot was actually created despite error
            if [[ -d "$CHROOT_DIR" ]] && [[ -d "$CHROOT_DIR/usr" ]] && [[ -f "$CHROOT_DIR/bin/bash" ]]; then
                log_success "Chroot exists despite error, considering successful"
                return 0
            fi
            return 1
            ;;
        "kernel-compilation")
            if [[ -d "$CHROOT_DIR" ]]; then
                log_info "Cleaning kernel build artifacts"
                chroot "$CHROOT_DIR" /bin/bash -c "cd /usr/src/linux* 2>/dev/null && make clean" 2>/dev/null || true
            fi
            return 1
            ;;
        *)
            if [[ "$error_code" == "124" ]]; then
                log_warning "Module timed out, may need more time"
            fi
            return 1
            ;;
    esac
}

#=============================================================================
# BUILD ORCHESTRATION
#=============================================================================

orchestrate_build() {
    local build_type="${1:-standard}"
    local custom_config="${2:-}"
    
    log_info "=== BUILD ORCHESTRATION ==="
    log_info "Build type: $build_type"
    log_info "Configuration: ${custom_config:-default}"
    log_info "Modules to execute: ${#MODULE_EXECUTION_ORDER[@]}"
    
    initialize_build_state
    
    local total_modules=${#MODULE_EXECUTION_ORDER[@]}
    local current_module=0
    
    for percentage in $(echo "${!MODULE_EXECUTION_ORDER[@]}" | tr ' ' '\n' | sort -n); do
        local module_name="${MODULE_EXECUTION_ORDER[$percentage]}"
        ((current_module++)) || true
        
        log_info "Executing module [$current_module/$total_modules]: $module_name ($percentage%)"
        
        # CRITICAL VERIFICATION: Check chroot handoff between 20% and 25%
        if [[ "$percentage" == "25" ]]; then
            log_info "=== CRITICAL HANDOFF VERIFICATION (20% -> 25%) ==="
            if ! verify_chroot_creation_success; then
                log_error "CRITICAL: Chroot verification failed before 25% module"
                log_error "This indicates 20% module (mmdebstrap) did not complete properly"
                generate_failure_report "chroot_handoff_verification" 1 "$module_name"
                return 1
            fi
            log_success "Chroot handoff verification passed - proceeding to 25% module"
        fi
        
        if execute_module "$module_name"; then
            log_success "Module completed: $module_name"
        else
            log_error "Module failed: $module_name - Build aborted"
            generate_failure_report "module_execution" 1 "$module_name"
            return 1
        fi
        
        create_checkpoint "progress_${percentage}" "$BUILD_ROOT" 2>/dev/null || true
    done
    
    # Build completion
    BUILD_STATUS="COMPLETED"
    local build_end_time=$(date +%s)
    local total_duration=$((build_end_time - BUILD_START_TIME))
    
    log_success "=== BUILD COMPLETED ==="
    log_success "Total duration: ${total_duration}s"
    log_success "Modules completed: ${#COMPLETED_MODULES[@]}"
    log_success "Modules failed: ${#FAILED_MODULES[@]}"
    
    generate_mission_report "$total_duration"
    
    return 0
}

#=============================================================================
# VALIDATION
#=============================================================================

validate_environment() {
    log_info "=== ENVIRONMENT VALIDATION ==="
    
    local validation_errors=0
    
    # Check directories
    local required_dirs=("$MODULE_DIR" "$PYTHON_DIR" "$CONFIG_DIR")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Missing directory: $dir"
            ((validation_errors++)) || true
        fi
    done
    
    # Check modules exist
    for percentage in "${!MODULE_EXECUTION_ORDER[@]}"; do
        local module_name="${MODULE_EXECUTION_ORDER[$percentage]}"
        local module_script="$MODULE_DIR/${module_name}.sh"
        
        if [[ ! -f "$module_script" ]]; then
            log_error "Missing module: $module_script"
            ((validation_errors++)) || true
        fi
    done
    
    # Check required commands
    local required_commands=("mmdebstrap" "mksquashfs" "xorriso" "chroot" "mount")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Missing command: $cmd"
            ((validation_errors++)) || true
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
# REPORTING
#=============================================================================

generate_mission_report() {
    local duration="$1"
    local report_file="$BUILD_ROOT/build-report.txt"
    
    cat > "$report_file" <<EOF
=== BUILD ORCHESTRATION REPORT ===
Generated: $(date -Iseconds)
Script: $SCRIPT_NAME v$SCRIPT_VERSION

BUILD PARAMETERS:
- Build Root: $BUILD_ROOT
- Total Duration: ${duration}s
- Modules Executed: ${#MODULE_EXECUTION_ORDER[@]}

RESULTS:
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
    
    echo -e "\nBUILD STATUS: ${BUILD_STATUS}" >> "$report_file"
    
    log_success "Build report generated: $report_file"
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

BUILD STATE:
- Phase: $BUILD_PHASE
- Progress: ${BUILD_PROGRESS}%
- Status: $BUILD_STATUS

RECOMMENDATIONS:
1. Review module logs in $LOG_DIR
2. Check system resources and dependencies
3. Verify module script integrity
4. Consider recovery with --continue flag
EOF

    log_error "Failure report: $failure_file"
}

cleanup_on_failure() {
    # GUARD CLAUSE: Prevent recursive cleanup calls
    if [[ "${CLEANUP_IN_PROGRESS:-0}" == "1" ]]; then
        echo "[WARNING] Cleanup already in progress, skipping recursive call"
        return 0
    fi
    
    export CLEANUP_IN_PROGRESS=1
    
    # Disable error trap to prevent recursion
    trap - ERR
    set +e
    
    log_warning "Executing cleanup procedures..."
    
    # Unmount chroot if it exists
    if [[ -d "$CHROOT_DIR" ]]; then
        unmount_chroot_filesystems "$CHROOT_DIR" 2>/dev/null || true
    fi
    
    # Kill only our build-related processes
    if [[ -f "$BUILD_PID_FILE" ]]; then
        local build_pid
        build_pid=$(cat "$BUILD_PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$build_pid" ]] && ps -p "$build_pid" >/dev/null 2>&1; then
            kill "$build_pid" 2>/dev/null || true
        fi
        rm -f "$BUILD_PID_FILE"
    fi
    
    log_info "Cleanup complete"
    
    # Clear guard flag and always return success to prevent error trap
    export CLEANUP_IN_PROGRESS=0
    return 0
}

#=============================================================================
# COMMANDS
#=============================================================================

show_help() {
    cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION - Build Orchestration

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    build [TYPE]     Execute build (standard, minimal, development)
    validate         Validate environment
    status           Show build status  
    clean            Clean build artifacts
    help             Show this help

OPTIONS:
    --build-root DIR    Set build directory
    --use-ramdisk       Use RAM disk for build (requires 25GB RAM)
    --debug            Enable debug output
    --continue         Continue from checkpoint

EXAMPLES:
    $0 build
    $0 --use-ramdisk build
    $0 validate
    $0 clean
EOF
}

show_build_status() {
    if [[ -f "$CHECKPOINT_DIR/build_start" ]]; then
        log_info "Build status: ${BUILD_STATUS:-UNKNOWN}"
        log_info "Build root: ${BUILD_ROOT:-Not set}"
        if [[ -f "$METRICS_DIR/progress.txt" ]]; then
            local progress
            progress=$(cat "$METRICS_DIR/progress.txt")
            log_info "Progress: $progress"
        fi
    else
        log_info "No build in progress"
    fi
}

clean_build_artifacts() {
    log_info "Cleaning build artifacts..."
    
    if [[ -d "$BUILD_ROOT" ]]; then
        # Safely unmount chroot first
        if [[ -d "$BUILD_ROOT/chroot" ]]; then
            unmount_chroot_filesystems "$BUILD_ROOT/chroot" 2>/dev/null || true
        fi
        
        log_warning "Removing: $BUILD_ROOT"
        rm -rf "$BUILD_ROOT"
        log_success "Build artifacts cleaned"
    else
        log_info "No artifacts to clean"
    fi
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    local command="${1:-help}"
    shift || true
    
    # Process options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-root)
                BUILD_ROOT="$2"
                shift 2
                ;;
            --use-ramdisk)
                export USE_RAMDISK=1
                shift
                ;;
            --debug)
                export DEBUG=1
                set -x
                shift
                ;;
            --continue)
                export CONTINUE=1
                shift
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
            local build_type="${1:-standard}"
            if validate_environment; then
                orchestrate_build "$build_type"
            else
                log_error "Environment validation failed"
                exit 1
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

# Verify root for build operations
if [[ "$1" == "build" ]] && [[ $EUID -ne 0 ]]; then
    log_error "Build requires root privileges"
    log_info "Run: sudo $0 $*"
    exit 1
fi

# Set cleanup trap
trap cleanup_on_failure EXIT INT TERM

# Execute
main "$@"