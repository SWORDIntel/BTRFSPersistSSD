#!/bin/bash
#
# Build Recovery Script
# Recovers stuck builds, skips problematic packages, manages checkpoints
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-/dev/shm/build}"

echo -e "${BLUE}=== Build Recovery System ===${NC}"

#=============================================================================
# RECOVERY FUNCTIONS
#=============================================================================

check_stuck_processes() {
    echo -e "\n${YELLOW}Checking for stuck processes...${NC}"
    
    # Check for stuck apt/dpkg
    local stuck_apt=$(ps aux | grep -E "(apt-get|dpkg|apt)" | grep -v grep | grep -v "$0")
    if [[ -n "$stuck_apt" ]]; then
        echo -e "${RED}Found stuck package manager processes:${NC}"
        echo "$stuck_apt"
        
        read -p "Kill these processes? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$stuck_apt" | awk '{print $2}' | xargs -r sudo kill -9
            echo -e "${GREEN}Processes killed${NC}"
            sleep 2
        fi
    else
        echo -e "${GREEN}No stuck package managers found${NC}"
    fi
    
    # Check for stuck build
    local stuck_build=$(ps aux | grep -E "build-orchestrator|unified-deploy" | grep -v grep | grep -v "$0")
    if [[ -n "$stuck_build" ]]; then
        echo -e "${YELLOW}Found running build process:${NC}"
        echo "$stuck_build"
        
        read -p "Stop the build? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$stuck_build" | awk '{print $2}' | xargs -r sudo kill -9
            echo -e "${GREEN}Build stopped${NC}"
        fi
    fi
}

fix_package_locks() {
    echo -e "\n${YELLOW}Fixing package manager locks...${NC}"
    
    sudo rm -f /var/lib/dpkg/lock-frontend
    sudo rm -f /var/lib/dpkg/lock
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/apt/lists/lock
    
    # Also check chroot if exists
    if [[ -d "$BUILD_ROOT/chroot" ]]; then
        sudo rm -f "$BUILD_ROOT/chroot/var/lib/dpkg/lock-frontend"
        sudo rm -f "$BUILD_ROOT/chroot/var/lib/dpkg/lock"
        sudo rm -f "$BUILD_ROOT/chroot/var/cache/apt/archives/lock"
        sudo rm -f "$BUILD_ROOT/chroot/var/lib/apt/lists/lock"
    fi
    
    echo -e "${GREEN}Locks cleared${NC}"
}

fix_broken_packages() {
    echo -e "\n${YELLOW}Fixing broken packages...${NC}"
    
    # Try to configure partially installed packages
    sudo dpkg --configure -a --force-confold --force-confdef 2>&1 | \
        grep -E "(Errors|dpkg:|Setting up)" || true
    
    # Find problematic packages
    local broken_pkgs=$(dpkg -l | grep -E "^[^ii]" | awk '{print $2}')
    if [[ -n "$broken_pkgs" ]]; then
        echo -e "${RED}Found broken packages:${NC}"
        echo "$broken_pkgs"
        
        for pkg in $broken_pkgs; do
            read -p "Remove $pkg? (y/n/s=skip): " -n 1 -r
            echo
            case $REPLY in
                [Yy])
                    sudo dpkg --remove --force-remove-reinstreq "$pkg" 2>/dev/null || \
                    sudo apt-get remove --purge -y "$pkg" 2>/dev/null || true
                    ;;
                [Ss])
                    echo "$pkg" >> "$SCRIPT_DIR/src/config/problematic-packages.list"
                    echo -e "${YELLOW}Added $pkg to skip list${NC}"
                    ;;
            esac
        done
    else
        echo -e "${GREEN}No broken packages found${NC}"
    fi
    
    # Fix any remaining issues
    sudo apt-get install -f -y 2>/dev/null || true
}

