#!/bin/bash
#
# QUICK BUILD RESTART SCRIPT
# For when builds crash due to Claude sessions ending
#

set -euo pipefail

BUILD_ROOT="${BUILD_ROOT:-/mnt/build-ramdisk}"

echo "🔥 RESTARTING BUILD AFTER CRASH 🔥"
echo "Build root: $BUILD_ROOT"

# Kill any stuck processes
echo "Cleaning up stuck processes..."
sudo pkill -f "build-orchestrator" 2>/dev/null || true
sudo pkill -f "mmdebstrap" 2>/dev/null || true

# Check if we have existing progress
if [[ -f "$BUILD_ROOT/.metrics/progress.txt" ]]; then
    echo "Previous progress: $(cat "$BUILD_ROOT/.metrics/progress.txt")"
fi

if [[ -f "$BUILD_ROOT/.metrics/progress.log" ]]; then
    echo "Last completed modules:"
    tail -3 "$BUILD_ROOT/.metrics/progress.log"
fi

echo ""
echo "Starting build with thermal resilience enabled..."
echo "Press Ctrl+C to stop monitoring, build will continue in background"
echo ""

# Start build in background and monitor
exec ./monitor-build.sh monitor