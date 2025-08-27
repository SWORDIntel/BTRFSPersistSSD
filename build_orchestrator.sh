#!/bin/bash
#
# Build Orchestrator - Master Build Control Script v2.0
# Version: 2.0.0 - PRODUCTION
# Part of: LiveCD Generation System
#
# Requirements:
#   - command: systemd-nspawn
#   - file: common_module_functions.sh
#   - file: install_all_dependencies.sh
# Configuration:
#   - BUILD_ROOT: Build directory path
#   - MODULE_DIR: Module scripts location
#

# Source tactical support infrastructure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Source common functions
[[ -f "$REPO_ROOT/common_module_functions.sh" ]] && \
    source "$REPO_ROOT/common_module_functions.sh" || {
        echo "ERROR: Common module functions not found" >&2
        exit 1
    }

# Script configuration
readonly SCRIPT_NAME="build-orchestrator"
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_STATUS="PRODUCTION"

# Enable strict mode
set -eEuo pipefail
IFS=$'\n\t'

# Set error trap
trap 'error_handler $LINENO $? "$BASH_COMMAND"' ERR

#=============================================================================
# BUILD CONFIGURATION - TACTICAL PARAMETERS
#=============================================================================

# Build directories
readonly BUILD_ROOT="${BUILD_ROOT:-/tmp/build}"
readonly MODULE_DIR="${MODULE_DIR:-$REPO_ROOT/src/modules}"
readonly CHECKPOINT_DIR="$BUILD_ROOT/.checkpoints"
readonly METRICS_DIR="$BUILD_ROOT/.metrics"

# Build parameters
readonly MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-$(nproc)}"
readonly BUILD_TIMEOUT="${BUILD_TIMEOUT:-7200}"  # 2 hours default
readonly CHECKPOINT_INTERVAL="${CHECKPOINT_INTERVAL:-300}"  # 5 minutes

# Module execution order (percentage -> module name)
declare -A MODULE_EXECUTION_ORDER=(
    [10]="dependency-validation"
    [20]="environment-setup"
    [30]="base-system"
    [40]="kernel-compilation"
    [50]="package-installation"
    [60]="system-configuration"
    [70]="initramfs-generation"
    [80]="iso-assembly"
    [90]="validation"
    [100]="finalization"
)

#=============================================================================
# BUILD STATE MANAGEMENT - BATTLEFIELD TRACKING
#=============================================================================

# Global build state
declare -g BUILD_START_TIME
declare -g BUILD_PHASE=""
declare -g BUILD_PROGRESS=0
declare -g BUILD_STATUS="INITIALIZING"
declare -g FAILED_MODULES=()
declare -g COMPLETED_MODULES=()
declare -g MODULE_METRICS=()

# Initialize build state
initialize_build_state() {
    BUILD_START_TIME=$(date +%s)
    BUILD_PHASE="INITIALIZATION"
    BUILD_PROGRESS=0
    BUILD_STATUS="ACTIVE"
    
    # Create build directories
    safe_mkdir "$BUILD_ROOT" 755
    safe_mkdir "$CHECKPOINT_DIR" 755
    safe_mkdir "$METRICS_DIR" 755
    
    # Create initial checkpoint
    create_checkpoint "build_start" "$BUILD_ROOT"
    
    log_success "Build state initialized at $(date -Iseconds)"
}

#=============================================================================
# MODULE EXECUTION ENGINE - FORCE DEPLOYMENT
#=============================================================================

# Execute single module
execute_module() {
    local module_name="$1"
    local module_script="$MODULE_DIR/${module_name}.sh"
    local module_start_time=$(date +%s)
    
    # Validate module exists
    if [[ ! -f "$module_script" ]]; then
        log_error "Module not found: $module_script"
        FAILED_MODULES+=("$module_name")
        return 1
    fi
    
    log_info "Executing module: $module_name"
    
    # Create module checkpoint
    create_checkpoint "module_${module_name}_start" "$BUILD_ROOT"
    
    # Execute with timeout and error handling
    local result=0
    if timeout "$BUILD_TIMEOUT" bash "$module_script" "$BUILD_ROOT"; then
        local module_end_time=$(date +%s)
        local duration=$((module_end_time - module_start_time))
        
        COMPLETED_MODULES+=("$module_name")
        MODULE_METRICS+=("${module_name}:${duration}s")
        
        log_success "Module completed: $module_name (${duration}s)"
        create_checkpoint "module_${module_name}_complete" "$BUILD_ROOT"
    else
        result=$?
        FAILED_MODULES+=("$module_name")
        log_error "Module failed: $module_name (exit code: $result)"
        
        # Attempt recovery
        if recover_from_module_failure "$module_name"; then
            log_info "Recovery successful for module: $module_name"
            result=0
        fi
    fi
    
    return $result
}

# Execute modules in parallel where possible
execute_parallel_modules() {
    local -a module_group=("$@")
    local pids=()
    local failed=false
    
    log_info "Executing ${#module_group[@]} modules in parallel (max jobs: $MAX_PARALLEL_JOBS)"
    
    # Start modules
    for module in "${module_group[@]}"; do
        while [[ $(jobs -r | wc -l) -ge $MAX_PARALLEL_JOBS ]]; do
            sleep 0.1
        done
        
        execute_module "$module" &
        pids+=($!)
    done
    
    # Wait for completion
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=true
        fi
    done
    
    [[ "$failed" == "false" ]]
}

#=============================================================================
# BUILD ORCHESTRATION - MISSION CONTROL
#=============================================================================

# Main build orchestration
orchestrate_build() {
    local build_type="${1:-standard}"
    local custom_config="${2:-}"
    
    log_info "=== BUILD ORCHESTRATION START ==="
    log_info "Build type: $build_type"
    log_info "Configuration: ${custom_config:-default}"
    
    # Initialize build environment
    initialize_build_state
    
    # Validate environment
    if ! validate_build_environment; then
        log_error "Environment validation failed"
        return 1
    fi
    
    # Execute build phases
    local phase_result=0
    for percentage in $(echo "${!MODULE_EXECUTION_ORDER[@]}" | tr ' ' '\n' | sort -n); do
        local module="${MODULE_EXECUTION_ORDER[$percentage]}"
        
        BUILD_PHASE="$module"
        BUILD_PROGRESS=$percentage
        
        log_info "=== PHASE: $module ($percentage% complete) ==="
        
        # Update progress file
        update_build_progress "$percentage" "$module"
        
        # Execute module
        if ! execute_module "$module"; then
            phase_result=1
            
            if [[ "${FORCE_CONTINUE:-false}" != "true" ]]; then
                log_error "Build halted at phase: $module"
                break
            else
                log_warning "Continuing despite failure (FORCE_CONTINUE=true)"
            fi
        fi
        
        # Checkpoint after each major phase
        if [[ $((percentage % 20)) -eq 0 ]]; then
            create_checkpoint "phase_${percentage}" "$BUILD_ROOT"
        fi
    done
    
    # Finalize build
    if [[ $phase_result -eq 0 ]]; then
        BUILD_STATUS="SUCCESS"
        log_success "=== BUILD ORCHESTRATION COMPLETE ==="
    else
        BUILD_STATUS="FAILED"
        log_error "=== BUILD ORCHESTRATION FAILED ==="
    fi
    
    # Generate build report
    generate_build_report
    
    return $phase_result
}

#=============================================================================
# RECOVERY MECHANISMS - CASUALTY MANAGEMENT
#=============================================================================

# Recover from module failure
recover_from_module_failure() {
    local failed_module="$1"
    local recovery_attempts=0
    local max_attempts=3
    
    log_warning "Attempting recovery for module: $failed_module"
    
    while [[ $recovery_attempts -lt $max_attempts ]]; do
        recovery_attempts=$((recovery_attempts + 1))
        log_info "Recovery attempt $recovery_attempts/$max_attempts"
        
        # Try to recover from last checkpoint
        local last_checkpoint=$(find "$CHECKPOINT_DIR" -name "*.checkpoint" | sort | tail -1)
        if [[ -n "$last_checkpoint" ]]; then
            log_info "Recovering from checkpoint: $(basename "$last_checkpoint")"
            
            if recover_from_checkpoint "$(basename "$last_checkpoint" .checkpoint)" "$BUILD_ROOT"; then
                # Retry module execution
                if execute_module "$failed_module"; then
                    log_success "Recovery successful after $recovery_attempts attempts"
                    return 0
                fi
            fi
        fi
        
        # Exponential backoff
        sleep $((2 ** recovery_attempts))
    done
    
    log_error "Recovery failed after $max_attempts attempts"
    return 1
}

#=============================================================================
# VALIDATION FUNCTIONS - RECONNAISSANCE
#=============================================================================

