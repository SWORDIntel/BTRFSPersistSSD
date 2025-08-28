#!/bin/bash
# common_module_functions.sh - Tactical Support Infrastructure v1.0
# Standardized functions for all scripts in repository

set -eEuo pipefail
IFS=$'\n\t'

# Configuration
SCRIPT_VERSION="${SCRIPT_VERSION:-1.0.0}"
LOG_DIR="${LOG_DIR:-/var/log/tactical-ops}"
STATE_DIR="${STATE_DIR:-/var/lib/tactical-state}"
LOCK_DIR="${LOCK_DIR:-/var/lock}"
CHECKPOINT_DIR="${CHECKPOINT_DIR:-/var/lib/checkpoints}"

# ANSI Colors - Combat Display
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Initialize logging
mkdir -p "$LOG_DIR" "$STATE_DIR" "$CHECKPOINT_DIR"
LOG_FILE="${LOG_FILE:-$LOG_DIR/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/$(basename "$0" .sh).state}"
LOCK_FILE="${LOCK_FILE:-$LOCK_DIR/$(basename "$0" .sh).lock}"

#=============================================================================
# TACTICAL LOGGING SYSTEM
#=============================================================================

log() {
    local level="$1"
    shift
    echo -e "${level}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    log "$CYAN" "INFO: $*"
}

log_success() {
    log "$GREEN" "SUCCESS: $*"
}

log_warning() {
    log "$YELLOW" "WARNING: $*"
}

log_error() {
    log "$RED" "ERROR: $*"
    return 1
}

log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && log "$MAGENTA" "DEBUG: $*"
}

#=============================================================================
# ATOMIC OPERATIONS - CRITICAL SECTION MANAGEMENT
#=============================================================================

acquire_lock() {
    local timeout="${1:-300}"
    local elapsed=0
    
    log_debug "Acquiring lock: $LOCK_FILE"
    
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Failed to acquire lock after ${timeout}s"
            return 1
        fi
        
        sleep 1
        ((elapsed++)) || true
        
        # Check for stale lock
        if [[ $elapsed -eq 30 ]]; then
            local lock_age
            lock_age=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
            local current_time=$(date +%s)
            
            if [[ $((current_time - lock_age)) -gt 600 ]]; then
                log_warning "Removing stale lock (>10 minutes old)"
                rm -rf "$LOCK_FILE"
            fi
        fi
    done
    
    echo "$$" > "$LOCK_FILE/pid"
    log_debug "Lock acquired by PID $$"
    return 0
}

release_lock() {
    if [[ -d "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE/pid" 2>/dev/null || echo "")
        
        if [[ "$lock_pid" == "$$" ]]; then
            rm -rf "$LOCK_FILE"
            log_debug "Lock released by PID $$"
        else
            log_warning "Lock owned by different PID: $lock_pid (current: $$)"
        fi
    fi
}

#=============================================================================
# CHECKPOINT & RECOVERY SYSTEM
#=============================================================================

create_checkpoint() {
    local phase="$1"
    local data="${2:-}"
    local checkpoint_file="$CHECKPOINT_DIR/$(basename "$0" .sh)-$phase.checkpoint"
    
    log_info "Creating checkpoint: $phase"
    
    cat > "$checkpoint_file" << EOF
{
    "phase": "$phase",
    "timestamp": "$(date -Iseconds)",
    "pid": $$,
    "data": "$data",
    "environment": {
        "script": "$0",
        "version": "$SCRIPT_VERSION",
        "user": "$(whoami)",
        "hostname": "$(hostname)"
    }
}
EOF
    
    log_success "Checkpoint created: $phase"
    return 0
}

validate_checkpoint() {
    local phase="$1"
    local checkpoint_file="$CHECKPOINT_DIR/$(basename "$0" .sh)-$phase.checkpoint"
    
    if [[ ! -f "$checkpoint_file" ]]; then
        log_debug "No checkpoint found for phase: $phase"
        return 1
    fi
    
    # Verify checkpoint integrity
    if ! jq . "$checkpoint_file" >/dev/null 2>&1; then
        log_warning "Corrupted checkpoint for phase: $phase"
        return 1
    fi
    
    local checkpoint_age
    checkpoint_age=$(stat -c %Y "$checkpoint_file" 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    local age_hours=$(( (current_time - checkpoint_age) / 3600 ))
    
    if [[ $age_hours -gt 24 ]]; then
        log_warning "Checkpoint older than 24 hours: $phase"
        return 1
    fi
    
    log_info "Valid checkpoint found: $phase (${age_hours}h old)"
    return 0
}

recover_from_checkpoint() {
    local phase="$1"
    
    if validate_checkpoint "$phase"; then
        local checkpoint_file="$CHECKPOINT_DIR/$(basename "$0" .sh)-$phase.checkpoint"
        local checkpoint_data=$(jq -r '.data' "$checkpoint_file" 2>/dev/null || echo "")
        
        log_info "Recovering from checkpoint: $phase"
        echo "$checkpoint_data"
        return 0
    fi
    
    return 1
}

cleanup_checkpoints() {
    local script_name="$(basename "$0" .sh)"
    
    log_info "Cleaning up checkpoints for: $script_name"
    rm -f "$CHECKPOINT_DIR/${script_name}-"*.checkpoint
    log_success "Checkpoints cleaned"
}

#=============================================================================
# STATE MANAGEMENT - OPERATIONAL CONTINUITY
#=============================================================================

save_state() {
    local state_data="$1"
    
    cat > "$STATE_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "pid": $$,
    "state": $state_data
}
EOF
    
    log_debug "State saved to: $STATE_FILE"
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        jq -r '.state' "$STATE_FILE" 2>/dev/null || echo "{}"
    else
        echo "{}"
    fi
}

#=============================================================================
# ERROR HANDLING - CASUALTY MANAGEMENT
#=============================================================================

error_handler() {
    # Prevent recursive error handling
    trap - ERR
    set +e
    
    local line_no="$1"
    local exit_code="${2:-$?}"
    local command="${3:-unknown}"
    
    log_error "Command failed at line $line_no: $command (exit: $exit_code)" 2>/dev/null || echo "ERROR: Command failed at line $line_no" >&2
    
    # Save failure state (safely)
    save_state "{
        \"status\": \"failed\",
        \"line\": $line_no,
        \"exit_code\": $exit_code,
        \"command\": \"$command\"
    }" 2>/dev/null || true
    
    # Cleanup (safely)
    release_lock 2>/dev/null || true
    
    # Simple stack trace without recursion risk
    log_error "Stack trace:" 2>/dev/null || echo "ERROR: Stack trace:" >&2
    local frame=0
    while caller $frame 2>/dev/null; do
        frame=$((frame + 1))
        [[ $frame -gt 10 ]] && break  # Prevent infinite loops
    done | while IFS= read -r line || break; do
        log_error "  $line" 2>/dev/null || echo "  $line" >&2
    done
    
    exit $exit_code
}

# Set global error trap
trap 'error_handler $LINENO $? "$BASH_COMMAND"' ERR

#=============================================================================
# NETWORK RESILIENCE - COMMUNICATIONS
#=============================================================================

retry_with_backoff() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    local max_delay="${3:-60}"
    shift 3
    
    local attempt=1
    local current_delay=$delay
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: $*"
        
        if "$@"; then
            log_success "Command succeeded on attempt $attempt"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warning "Command failed, retrying in ${current_delay}s..."
            sleep "$current_delay"
            current_delay=$((current_delay * 2))
            [[ $current_delay -gt $max_delay ]] && current_delay=$max_delay
        fi
        
        ((attempt++)) || true
    done
    
    log_error "Command failed after $max_attempts attempts"
    return 1
}

#=============================================================================
# VALIDATION FRAMEWORK - TARGET VERIFICATION
#=============================================================================

validate_environment() {
    local requirements=("$@")
    local missing=()
    
    for req in "${requirements[@]}"; do
        case "$req" in
            cmd:*)
                local cmd="${req#cmd:}"
                if ! command -v "$cmd" &>/dev/null; then
                    missing+=("command: $cmd")
                fi
                ;;
            file:*)
                local file="${req#file:}"
                if [[ ! -f "$file" ]]; then
                    missing+=("file: $file")
                fi
                ;;
            dir:*)
                local dir="${req#dir:}"
                if [[ ! -d "$dir" ]]; then
                    missing+=("directory: $dir")
                fi
                ;;
            var:*)
                local var="${req#var:}"
                if [[ -z "${!var:-}" ]]; then
                    missing+=("variable: $var")
                fi
                ;;
        esac
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing requirements:"
        for item in "${missing[@]}"; do
            log_error "  - $item"
        done
        return 1
    fi
    
    log_success "Environment validation passed"
    return 0
}

#=============================================================================
# PERFORMANCE MONITORING - METRICS
#=============================================================================

start_timer() {
    local timer_name="${1:-default}"
    eval "TIMER_${timer_name}=$(date +%s%N)"
    log_debug "Timer started: $timer_name"
}

stop_timer() {
    local timer_name="${1:-default}"
    local start_var="TIMER_${timer_name}"
    
    if [[ -z "${!start_var:-}" ]]; then
        log_warning "Timer not started: $timer_name"
        return 1
    fi
    
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - ${!start_var}) / 1000000 ))
    
    log_info "Timer $timer_name: ${duration}ms"
    unset "$start_var"
    
    echo "$duration"
}

#=============================================================================
# DIRECTORY FUNCTIONS
#=============================================================================

safe_mkdir() {
    local dir="$1"
    local perms="${2:-755}"
    
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" && chmod "$perms" "$dir"
    fi
}

#=============================================================================
# EXPORT ALL FUNCTIONS
#=============================================================================

export -f log log_info log_success log_warning log_error log_debug
export -f acquire_lock release_lock
export -f create_checkpoint validate_checkpoint recover_from_checkpoint cleanup_checkpoints
export -f save_state load_state
export -f error_handler retry_with_backoff
export -f validate_environment
export -f start_timer stop_timer
export -f safe_mkdir