clean_build_artifacts() {
    echo -e "\n${YELLOW}Cleaning build artifacts...${NC}"
    
    # Show current usage
    echo "Current disk usage:"
    df -h "$BUILD_ROOT" 2>/dev/null || df -h /dev/shm || df -h /tmp
    
    read -p "Clean package cache? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt-get clean
        sudo apt-get autoclean
        if [[ -d "$BUILD_ROOT/chroot" ]]; then
            sudo rm -rf "$BUILD_ROOT/chroot/var/cache/apt/archives/"*.deb
        fi
        echo -e "${GREEN}Package cache cleaned${NC}"
    fi
    
    read -p "Clean build logs? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$BUILD_ROOT"/*.log
        rm -rf "$BUILD_ROOT/.logs/"*.log
        echo -e "${GREEN}Logs cleaned${NC}"
    fi
}

show_checkpoint_status() {
    echo -e "\n${BLUE}=== Checkpoint Status ===${NC}"
    
    if [[ -f "$BUILD_ROOT/.checkpoints/build.checkpoint" ]]; then
        echo "Last 5 checkpoints:"
        tail -5 "$BUILD_ROOT/.checkpoints/build.checkpoint" | while IFS=: read -r ts module status; do
            echo "  $(date -d "@$ts" +"%H:%M:%S") - $module ($status)"
        done
    else
        echo "No checkpoints found"
    fi
    
    if [[ -f "$BUILD_ROOT/.checkpoints/completed_modules" ]]; then
        echo -e "\nCompleted modules:"
        cat "$BUILD_ROOT/.checkpoints/completed_modules" | sed 's/^/  ✓ /'
    fi
    
    if [[ -f "$BUILD_ROOT/.checkpoints/skip_packages.list" ]]; then
        echo -e "\nSkipped packages:"
        cat "$BUILD_ROOT/.checkpoints/skip_packages.list" | sed 's/^/  ✗ /'
    fi
}

resume_build() {
    echo -e "\n${CYAN}=== Resume Build ===${NC}"
    
    show_checkpoint_status
    
    read -p "Resume from checkpoint? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Resuming build...${NC}"
        cd "$SCRIPT_DIR"
        
        # Export checkpoint flag
        export RESUME_FROM_CHECKPOINT=1
        
        # Run build with resume
        sudo BUILD_ROOT="$BUILD_ROOT" ./unified-deploy.sh build
    fi
}

clean_git() {
    echo -e "\n${YELLOW}=== Git Cleanup ===${NC}"
    
    local git_size=$(du -sh "$SCRIPT_DIR/.git" 2>/dev/null | cut -f1)
    echo "Current .git size: $git_size"
    
    read -p "Run git cleanup? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$SCRIPT_DIR"
        if [[ -x "./git-cleanup.sh" ]]; then
            ./git-cleanup.sh
        else
            git gc --aggressive --prune=now
            git repack -a -d
        fi
        
        new_size=$(du -sh "$SCRIPT_DIR/.git" | cut -f1)
        echo -e "${GREEN}Git cleaned: $git_size -> $new_size${NC}"
    fi
}

#=============================================================================
# MAIN MENU
#=============================================================================

show_menu() {
    echo -e "\n${CYAN}Recovery Options:${NC}"
    echo "1. Check for stuck processes"
    echo "2. Fix package locks"
    echo "3. Fix broken packages"
    echo "4. Clean build artifacts"
    echo "5. Show checkpoint status"
    echo "6. Resume build from checkpoint"
    echo "7. Clean git repository"
    echo "8. Run full recovery (1-4)"
    echo "9. Exit"
    echo
    read -p "Select option: " choice
    
    case $choice in
        1) check_stuck_processes ;;
        2) fix_package_locks ;;
        3) fix_broken_packages ;;
        4) clean_build_artifacts ;;
        5) show_checkpoint_status ;;
        6) resume_build ;;
        7) clean_git ;;
        8) 
            check_stuck_processes
            fix_package_locks
            fix_broken_packages
            clean_build_artifacts
            echo -e "${GREEN}Full recovery complete${NC}"
            ;;
        9) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
}

# Quick recovery if argument provided
case "${1:-}" in
    quick)
        check_stuck_processes
        fix_package_locks
        fix_broken_packages
        ;;
    resume)
        resume_build
        ;;
    clean)
        clean_build_artifacts
        clean_git
        ;;
    status)
        show_checkpoint_status
        ;;
    *)
        # Interactive menu
        while true; do
            show_menu
            echo
            read -p "Continue? (y/n): " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && break
        done
        ;;
esac