# Validate build environment
validate_build_environment() {
    log_info "Validating build environment..."
    
    local validation_failed=false
    
    # Check required commands
    local required_commands=(
        "systemd-nspawn"
        "debootstrap"
        "mksquashfs"
        "xorriso"
        "git"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Missing required command: $cmd"
            validation_failed=true
        fi
    done
    
    # Check disk space (minimum 20GB)
    local available_space=$(df "$BUILD_ROOT" --output=avail -B G | tail -1 | tr -d 'G')
    if [[ $available_space -lt 20 ]]; then
        log_error "Insufficient disk space: ${available_space}GB available (20GB required)"
        validation_failed=true
    fi
    
    # Check memory (minimum 4GB)
    local available_memory=$(free -g | awk '/^Mem:/{print $7}')
    if [[ $available_memory -lt 4 ]]; then
        log_warning "Low memory: ${available_memory}GB available (4GB recommended)"
    fi
    
    # Check module directory
    if [[ ! -d "$MODULE_DIR" ]]; then
        log_error "Module directory not found: $MODULE_DIR"
        validation_failed=true
    fi
    
    # Check module scripts
    local module_count=$(find "$MODULE_DIR" -name "*.sh" -type f | wc -l)
    if [[ $module_count -eq 0 ]]; then
        log_error "No module scripts found in: $MODULE_DIR"
        validation_failed=true
    else
        log_info "Found $module_count module scripts"
    fi
    
    [[ "$validation_failed" == "false" ]]
}

#=============================================================================
# PROGRESS TRACKING - BATTLEFIELD AWARENESS
#=============================================================================

# Update build progress
update_build_progress() {
    local percentage="$1"
    local phase="$2"
    local current_time=$(date +%s)
    local elapsed=$((current_time - BUILD_START_TIME))
    
    # Calculate ETA
    local eta="unknown"
    if [[ $percentage -gt 0 ]]; then
        local total_estimated=$((elapsed * 100 / percentage))
        local remaining=$((total_estimated - elapsed))
        eta="$(date -u -d @${remaining} +'%H:%M:%S')"
    fi
    
    # Write progress file
    cat > "$BUILD_ROOT/.progress" <<EOF
{
    "timestamp": "$current_time",
    "percentage": $percentage,
    "phase": "$phase",
    "status": "$BUILD_STATUS",
    "elapsed_seconds": $elapsed,
    "eta": "$eta",
    "completed_modules": ${#COMPLETED_MODULES[@]},
    "failed_modules": ${#FAILED_MODULES[@]}
}
EOF
    
    # Log progress
    log_info "Progress: $percentage% - Phase: $phase - ETA: $eta"
}

#=============================================================================
# REPORTING - AFTER ACTION REPORT
#=============================================================================

# Generate build report
generate_build_report() {
    local report_file="$BUILD_ROOT/build-report-$(date +%Y%m%d-%H%M%S).txt"
    local current_time=$(date +%s)
    local total_duration=$((current_time - BUILD_START_TIME))
    
    {
        echo "==================================================================="
        echo "BUILD ORCHESTRATION REPORT"
        echo "==================================================================="
        echo "Build Status: $BUILD_STATUS"
        echo "Start Time: $(date -d @$BUILD_START_TIME -Iseconds)"
        echo "End Time: $(date -d @$current_time -Iseconds)"
        echo "Total Duration: $(date -u -d @${total_duration} +'%H:%M:%S')"
        echo ""
        echo "=== MODULE EXECUTION SUMMARY ==="
        echo "Completed Modules: ${#COMPLETED_MODULES[@]}"
        for module in "${COMPLETED_MODULES[@]}"; do
            echo "  ✓ $module"
        done
        echo ""
        echo "Failed Modules: ${#FAILED_MODULES[@]}"
        for module in "${FAILED_MODULES[@]}"; do
            echo "  ✗ $module"
        done
        echo ""
        echo "=== MODULE PERFORMANCE METRICS ==="
        for metric in "${MODULE_METRICS[@]}"; do
            echo "  $metric"
        done
        echo ""
        echo "=== RESOURCE UTILIZATION ==="
        echo "Peak Memory Usage: $(grep VmPeak /proc/$$/status | awk '{print $2/1024 " MB"}')"
        echo "CPU Time: $(ps -p $$ -o cputime= | tr -d ' ')"
        echo "Disk Usage: $(du -sh "$BUILD_ROOT" 2>/dev/null | cut -f1)"
        echo ""
        echo "=== CHECKPOINTS CREATED ==="
        find "$CHECKPOINT_DIR" -name "*.checkpoint" -type f | while read checkpoint; do
            echo "  $(basename "$checkpoint" .checkpoint) - $(stat -c %y "$checkpoint" | cut -d'.' -f1)"
        done
        echo "==================================================================="
    } > "$report_file"
    
    log_success "Build report generated: $report_file"
    
    # Also output summary to console
    if [[ "$BUILD_STATUS" == "SUCCESS" ]]; then
        log_success "Build completed successfully in $(date -u -d @${total_duration} +'%H:%M:%S')"
    else
        log_error "Build failed after $(date -u -d @${total_duration} +'%H:%M:%S')"
        log_error "Failed modules: ${FAILED_MODULES[*]}"
    fi
}

#=============================================================================
# MAIN EXECUTION - MISSION LAUNCH
#=============================================================================

main() {
    local action="${1:-build}"
    shift || true
    
    case "$action" in
        build)
            orchestrate_build "$@"
            ;;
        validate)
            validate_build_environment
            ;;
        report)
            generate_build_report
            ;;
        clean)
            log_info "Cleaning build directory: $BUILD_ROOT"
            rm -rf "$BUILD_ROOT"
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Usage: $0 {build|validate|report|clean} [options]"
            exit 1
            ;;
    esac
}

# Execute if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi