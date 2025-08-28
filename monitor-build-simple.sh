#!/bin/bash
#
# Simple Build Monitor
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BUILD_ROOT="${BUILD_ROOT:-/tmp/build}"

show_status() {
    clear
    echo -e "${BLUE}=== BUILD MONITOR ===${NC}"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Current module/phase
    if [[ -f "$BUILD_ROOT/.build_state" ]]; then
        echo -e "${GREEN}Current Status:${NC}"
        grep "current_module\|current_phase" "$BUILD_ROOT/.build_state" | sed 's/=/ = /'
        echo ""
    fi
    
    # Chroot size
    if [[ -d "$BUILD_ROOT/chroot" ]]; then
        echo -e "${GREEN}Chroot Size:${NC} $(du -sh "$BUILD_ROOT/chroot" 2>/dev/null | cut -f1)"
    fi
    
    # Tmpfs usage
    echo -e "${GREEN}Tmpfs Usage:${NC}"
    df -h "$BUILD_ROOT" | tail -1 | awk '{print "Used: "$3" of "$2" ("$5")"}'
    echo ""
    
    # Running processes
    echo -e "${GREEN}Active Processes:${NC}"
    ps aux | grep -E "build-orchestrator|mmdebstrap|dpkg|apt-get|package-installation" | grep -v grep | head -5 | while read line; do
        echo "  $(echo "$line" | awk '{print $11}' | xargs basename)"
    done
    
    # Recent log entries
    echo ""
    echo -e "${GREEN}Recent Activity:${NC}"
    if ls $BUILD_ROOT/build-*.log >/dev/null 2>&1; then
        tail -5 $(ls -t $BUILD_ROOT/build-*.log | head -1) | sed 's/^/  /'
    fi
    
    # Checkpoints
    echo ""
    echo -e "${GREEN}Checkpoints:${NC} $(ls -1 $BUILD_ROOT/.checkpoints 2>/dev/null | wc -l) saved"
}

# Continuous monitoring
if [[ "$1" == "watch" ]]; then
    while true; do
        show_status
        sleep 5
    done
else
    show_status
fi