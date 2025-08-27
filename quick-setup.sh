#!/bin/bash
#
# QUICK SETUP SCRIPT
# Rapidly deploys existing build system scripts
#

set -euo pipefail

# Check root
[[ $EUID -ne 0 ]] && { echo "Run as root: sudo $0"; exit 1; }

echo "=== QUICK BUILD SYSTEM SETUP ==="

# Create directory structure
echo "Creating directories..."
mkdir -p src/modules

# Make all scripts executable
echo "Setting permissions..."
chmod +x *.sh 2>/dev/null || true
chmod +x src/modules/*.sh 2>/dev/null || true

# Quick validation
echo ""
echo "Checking core files..."
for file in common_module_functions.sh install_all_dependencies.sh build-orchestrator.sh; do
    if [[ -f "$file" ]]; then
        echo "✓ $file"
    else
        echo "✗ Missing: $file"
    fi
done

# Create simple launcher
cat > run-build.sh << 'EOF'
#!/bin/bash
# Quick build launcher
sudo ./build-orchestrator.sh build "$@"
EOF
chmod +x run-build.sh

echo ""
echo "=== SETUP COMPLETE ==="
echo ""
echo "To start a build:"
echo "  sudo ./run-build.sh"
echo ""
echo "To validate only:"
echo "  sudo ./build-orchestrator.sh validate"