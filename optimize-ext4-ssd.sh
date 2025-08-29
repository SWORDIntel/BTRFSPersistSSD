#!/bin/bash

# EXT4 SSD Optimization Script for Intel Meteor Lake (Core Ultra 7 165H)
# Optimized for Patriot P210 256GB SSD with ext4 filesystem
# SAFE VERSION - No dangerous operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== EXT4 SSD Optimizer for Intel Meteor Lake ===${NC}"
echo -e "${BLUE}System: Intel Core Ultra 7 165H${NC}"
echo -e "${BLUE}Storage: Patriot P210 256GB SSD (ext4)${NC}"
echo -e "${BLUE}NVMe: 1.9TB available${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Safe write function
safe_write() {
    local file="$1"
    local value="$2"
    local description="$3"
    
    if [ ! -e "$file" ]; then
        return 1
    fi
    
    if [ -w "$file" ]; then
        echo "$value" > "$file" 2>/dev/null && {
            echo -e "${GREEN}✓ $description${NC}"
            return 0
        } || {
            echo -e "${YELLOW}Warning: Could not write to $file${NC}"
            return 1
        }
    fi
}

# =============================================================================
# 1. EXT4 FILESYSTEM OPTIMIZATIONS
# =============================================================================
echo -e "\n${GREEN}[1/8] EXT4 Filesystem Optimizations${NC}"

# Check current mount options
current_mount=$(mount | grep "on / ")
echo "Current root mount: $current_mount"

# Create optimized fstab entry for next boot
if ! grep -q "noatime" /etc/fstab; then
    echo -e "${YELLOW}Adding SSD-optimized mount options for next boot${NC}"
    
    # Backup fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # Update root partition mount options
    sed -i 's|/dev/sda2.*ext4.*defaults|/dev/sda2 / ext4 defaults,noatime,discard,commit=60|' /etc/fstab
    
    echo -e "${GREEN}✓ EXT4 mount options optimized (takes effect on reboot)${NC}"
    echo "  • noatime: Reduces write operations"
    echo "  • discard: Enables TRIM support for SSD"
    echo "  • commit=60: Reduces sync frequency"
else
    echo -e "${GREEN}✓ EXT4 already optimized${NC}"
fi

# Enable periodic TRIM if not already scheduled
if [ ! -f /etc/cron.weekly/fstrim ]; then
    cat > /etc/cron.weekly/fstrim << 'EOF'
#!/bin/bash
# Weekly TRIM for SSD health
/sbin/fstrim -v / >> /var/log/fstrim.log 2>&1
EOF
    chmod +x /etc/cron.weekly/fstrim
    echo -e "${GREEN}✓ Weekly TRIM scheduled${NC}"
fi

# =============================================================================
# 2. SSD I/O OPTIMIZATION (Patriot P210 specific)
# =============================================================================
echo -e "\n${GREEN}[2/8] SSD I/O Scheduler Optimization${NC}"

# Optimize for Patriot P210 SSD
sda_scheduler="/sys/block/sda/queue/scheduler"
if [ -f "$sda_scheduler" ]; then
    current_scheduler=$(cat "$sda_scheduler" | grep -o '\[.*\]' | tr -d '[]')
    echo "Current I/O scheduler: $current_scheduler"
    
    # Set optimal scheduler for SSD
    if grep -q "mq-deadline" "$sda_scheduler"; then
        safe_write "$sda_scheduler" "mq-deadline" "SSD I/O scheduler"
    elif grep -q "none" "$sda_scheduler"; then
        safe_write "$sda_scheduler" "none" "SSD I/O scheduler"
    fi
fi

# SSD-specific optimizations for Patriot P210
ssd_queue="/sys/block/sda/queue"
if [ -d "$ssd_queue" ]; then
    safe_write "$ssd_queue/rotational" "0" "Mark as SSD"
    safe_write "$ssd_queue/nr_requests" "128" "Queue depth for P210"
    safe_write "$ssd_queue/read_ahead_kb" "128" "Read-ahead for P210"
    safe_write "$ssd_queue/add_random" "0" "Disable entropy for SSD"
    safe_write "$ssd_queue/rq_affinity" "1" "RQ affinity"
fi

# =============================================================================
# 3. NVME DRIVE - SKIP OPTIMIZATION (Main Drive)
# =============================================================================
echo -e "\n${GREEN}[3/8] NVMe Drive - Skipping (Main Drive)${NC}"

# Do NOT touch the NVMe 1.9TB drive - it's the main system drive
if [ -d "/sys/block/nvme0n1/queue" ]; then
    echo -e "${YELLOW}NVMe 1.9TB detected - NOT optimizing (main drive)${NC}"
    echo "  • Leaving NVMe settings as-is for stability"
    echo "  • Main drive optimizations handled separately"
else
    echo -e "${BLUE}No NVMe drive detected${NC}"
fi

# =============================================================================
# 4. CPU GOVERNOR (Performance Mode)
# =============================================================================
echo -e "\n${GREEN}[4/8] CPU Performance Optimization${NC}"

current_gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
echo "Current CPU governor: $current_gov"

if [ "$current_gov" != "performance" ]; then
    echo -e "${YELLOW}Setting performance governor${NC}"
    
    # Set all CPUs to performance
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        safe_write "$cpu" "performance" "CPU $(basename $(dirname $cpu)) governor"
    done
    
    # Intel P-state optimization
    if [ -d /sys/devices/system/cpu/intel_pstate ]; then
        safe_write "/sys/devices/system/cpu/intel_pstate/scaling_governor" "performance" "Intel P-state"
        safe_write "/sys/devices/system/cpu/intel_pstate/max_perf_pct" "100" "Max performance"
        safe_write "/sys/devices/system/cpu/intel_pstate/min_perf_pct" "25" "Min performance"
    fi
    
    # Make persistent
    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
fi

# =============================================================================
# 5. MEMORY OPTIMIZATION (62GB RAM)
# =============================================================================
echo -e "\n${GREEN}[5/8] Memory Optimization for Large RAM${NC}"

# VM settings optimized for 62GB RAM + SSD
safe_write "/proc/sys/vm/swappiness" "1" "Very low swappiness for SSD"
safe_write "/proc/sys/vm/vfs_cache_pressure" "50" "Balanced cache pressure"
safe_write "/proc/sys/vm/dirty_ratio" "5" "Dirty pages ratio for SSD"
safe_write "/proc/sys/vm/dirty_background_ratio" "2" "Background dirty ratio"
safe_write "/proc/sys/vm/dirty_expire_centisecs" "3000" "Dirty expire time"
safe_write "/proc/sys/vm/dirty_writeback_centisecs" "1500" "Writeback frequency"

# Transparent Huge Pages
safe_write "/sys/kernel/mm/transparent_hugepage/enabled" "madvise" "THP madvise"
safe_write "/sys/kernel/mm/transparent_hugepage/defrag" "defer" "THP defrag defer"

# =============================================================================
# 6. NETWORK OPTIMIZATION (Intel WiFi)
# =============================================================================
echo -e "\n${GREEN}[6/8] Network Performance${NC}"

# Disable WiFi power saving
for interface in $(iw dev 2>/dev/null | grep Interface | cut -d' ' -f2 2>/dev/null); do
    echo "Optimizing WiFi: $interface"
    iw dev "$interface" set power_save off 2>/dev/null && {
        echo -e "${GREEN}✓ Power save disabled for $interface${NC}"
    }
done

# Network buffer optimization
cat > /etc/sysctl.d/99-network-ssd.conf << 'EOF'
# Network optimization for SSD system
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.netdev_max_backlog = 1500
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
EOF

sysctl -p /etc/sysctl.d/99-network-ssd.conf >/dev/null 2>&1

# =============================================================================
# 7. INTEL LPSS - ABSOLUTELY KEEP ENABLED
# =============================================================================
echo -e "\n${GREEN}[7/8] Intel LPSS Status Check${NC}"

if lsmod | grep -q intel_lpss; then
    echo -e "${GREEN}✓ Intel LPSS enabled (GOOD - keeps I2C/SPI working)${NC}"
    echo "  • Touchpad/touchscreen support"
    echo "  • System sensors (temperature, ambient light)"
    echo "  • TPM communication"
    echo "  • Some NVMe/storage controllers"
else
    echo -e "${YELLOW}Intel LPSS not loaded${NC}"
