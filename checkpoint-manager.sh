#!/bin/bash
#
# Checkpoint Manager for Build System
# Allows resuming builds from last successful point
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CHECKPOINT_DIR="${BUILD_ROOT:-/dev/shm/build}/.checkpoints"
CHECKPOINT_FILE="$CHECKPOINT_DIR/build.checkpoint"
SKIP_FILE="$CHECKPOINT_DIR/skip_packages.list"
STATE_FILE="$CHECKPOINT_DIR/build.state"

# Ensure checkpoint directory exists
mkdir -p "$CHECKPOINT_DIR"

#=============================================================================
# CHECKPOINT FUNCTIONS
#=============================================================================

create_checkpoint() {
    local module="$1"
    local status="${2:-completed}"
    local timestamp=$(date +%s)
    
    echo "${timestamp}:${module}:${status}" >> "$CHECKPOINT_FILE"
    echo -e "${GREEN}✓ Checkpoint created: $module ($status)${NC}"
    
    # Save current state
    save_state
}

get_last_checkpoint() {
    if [[ -f "$CHECKPOINT_FILE" ]]; then
        tail -1 "$CHECKPOINT_FILE" | cut -d: -f2
    else
        echo "none"
    fi
}

list_checkpoints() {
    echo -e "${BLUE}=== Build Checkpoints ===${NC}"
    if [[ -f "$CHECKPOINT_FILE" ]]; then
        cat "$CHECKPOINT_FILE" | while IFS=: read -r timestamp module status; do
            local date_str=$(date -d "@$timestamp" +"%Y-%m-%d %H:%M:%S")
            printf "%-20s %-30s %s\n" "$date_str" "$module" "$status"
        done
    else
        echo "No checkpoints found"
    fi
}

resume_from_checkpoint() {
    local last_module=$(get_last_checkpoint)
    
    if [[ "$last_module" == "none" ]]; then
        echo -e "${YELLOW}No checkpoint found, starting from beginning${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Resuming from checkpoint: $last_module${NC}"
    echo "$last_module"
    return 0
}

clear_checkpoints() {
    rm -f "$CHECKPOINT_FILE" "$STATE_FILE" "$SKIP_FILE"
    echo -e "${YELLOW}All checkpoints cleared${NC}"
}

save_state() {
    # Save environment variables
    cat > "$STATE_FILE" << EOF
BUILD_ROOT="$BUILD_ROOT"
CHROOT_DIR="${CHROOT_DIR:-$BUILD_ROOT/chroot}"
ISO_DIR="${ISO_DIR:-$BUILD_ROOT/iso}"
DEBIAN_RELEASE="${DEBIAN_RELEASE:-noble}"
BUILD_TYPE="${BUILD_TYPE:-standard}"
TIMESTAMP="$(date -Iseconds)"
EOF
    
    # Save disk usage
    df -h "$BUILD_ROOT" >> "$STATE_FILE" 2>/dev/null || true
    
    # Save package installation progress if exists
    if [[ -f "$BUILD_ROOT/installed-packages.list" ]]; then
        wc -l "$BUILD_ROOT/installed-packages.list" | awk '{print "PACKAGES_INSTALLED="$1}' >> "$STATE_FILE"
    fi
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        echo -e "${GREEN}State loaded from checkpoint${NC}"
        return 0
    fi
    return 1
}

#=============================================================================
# PACKAGE SKIP MANAGEMENT
#=============================================================================

add_skip_package() {
    local package="$1"
    echo "$package" >> "$SKIP_FILE"
    echo -e "${YELLOW}Package marked for skip: $package${NC}"
}

get_skip_packages() {
    if [[ -f "$SKIP_FILE" ]]; then
        cat "$SKIP_FILE"
    fi
}

should_skip_package() {
    local package="$1"
    if [[ -f "$SKIP_FILE" ]] && grep -qx "$package" "$SKIP_FILE"; then
        return 0
    fi
    return 1
}

#=============================================================================
# BUILD RECOVERY
#=============================================================================

