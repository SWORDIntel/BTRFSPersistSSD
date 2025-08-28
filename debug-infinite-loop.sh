#!/bin/bash
#
# EMERGENCY INFINITE LOOP DEBUGGER v1.0
# Created by PROJECTORCHESTRATOR for tactical debugging
#
set -euo pipefail

SCRIPT_NAME="debug-infinite-loop"
SCRIPT_VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_warning() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $*"; }

show_help() {
    cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION - Emergency Infinite Loop Debugger

USAGE:
    $0 [COMMAND]

COMMANDS:
    detect      Detect infinite loops in build processes
    kill        Kill all build-related processes
    cleanup     Clean up guard clauses and reset state
    monitor     Monitor for recursive patterns
    analyze     Analyze recent logs for loop patterns
    reset       Full system reset and cleanup
    status      Show current guard clause status
    
EXAMPLES:
    $0 detect               # Scan for infinite loop patterns
    $0 kill                 # Emergency kill of build processes
    $0 cleanup              # Reset all guard clauses
    $0 monitor              # Real-time loop detection
EOF
}

detect_infinite_loops() {
    log_info "=== INFINITE LOOP DETECTION ==="
    
    local loop_detected=false
    
    # Check for recursive process patterns
    log_info "Checking for recursive build processes..."
    if pgrep -f "build-orchestrator" | wc -l | grep -q '[2-9]'; then
        log_warning "Multiple build-orchestrator processes detected:"
        pgrep -af "build-orchestrator"
        loop_detected=true
    fi
    
    # Check for stuck cleanup processes
    log_info "Checking for stuck cleanup processes..."
    if pgrep -f "cleanup" | wc -l | grep -q '[2-9]'; then
        log_warning "Multiple cleanup processes detected:"
        pgrep -af "cleanup"
        loop_detected=true
    fi
    
    # Check guard clause status
    log_info "Checking guard clause status..."
    if [[ "${CLEANUP_IN_PROGRESS:-0}" == "1" ]]; then
        log_warning "CLEANUP_IN_PROGRESS flag is set - possible stuck cleanup"
        loop_detected=true
    fi
    
    if [[ "${UNMOUNT_IN_PROGRESS:-0}" == "1" ]]; then
        log_warning "UNMOUNT_IN_PROGRESS flag is set - possible stuck unmount"
        loop_detected=true
    fi
    
    if [[ "${STAGE_ERROR_HANDLING:-0}" == "1" ]]; then
        log_warning "STAGE_ERROR_HANDLING flag is set - possible stuck error handler"
        loop_detected=true
    fi
    
    # Check for recursive log patterns
    log_info "Analyzing recent logs for recursive patterns..."
    local log_dir="${BUILD_ROOT:-/tmp/build}/.logs"
    if [[ -d "$log_dir" ]]; then
        # Look for repeated error messages (indication of recursion)
        local repeated_errors=$(find "$log_dir" -name "*.log" -mtime -1 -exec grep -h "ERROR" {} \; 2>/dev/null | sort | uniq -c | sort -nr | head -3)
        if echo "$repeated_errors" | grep -q '[1-9][0-9]\+'; then
            log_warning "Repeated error patterns found:"
            echo "$repeated_errors"
            loop_detected=true
        fi
    fi
    
    if [[ "$loop_detected" == "true" ]]; then
        log_error "INFINITE LOOP DETECTED - Immediate action required"
        log_info "Run: $0 kill     # To terminate stuck processes"
        log_info "Run: $0 cleanup  # To reset guard clauses"
        return 1
    else
        log_success "No infinite loops detected"
        return 0
    fi
}

kill_build_processes() {
    log_warning "=== EMERGENCY PROCESS TERMINATION ==="
    
    # Kill build orchestrator processes
    if pgrep -f "build-orchestrator" >/dev/null; then
        log_info "Terminating build-orchestrator processes..."
        pkill -TERM -f "build-orchestrator" || true
        sleep 3
        pkill -KILL -f "build-orchestrator" || true
    fi
    
    # Kill module processes
    for module in "mmdebstrap" "stages-enhanced" "chroot-dependencies"; do
        if pgrep -f "$module" >/dev/null; then
            log_info "Terminating $module processes..."
            pkill -TERM -f "$module" || true
        fi
    done
    
    # Kill cleanup processes
    if pgrep -f "cleanup" >/dev/null; then
        log_info "Terminating cleanup processes..."
        pkill -TERM -f "cleanup" || true
        sleep 2
        pkill -KILL -f "cleanup" || true
    fi
    
    # Kill any chroot processes
    if pgrep -f "chroot" >/dev/null; then
        log_info "Terminating chroot processes..."
        pkill -TERM -f "chroot" || true
        sleep 2
        pkill -KILL -f "chroot" || true
    fi
    
    log_success "Process termination complete"
}

cleanup_guard_clauses() {
    log_info "=== GUARD CLAUSE CLEANUP ==="
    
    # Reset all guard flags
    export CLEANUP_IN_PROGRESS=0
    export UNMOUNT_IN_PROGRESS=0  
    export STAGE_ERROR_HANDLING=0
    
    # Clear environment variables
    unset CLEANUP_IN_PROGRESS
    unset UNMOUNT_IN_PROGRESS
    unset STAGE_ERROR_HANDLING
    
    # Remove any stuck PID files
    local build_root="${BUILD_ROOT:-/tmp/build}"
    if [[ -f "$build_root/.build.pid" ]]; then
        log_info "Removing stuck PID file..."
        rm -f "$build_root/.build.pid"
    fi
    
    # Clean up any lock files
    find "$build_root" -name "*.lock" -delete 2>/dev/null || true
    
    log_success "Guard clauses reset"
}

monitor_loops() {
    log_info "=== REAL-TIME LOOP MONITORING ==="
    log_info "Monitoring for 60 seconds... Press Ctrl+C to stop"
    
    local start_time=$(date +%s)
    local duration=60
    
    while [[ $(($(date +%s) - start_time)) -lt $duration ]]; do
        local current_procs=$(pgrep -f "build-orchestrator" | wc -l)
        local current_cleanup=$(pgrep -f "cleanup" | wc -l)
        
        if [[ "$current_procs" -gt 1 ]] || [[ "$current_cleanup" -gt 1 ]]; then
            log_warning "LOOP DETECTED: build-orchestrator=$current_procs, cleanup=$current_cleanup"
            detect_infinite_loops
            return 1
        fi
        
        echo -ne "\rMonitoring... build-orchestrator=$current_procs cleanup=$current_cleanup time=$(($(date +%s) - start_time))s"
        sleep 2
    done
    
    echo
    log_success "Monitoring complete - no loops detected"
}

analyze_logs() {
    log_info "=== LOG ANALYSIS FOR LOOP PATTERNS ==="
    
    local log_dir="${BUILD_ROOT:-/tmp/build}/.logs"
    if [[ ! -d "$log_dir" ]]; then
        log_warning "Log directory not found: $log_dir"
        return 1
    fi
    
    # Analyze error patterns
    log_info "Analyzing error patterns in recent logs..."
    local error_analysis=$(find "$log_dir" -name "*.log" -mtime -1 -exec grep -h "ERROR\|WARN" {} \; 2>/dev/null | sort | uniq -c | sort -nr | head -10)
    
    if [[ -n "$error_analysis" ]]; then
        echo "$error_analysis"
        
        # Check for high frequency errors (likely loops)
        if echo "$error_analysis" | head -1 | awk '{print $1}' | grep -q '[1-9][0-9]'; then
            log_warning "High frequency errors detected - possible infinite loop"
            return 1
        fi
    else
        log_info "No error patterns found"
    fi
    
    # Check for recursive function calls
    log_info "Checking for recursive function patterns..."
    local recursive_patterns=$(find "$log_dir" -name "*.log" -mtime -1 -exec grep -h "cleanup\|unmount\|error_handler" {} \; 2>/dev/null | wc -l)
    
    if [[ "$recursive_patterns" -gt 100 ]]; then
        log_warning "High frequency of cleanup/unmount/error_handler calls: $recursive_patterns"
        log_warning "This indicates possible recursive function calls"
        return 1
    fi
    
    log_success "Log analysis complete - no obvious loop patterns"
}

full_reset() {
    log_warning "=== FULL SYSTEM RESET ==="
    
    kill_build_processes
    cleanup_guard_clauses
    
    # Clean up build directory locks
    local build_root="${BUILD_ROOT:-/tmp/build}"
    if [[ -d "$build_root" ]]; then
        log_info "Cleaning up build directory locks and temp files..."
        find "$build_root" -name "*.lock" -delete 2>/dev/null || true
        find "$build_root" -name "*.tmp" -delete 2>/dev/null || true
        
        # Reset checkpoint state
        if [[ -d "$build_root/checkpoints" ]]; then
            echo "manual_reset" > "$build_root/checkpoints/current_module"
        fi
    fi
    
    # Force unmount any stuck mounts
    if command -v fuser >/dev/null 2>&1; then
        log_info "Checking for stuck chroot mounts..."
        if mount | grep -q "$build_root/chroot"; then
            log_info "Force unmounting stuck chroot filesystems..."
            fuser -KILL "$build_root/chroot" 2>/dev/null || true
            umount -lf "$build_root/chroot"/* 2>/dev/null || true
        fi
    fi
    
    log_success "Full system reset complete"
}

show_status() {
    log_info "=== GUARD CLAUSE STATUS ==="
    
    echo "CLEANUP_IN_PROGRESS: ${CLEANUP_IN_PROGRESS:-not set}"
    echo "UNMOUNT_IN_PROGRESS: ${UNMOUNT_IN_PROGRESS:-not set}"
    echo "STAGE_ERROR_HANDLING: ${STAGE_ERROR_HANDLING:-not set}"
    
    local build_procs=$(pgrep -f "build-orchestrator" | wc -l)
    local cleanup_procs=$(pgrep -f "cleanup" | wc -l)
    local chroot_procs=$(pgrep -f "chroot" | wc -l)
    
    echo "Active build-orchestrator processes: $build_procs"
    echo "Active cleanup processes: $cleanup_procs"
    echo "Active chroot processes: $chroot_procs"
    
    if [[ "$build_procs" -gt 1 ]] || [[ "$cleanup_procs" -gt 1 ]]; then
        log_warning "Multiple processes detected - possible infinite loop"
        return 1
    else
        log_success "Process counts normal"
        return 0
    fi
}

# Main execution
case "${1:-help}" in
    detect)     detect_infinite_loops ;;
    kill)       kill_build_processes ;;
    cleanup)    cleanup_guard_clauses ;;
    monitor)    monitor_loops ;;
    analyze)    analyze_logs ;;
    reset)      full_reset ;;
    status)     show_status ;;
    help|--help|-h) show_help ;;
    *)          
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac