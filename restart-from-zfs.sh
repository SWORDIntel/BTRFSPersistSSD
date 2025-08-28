#!/bin/bash
# Quick restart script to skip bootstrap and go straight to ZFS building
# Use this when mmdebstrap completed successfully but build crashed later

set -euo pipefail

BUILD_ROOT="${BUILD_ROOT:-/mnt/build-ramdisk}"

echo "=== RESTARTING FROM ZFS BUILDER (35%) ==="
echo "Build root: $BUILD_ROOT"

# Check if chroot exists
if [[ ! -d "$BUILD_ROOT/chroot" ]]; then
    echo "ERROR: Chroot not found at $BUILD_ROOT/chroot"
    echo "You need to run full build first"
    exit 1
fi

# Kill any existing build
echo "Killing existing build processes..."
sudo pkill -f build-orchestrator || true
sudo pkill -f "bash.*modules" || true

# Start with continue flag to resume from checkpoint
echo "Starting build with --continue flag..."
sudo BUILD_ROOT="$BUILD_ROOT" ./build-orchestrator.sh build --continue

echo "Build restarted with checkpoint recovery"