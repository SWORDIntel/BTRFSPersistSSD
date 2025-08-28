#!/bin/bash
#
# Git Cleanup Script - Aggressive cleaning
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Git Repository Cleanup ===${NC}"

# Get initial size
INITIAL_SIZE=$(du -sh .git | cut -f1)
echo "Initial .git size: $INITIAL_SIZE"

# 1. Remove all remotes to prevent accidental large fetches
echo -e "\n${YELLOW}Step 1: Managing remotes...${NC}"
git remote -v
read -p "Remove all remotes? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for remote in $(git remote); do
        git remote remove "$remote"
    done
    echo "Remotes removed"
fi

# 2. Remove large files from history
echo -e "\n${YELLOW}Step 2: Finding large files in history...${NC}"
git rev-list --all --objects | \
    git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \
    awk '/^blob/ {print $3, $4}' | \
    sort -n -r | \
    head -20 | \
    while read size path; do
        size_mb=$((size / 1048576))
        if [ $size_mb -gt 1 ]; then
            echo "Found: $path (${size_mb}MB)"
        fi
    done

read -p "Remove large files from history? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Remove specific large file patterns
    git filter-branch --force --index-filter \
        'git rm --cached --ignore-unmatch *.iso *.img *.squashfs *.deb *.tar.gz *.zip 2>/dev/null || true' \
        --prune-empty --tag-name-filter cat -- --all 2>/dev/null || true
fi

# 3. Clean reflog
echo -e "\n${YELLOW}Step 3: Cleaning reflog...${NC}"
git reflog expire --expire=now --all

# 4. Aggressive garbage collection
echo -e "\n${YELLOW}Step 4: Aggressive garbage collection...${NC}"
git gc --aggressive --prune=now

# 5. Repack
echo -e "\n${YELLOW}Step 5: Repacking objects...${NC}"
git repack -a -d --depth=250 --window=250

# 6. Remove unnecessary files
echo -e "\n${YELLOW}Step 6: Removing unnecessary files...${NC}"
rm -rf .git/refs/original/ 2>/dev/null || true
rm -rf .git/logs/ 2>/dev/null || true

# 7. Clean git LFS if present
if [[ -d .git/lfs ]]; then
    echo -e "\n${YELLOW}Step 7: Cleaning Git LFS...${NC}"
    rm -rf .git/lfs/objects/* 2>/dev/null || true
    git lfs prune
fi

# 8. Final garbage collection
echo -e "\n${YELLOW}Step 8: Final cleanup...${NC}"
git gc --aggressive --prune=all

# Get final size
FINAL_SIZE=$(du -sh .git | cut -f1)

echo -e "\n${GREEN}=== Cleanup Complete ===${NC}"
echo "Initial size: $INITIAL_SIZE"
echo "Final size: $FINAL_SIZE"
echo

# Estimate space saved
INITIAL_KB=$(du -sk .git | cut -f1)
git gc --aggressive --prune=all
FINAL_KB=$(du -sk .git | cut -f1)
SAVED_KB=$((INITIAL_KB - FINAL_KB))
SAVED_MB=$((SAVED_KB / 1024))

if [ $SAVED_MB -gt 0 ]; then
    echo -e "${GREEN}Space saved: ~${SAVED_MB}MB${NC}"
fi

# Add back origin if needed
read -p "Re-add origin remote? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter remote URL: " remote_url
    git remote add origin "$remote_url"
    echo "Remote added: $remote_url"
fi

echo -e "\n${BLUE}Tips to prevent future bloat:${NC}"
echo "• Use .gitignore for build artifacts"
echo "• Build in tmpfs (/dev/shm/build)"
echo "• Run this script periodically"
echo "• Use 'git clean -fdx' to remove untracked files"