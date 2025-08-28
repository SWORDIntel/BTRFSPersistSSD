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
REFRESH_INTERVAL=2  # Real-time update every 2 seconds

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Module execution order for progress calculation
declare -A MODULE_ORDER=(
    [10]="dependency-validation"
    [15]="environment-setup"
    [20]="mmdebootstrap/orchestrator"
    [25]="package-installation"
    [28]="chroot-dependencies"
    [30]="config-apply"
    [35]="zfs-builder"
    [38]="dell-cctk-builder"
    [40]="kernel-compilation"
    [50]="system-configuration"
    [60]="validation"
    [70]="initramfs-generation"
    [80]="iso-assembly"
    [90]="finalization"
)

log_monitor() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$MONITOR_LOG"
}

get_cpu_temperature() {
    # Try multiple temperature sources
    local temp="N/A"
    
    # Try thermal zones (most common)
    if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp_millis=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
        temp="$((temp_millis / 1000))°C"
    # Try coretemp (Intel)
    elif [[ -r /sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input ]]; then
        local temp_file=$(ls /sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)
        if [[ -r "$temp_file" ]]; then
            local temp_millis=$(cat "$temp_file" 2>/dev/null || echo "0")
            temp="$((temp_millis / 1000))°C"
        fi
    # Try k10temp (AMD)
    elif [[ -r /sys/devices/pci*/*/hwmon/hwmon*/temp1_input ]]; then
        local temp_file=$(ls /sys/devices/pci*/*/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)
        if [[ -r "$temp_file" ]]; then
            local temp_millis=$(cat "$temp_file" 2>/dev/null || echo "0")
            temp="$((temp_millis / 1000))°C"
        fi
    # Try lm-sensors via sensors command
    elif command -v sensors >/dev/null 2>&1; then
        temp=$(sensors 2>/dev/null | grep -E '(Core 0|Tctl)' | head -1 | grep -oE '[0-9]+\.[0-9]+°C' || echo "N/A")
    fi
    
    echo "$temp"
}

get_thermal_status() {
    local temp_str=$(get_cpu_temperature)
    local temp_num=$(echo "$temp_str" | grep -oE '[0-9]+' | head -1)
    
    if [[ "$temp_num" =~ ^[0-9]+$ ]]; then
        if [[ $temp_num -ge 85 ]]; then
            echo "${RED}CRITICAL${NC}"
        elif [[ $temp_num -ge 75 ]]; then
            echo "${YELLOW}HIGH${NC}"
        elif [[ $temp_num -ge 60 ]]; then
            echo "${BLUE}WARM${NC}"
        else
            echo "${GREEN}NORMAL${NC}"
        fi
    else
        echo "${CYAN}UNKNOWN${NC}"
    fi
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
    # Check checkpoint files to determine current module
    local checkpoint_dir="$BUILD_ROOT/.checkpoints"
    local current_progress=0
    local current_module="initializing"
    
    if [[ -d "$checkpoint_dir" ]]; then
        # Find the latest checkpoint
        local latest_checkpoint=$(ls -t "$checkpoint_dir"/*.checkpoint 2>/dev/null | head -1)
        if [[ -f "$latest_checkpoint" ]]; then
            local checkpoint_name=$(basename "$latest_checkpoint" .checkpoint)
            
            # Map checkpoint to module progress
            case "$checkpoint_name" in
                "dependency_validation_complete") current_progress=10; current_module="environment-setup" ;;
                "environment_setup_complete") current_progress=15; current_module="mmdebootstrap" ;;
                "mmdebstrap_complete") current_progress=20; current_module="package-installation" ;;
                "package_installation_complete") current_progress=25; current_module="chroot-dependencies" ;;
                "chroot_dependencies_complete") current_progress=28; current_module="config-apply" ;;
                "config_apply_complete") current_progress=30; current_module="zfs-builder" ;;
                "zfs_builder_complete") current_progress=35; current_module="dell-cctk-builder" ;;
                "dell_cctk_complete") current_progress=38; current_module="kernel-compilation" ;;
                "kernel_compilation_complete") current_progress=40; current_module="system-configuration" ;;
                "system_configuration_complete") current_progress=50; current_module="validation" ;;
                "validation_complete") current_progress=60; current_module="initramfs-generation" ;;
                "initramfs_complete") current_progress=70; current_module="iso-assembly" ;;
                "iso_assembly_complete") current_progress=80; current_module="finalization" ;;
                "finalization_complete") current_progress=90; current_module="completed" ;;
                *) current_progress=5; current_module="$checkpoint_name" ;;
            esac
        fi
    fi
    
    # Check if ISO exists (100% complete)
    if [[ -f "$BUILD_ROOT/ubuntu.iso" ]]; then
        current_progress=100
        current_module="completed"
    fi
    
    echo "$current_progress|$current_module"
}

get_build_stats() {
    local start_time_file="$BUILD_ROOT/.build_start_time"
    local current_time=$(date +%s)
    local elapsed="00:00:00"
    local eta="calculating..."
    
    if [[ -f "$start_time_file" ]]; then
        local start_time=$(cat "$start_time_file" 2>/dev/null || echo "$current_time")
        local elapsed_seconds=$((current_time - start_time))
        
        # Format elapsed time
        local hours=$((elapsed_seconds / 3600))
        local minutes=$(((elapsed_seconds % 3600) / 60))
        local seconds=$((elapsed_seconds % 60))
        elapsed=$(printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds")
        
        # Calculate ETA based on progress
        local progress_data=$(get_build_progress)
        local progress=$(echo "$progress_data" | cut -d'|' -f1)
        
        if [[ $progress -gt 0 && $progress -lt 100 ]]; then
            local total_estimated=$((elapsed_seconds * 100 / progress))
            local remaining=$((total_estimated - elapsed_seconds))
            
            if [[ $remaining -gt 0 ]]; then
                local eta_hours=$((remaining / 3600))
                local eta_minutes=$(((remaining % 3600) / 60))
                local eta_seconds=$((remaining % 60))
                eta=$(printf "%02d:%02d:%02d" "$eta_hours" "$eta_minutes" "$eta_seconds")
            else
                eta="soon"
            fi
        elif [[ $progress -eq 100 ]]; then
            eta="completed"
        fi
    fi
    
    echo "$elapsed|$eta"
}

draw_progress_bar() {
    local progress=$1
    local width=50
    local filled=$((progress * width / 100))
    local empty=$((width - filled))
    
    printf "["
    printf "%*s" "$filled" "" | tr ' ' '█'
    printf "%*s" "$empty" "" | tr ' ' '░'
    printf "]"
}

show_real_time_status() {
    # Clear screen and move cursor to top
    clear
    
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                     UBUNTU LIVECD BUILD MONITOR                     ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Get current status
    local is_running=$(check_build_status && echo "true" || echo "false")
    local progress_data=$(get_build_progress)
    local progress=$(echo "$progress_data" | cut -d'|' -f1)
    local current_module=$(echo "$progress_data" | cut -d'|' -f2)
    local stats=$(get_build_stats)
    local elapsed=$(echo "$stats" | cut -d'|' -f1)
    local eta=$(echo "$stats" | cut -d'|' -f2)
    local temperature=$(get_cpu_temperature)
    local thermal_status=$(get_thermal_status)
    
    # Build Status
    if [[ "$is_running" == "true" ]]; then
        echo -e "${GREEN}●${NC} ${BOLD}Status:${NC} ${GREEN}RUNNING${NC}"
    else
        if [[ -f "$BUILD_ROOT/ubuntu.iso" ]]; then
            echo -e "${GREEN}●${NC} ${BOLD}Status:${NC} ${GREEN}COMPLETED${NC}"
        else
            echo -e "${RED}●${NC} ${BOLD}Status:${NC} ${RED}STOPPED${NC}"
        fi
    fi
    
    echo
    
    # Progress Information
    echo -e "${BOLD}Progress: ${CYAN}$progress%${NC}"
    draw_progress_bar "$progress"
    echo -e " ${CYAN}$progress%${NC}"
    echo
    echo -e "${BOLD}Current Module:${NC} ${YELLOW}$current_module${NC}"
    echo -e "${BOLD}Elapsed Time:${NC}   $elapsed"
    echo -e "${BOLD}Estimated ETA:${NC}  $eta"
    echo
    
    # System Information
    echo -e "${BOLD}${MAGENTA}╔═════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${MAGENTA}║                        SYSTEM STATUS                           ║${NC}"
    echo -e "${BOLD}${MAGENTA}╚═════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BOLD}CPU Temperature:${NC} $temperature ($thermal_status)"
    
    # Memory usage
    local memory_info=$(free -h | grep '^Mem:' | awk '{printf "Used: %s / %s (%.1f%%)", $3, $2, ($3/$2)*100}' 2>/dev/null || echo "N/A")
    echo -e "${BOLD}Memory Usage:${NC}    $memory_info"
    
    # Disk usage for build root
    if [[ -d "$BUILD_ROOT" ]]; then
        local disk_info=$(df -h "$BUILD_ROOT" | tail -1 | awk '{printf "Used: %s / %s (%s full)", $3, $2, $5}' 2>/dev/null || echo "N/A")
        echo -e "${BOLD}Build Disk:${NC}      $disk_info"
    fi
    
    # Build root location
    echo -e "${BOLD}Build Location:${NC}  $BUILD_ROOT"
    
    echo
    
    # Recent log entries
    echo -e "${BOLD}${CYAN}╔═════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                         RECENT ACTIVITY                        ║${NC}"
    echo -e "${BOLD}${CYAN}╚═════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Show last few lines from the most recent log
    local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
    if [[ -f "$latest_log" ]]; then
        echo -e "${BOLD}Latest Log:${NC} $(basename "$latest_log")"
        echo
        tail -5 "$latest_log" 2>/dev/null | sed 's/^/  /' || echo "  No recent activity"
    else
        echo "  No log files found"
    fi
    
    echo
    echo -e "${YELLOW}Press Ctrl+C to exit monitoring${NC}"
    echo -e "${CYAN}Updates every $REFRESH_INTERVAL seconds${NC}"
}

kill_stuck_build() {
    log_monitor "${RED}[KILL]${NC} Killing stuck build processes..."
    sudo pkill -f "build-orchestrator" 2>/dev/null || true
    sudo pkill -f "mmdebstrap" 2>/dev/null || true
    sleep 3
}

restart_build() {
    ((RESTART_COUNT++)) || true
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
    
    # Set up signal handlers for clean exit
    trap 'echo; echo "Monitoring stopped."; exit 0' INT TERM
    
    # Record start time if not exists
    local start_time_file="$BUILD_ROOT/.build_start_time"
    if [[ ! -f "$start_time_file" ]]; then
        date +%s > "$start_time_file"
    fi
    
    while [[ $RESTART_COUNT -lt $MAX_RESTARTS ]]; do
        # Show real-time status
        show_real_time_status
        
        # Check build status
        if check_build_status; then
            local progress_data=$(get_build_progress)
            local progress=$(echo "$progress_data" | cut -d'|' -f1)
            
            # Log progress periodically (every 30 seconds)
            local current_minute=$(date +%M)
            if [[ $((current_minute % 1)) -eq 0 ]] && [[ "$(date +%S)" -lt 3 ]]; then
                log_monitor "${BLUE}[PROGRESS]${NC} Build running: $progress%"
            fi
            
            if check_if_stuck; then
                log_monitor "${YELLOW}[STUCK]${NC} Build appears stuck (no log activity for ${STUCK_TIMEOUT}s)"
                kill_stuck_build
                restart_build
            fi
        else
            # Check if build completed successfully
            if [[ -f "$BUILD_ROOT/ubuntu.iso" ]]; then
                log_monitor "${GREEN}[SUCCESS]${NC} Build completed! ISO created: $BUILD_ROOT/ubuntu.iso"
                show_real_time_status  # Final status display
                echo
                echo -e "${GREEN}${BOLD}BUILD COMPLETED SUCCESSFULLY!${NC}"
                echo -e "ISO Location: ${CYAN}$BUILD_ROOT/ubuntu.iso${NC}"
                local iso_size=$(du -h "$BUILD_ROOT/ubuntu.iso" 2>/dev/null | cut -f1 || echo "Unknown")
                echo -e "ISO Size: ${CYAN}$iso_size${NC}"
                break
            else
                log_monitor "${RED}[CRASH]${NC} Build process died, restarting..."
                restart_build
            fi
        fi
        
        sleep $REFRESH_INTERVAL
    done
    
    if [[ $RESTART_COUNT -ge $MAX_RESTARTS ]]; then
        log_monitor "${RED}[FAILED]${NC} Max restarts ($MAX_RESTARTS) reached. Manual intervention required."
        echo
        echo -e "${RED}${BOLD}BUILD FAILED${NC}"
        echo -e "Maximum restart attempts ($MAX_RESTARTS) exceeded."
        echo -e "Check logs in: ${CYAN}$LOG_DIR${NC}"
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
            local progress_data=$(get_build_progress)
            local progress=$(echo "$progress_data" | cut -d'|' -f1)
            local current_module=$(echo "$progress_data" | cut -d'|' -f2)
            local temperature=$(get_cpu_temperature)
            echo "Build is RUNNING"
            echo "Progress: $progress%"
            echo "Current Module: $current_module"
            echo "CPU Temperature: $temperature"
        else
            echo "Build is NOT RUNNING"
            if [[ -f "$BUILD_ROOT/ubuntu.iso" ]]; then
                echo "Status: COMPLETED"
                local iso_size=$(du -h "$BUILD_ROOT/ubuntu.iso" 2>/dev/null | cut -f1 || echo "Unknown")
                echo "ISO Size: $iso_size"
            else
                echo "Status: FAILED or STOPPED"
            fi
        fi
        ;;
    "kill")
        kill_stuck_build
        ;;
    *)
        echo "Usage: $0 [start|monitor|status|kill]"
        echo "  start   - Start build and exit"
        echo "  monitor - Start real-time build monitoring (default)"
        echo "  status  - Check current status with temperature"
        echo "  kill    - Kill stuck processes"
        echo
        echo "Real-time monitoring features:"
        echo "  - Live progress percentage based on module completion"
        echo "  - CPU temperature monitoring with thermal status"
        echo "  - Build time elapsed and ETA calculation"
        echo "  - System resource usage (memory, disk)"
        echo "  - Recent log activity display"
        echo "  - Auto-restart on failures (max $MAX_RESTARTS attempts)"
        exit 1
        ;;
esac