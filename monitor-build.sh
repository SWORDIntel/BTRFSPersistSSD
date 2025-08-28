#!/bin/bash
#
# BUILD MONITORING AND AUTO-RESTART SYSTEM
# Monitors build progress and automatically restarts on failures
# Designed to handle Claude session crashes and thermal issues
#

set -euo pipefail

BUILD_ROOT="${BUILD_ROOT:-/mnt/build-ramdisk}"
LOG_DIR="/var/log/tactical-ops"
MONITOR_LOG="/tmp/build-monitor.log"
MAX_RESTARTS=10
RESTART_COUNT=0
STUCK_TIMEOUT=300  # 5 minutes without progress = stuck

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_monitor() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$MONITOR_LOG"
}

check_build_status() {
    # Check if build processes are running
    if pgrep -f "build-orchestrator" > /dev/null; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

check_if_stuck() {
    local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
    if [[ -f "$latest_log" ]]; then
        local last_mod=$(stat -c %Y "$latest_log")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_mod))
        
        if [[ $time_diff -gt $STUCK_TIMEOUT ]]; then
            return 0  # Stuck
        fi
    fi
    return 1  # Not stuck
}

get_build_progress() {
    local progress_file="$BUILD_ROOT/.metrics/progress.txt"
    if [[ -f "$progress_file" ]]; then
        cat "$progress_file" 2>/dev/null || echo "0%"
    else
        echo "0%"
    fi
}

kill_stuck_build() {
    log_monitor "${RED}[KILL]${NC} Killing stuck build processes..."
    sudo pkill -f "build-orchestrator" 2>/dev/null || true
    sudo pkill -f "mmdebstrap" 2>/dev/null || true
    sleep 3
}

restart_build() {
    ((RESTART_COUNT++))
    log_monitor "${YELLOW}[RESTART $RESTART_COUNT/$MAX_RESTARTS]${NC} Starting build..."
    
    # Start build in background with thermal resilience
    nohup sudo -E env BUILD_ROOT="$BUILD_ROOT" ./build-orchestrator.sh build \
        > /tmp/build-output-$RESTART_COUNT.log 2>&1 &
    
    local build_pid=$!
    echo $build_pid > /tmp/build-monitor.pid
    log_monitor "${BLUE}[START]${NC} Build started with PID: $build_pid"
}

monitor_loop() {
    log_monitor "${GREEN}[MONITOR]${NC} Build monitoring started (max $MAX_RESTARTS restarts)"
    
    while [[ $RESTART_COUNT -lt $MAX_RESTARTS ]]; do
        if check_build_status; then
            local progress=$(get_build_progress)
            log_monitor "${BLUE}[PROGRESS]${NC} Build running: $progress"
            
            if check_if_stuck; then
                log_monitor "${YELLOW}[STUCK]${NC} Build appears stuck (no log activity for ${STUCK_TIMEOUT}s)"
                kill_stuck_build
                restart_build
            fi
        else
            # Check if build completed successfully
            if [[ -f "$BUILD_ROOT/ubuntu.iso" ]]; then
                log_monitor "${GREEN}[SUCCESS]${NC} Build completed! ISO created: $BUILD_ROOT/ubuntu.iso"
                break
            else
                log_monitor "${RED}[CRASH]${NC} Build process died, restarting..."
                restart_build
            fi
        fi
        
        sleep 30  # Check every 30 seconds
    done
    
    if [[ $RESTART_COUNT -ge $MAX_RESTARTS ]]; then
        log_monitor "${RED}[FAILED]${NC} Max restarts ($MAX_RESTARTS) reached. Manual intervention required."
        exit 1
    fi
}

# Main execution
case "${1:-monitor}" in
    "start")
        restart_build
        ;;
    "monitor")
        monitor_loop
        ;;
    "status")
        if check_build_status; then
            echo "Build is RUNNING"
            echo "Progress: $(get_build_progress)"
        else
            echo "Build is NOT RUNNING"
        fi
        ;;
    "kill")
        kill_stuck_build
        ;;
    *)
        echo "Usage: $0 [start|monitor|status|kill]"
        echo "  start   - Start build and exit"
        echo "  monitor - Start build monitoring loop (default)"
        echo "  status  - Check current status"
        echo "  kill    - Kill stuck processes"
        exit 1
        ;;
esac