recover_stuck_build() {
    echo -e "${YELLOW}=== Build Recovery Mode ===${NC}"
    
    # Find and kill stuck apt/dpkg processes
    echo "Checking for stuck package managers..."
    
    local stuck_pids=$(ps aux | grep -E "(apt-get|dpkg|apt)" | grep -v grep | awk '{print $2}')
    if [[ -n "$stuck_pids" ]]; then
        echo -e "${YELLOW}Found stuck processes, terminating...${NC}"
        for pid in $stuck_pids; do
            sudo kill -9 "$pid" 2>/dev/null || true
        done
        sleep 2
    fi
    
    # Fix dpkg locks
    echo "Clearing package manager locks..."
    sudo rm -f /var/lib/dpkg/lock-frontend
    sudo rm -f /var/lib/dpkg/lock
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/apt/lists/lock
    
    # Configure any half-installed packages
    echo "Attempting to fix partial installations..."
    sudo dpkg --configure -a --force-confold --force-confdef 2>/dev/null || true
    
    # Get the problematic package from dpkg
    local problem_pkg=$(sudo dpkg -l | grep -E "^[^ii]" | awk '{print $2}' | head -1)
    if [[ -n "$problem_pkg" ]]; then
        echo -e "${YELLOW}Problem package detected: $problem_pkg${NC}"
        read -p "Skip this package? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            add_skip_package "$problem_pkg"
            sudo dpkg --remove --force-remove-reinstreq "$problem_pkg" 2>/dev/null || true
        fi
    fi
    
    echo -e "${GREEN}Recovery complete${NC}"
}

#=============================================================================
# MONITORING
#=============================================================================

monitor_build() {
    echo -e "${BLUE}=== Build Monitor ===${NC}"
    
    # Check if build is running
    if pgrep -f "build-orchestrator.sh" > /dev/null; then
        echo -e "${GREEN}✓ Build is running${NC}"
    else
        echo -e "${YELLOW}⚠ No build process detected${NC}"
    fi
    
    # Show current module
    if [[ -f "$CHECKPOINT_DIR/current_module" ]]; then
        echo "Current module: $(cat $CHECKPOINT_DIR/current_module)"
    fi
    
    # Show progress
    list_checkpoints | tail -5
    
    # Show disk usage
    echo -e "\n${BLUE}Disk Usage:${NC}"
    df -h "$BUILD_ROOT" 2>/dev/null || df -h /dev/shm
    
    # Show skip list
    if [[ -f "$SKIP_FILE" ]]; then
        echo -e "\n${YELLOW}Skipped packages:${NC}"
        cat "$SKIP_FILE"
    fi
}

#=============================================================================
# MAIN MENU
#=============================================================================

show_menu() {
    echo -e "${BLUE}=== Checkpoint Manager ===${NC}"
    echo "1. List checkpoints"
    echo "2. Resume from last checkpoint"
    echo "3. Recover stuck build"
    echo "4. Monitor current build"
    echo "5. Add package to skip list"
    echo "6. Clear all checkpoints"
    echo "7. Show build state"
    echo "8. Exit"
    echo
    read -p "Select option: " choice
    
    case $choice in
        1) list_checkpoints ;;
        2) resume_from_checkpoint ;;
        3) recover_stuck_build ;;
        4) monitor_build ;;
        5) 
            read -p "Package name to skip: " pkg
            add_skip_package "$pkg"
            ;;
        6) clear_checkpoints ;;
        7) 
            if [[ -f "$STATE_FILE" ]]; then
                cat "$STATE_FILE"
            else
                echo "No state file found"
            fi
            ;;
        8) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
}

# Handle command line arguments
case "${1:-}" in
    create)
        create_checkpoint "$2" "${3:-completed}"
        ;;
    resume)
        resume_from_checkpoint
        ;;
    recover)
        recover_stuck_build
        ;;
    monitor)
        while true; do
            clear
            monitor_build
            sleep 5
        done
        ;;
    skip)
        add_skip_package "$2"
        ;;
    list)
        list_checkpoints
        ;;
    clear)
        clear_checkpoints
        ;;
    *)
        show_menu
        ;;
esac