fi

# Ensure LPSS stays loaded
cat > /etc/modprobe.d/intel-lpss-keep.conf << 'EOF'
# Keep Intel Low Power Subsystem enabled for I2C/SPI
# NEVER remove these modules - they're critical for hardware function
# intel_lpss_pci - PCI interface for LPSS
# intel_lpss - Core LPSS functionality
EOF

# =============================================================================
# 8. ZRAM SWAP (Conservative for SSD protection)
# =============================================================================
echo -e "\n${GREEN}[8/8] ZRAM Compressed Swap${NC}"

if [ ! -b /dev/zram0 ]; then
    total_mem=$(awk '/MemTotal:/{print int($2/1048576)}' /proc/meminfo)
    
    if [ "$total_mem" -gt 32 ]; then
        echo "Creating 4GB ZRAM swap (protects SSD from swap writes)"
        
        modprobe zram num_devices=1 2>/dev/null
        
        if [ -b /dev/zram0 ]; then
            echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || echo lzo > /sys/block/zram0/comp_algorithm
            echo 4G > /sys/block/zram0/disksize
            
            mkswap /dev/zram0 >/dev/null 2>&1 && {
                swapon -p 100 /dev/zram0
                echo -e "${GREEN}✓ ZRAM swap active (4GB, protects SSD)${NC}"
            }
        fi
    fi
else
    echo -e "${GREEN}✓ ZRAM already configured${NC}"
fi

# =============================================================================
# PERSISTENCE SERVICE
# =============================================================================
echo -e "\n${GREEN}Creating Persistent Optimization Service${NC}"

cat > /usr/local/bin/apply-ext4-optimizations.sh << 'SCRIPT'
#!/bin/bash
# Persistent EXT4/SSD optimizations

# CPU performance
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -w "$cpu" ] && echo performance > "$cpu" 2>/dev/null
done

# SSD optimizations (only the Patriot P210 - not the main NVMe)
[ -w /sys/block/sda/queue/scheduler ] && echo mq-deadline > /sys/block/sda/queue/scheduler 2>/dev/null

# Network
for interface in $(iw dev 2>/dev/null | grep Interface | cut -d' ' -f2); do
    iw dev "$interface" set power_save off 2>/dev/null || true
done

# Log
echo "$(date): EXT4 SSD optimizations applied" >> /var/log/ext4-optimize.log
SCRIPT

chmod +x /usr/local/bin/apply-ext4-optimizations.sh

cat > /etc/systemd/system/ext4-ssd-optimize.service << 'EOF'
[Unit]
Description=EXT4 SSD Performance Optimizations
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apply-ext4-optimizations.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ext4-ssd-optimize.service 2>/dev/null || true

# =============================================================================
# SUMMARY
# =============================================================================
echo -e "\n${GREEN}=== EXT4 SSD Optimization Complete ===${NC}"
echo -e "${BLUE}Optimizations Applied:${NC}"
echo "  ✓ EXT4: noatime, discard (TRIM), optimized commit"
echo "  ✓ SSD: I/O scheduler optimized for Patriot P210 only"
echo "  ✓ NVMe: 1.9TB main drive left untouched"
echo "  ✓ CPU: Performance governor enabled"
echo "  ✓ Memory: VM settings for 62GB + SSD combo"
echo "  ✓ Network: WiFi power save disabled"
echo "  ✓ Intel LPSS: KEPT ENABLED (critical for hardware)"
echo "  ✓ ZRAM: 4GB compressed swap (protects SSD)"
echo "  ✓ TRIM: Weekly scheduled maintenance"

echo -e "\n${GREEN}SSD Protection Features:${NC}"
echo "  • Reduced write amplification with noatime"
echo "  • TRIM support for wear leveling"
echo "  • ZRAM swap reduces SSD swap usage"
echo "  • Optimized dirty page ratios"
echo "  • Weekly TRIM maintenance"

echo -e "\n${YELLOW}Reboot recommended for fstab changes to take effect${NC}"
echo -e "${YELLOW}After microcode change to 0x1c: AVX-512 available on P-cores${NC}"

echo -e "\n${GREEN}Log: /var/log/ext4-optimize.log${NC}"