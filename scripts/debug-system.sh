#!/bin/bash
#
# ARCH System Debugger - Comprehensive Hardware/Driver Diagnostics
# Diagnoses: VMD, NVIDIA drivers, Thunderbolt/DisplayPort issues
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/logs"
DEBUG_LOG="${LOG_DIR}/system-debug-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[DEBUG]${NC} $1" | tee -a "$DEBUG_LOG"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$DEBUG_LOG"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$DEBUG_LOG"; }
info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$DEBUG_LOG"; }
header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}" | tee -a "$DEBUG_LOG"
    echo -e "${CYAN}  $1${NC}" | tee -a "$DEBUG_LOG"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n" | tee -a "$DEBUG_LOG"
}

mkdir -p "$LOG_DIR"

# ============================================================================
# System Overview
# ============================================================================
debug_system_overview() {
    header "System Overview"

    log "Kernel version:"
    uname -a | tee -a "$DEBUG_LOG"

    log ""
    log "Distribution:"
    cat /etc/os-release | grep -E "^(NAME|VERSION)" | tee -a "$DEBUG_LOG"

    log ""
    log "Installed kernels:"
    ls -lh /boot/vmlinuz-* 2>/dev/null | tee -a "$DEBUG_LOG" || warn "No kernels found in /boot"

    log ""
    log "Current boot entry:"
    if command -v efibootmgr &>/dev/null; then
        efibootmgr -v | grep -E "BootCurrent|Boot[0-9].*Linux" | tee -a "$DEBUG_LOG"
    else
        warn "efibootmgr not available"
    fi
}

# ============================================================================
# VMD (Volume Management Device) Diagnostics
# ============================================================================
debug_vmd() {
    header "VMD (Intel Volume Management Device) Diagnostics"

    local vmd_issues=0

    # Check if VMD is enabled in BIOS
    log "Checking VMD device presence..."
    if lspci | grep -i "volume management device"; then
        log "${GREEN}✓${NC} VMD device detected in lspci"
        lspci | grep -i "volume management device" | tee -a "$DEBUG_LOG"
    else
        error "✗ VMD device NOT found - may be disabled in BIOS"
        ((vmd_issues++))
    fi

    # Check kernel config
    log ""
    log "Checking kernel VMD support..."
    local kernel_version=$(uname -r)
    local config_file="/boot/config-${kernel_version}"

    if [ -f "$config_file" ]; then
        if grep -q "CONFIG_VMD=y" "$config_file"; then
            log "${GREEN}✓${NC} CONFIG_VMD=y (built-in)"
        elif grep -q "CONFIG_VMD=m" "$config_file"; then
            log "${YELLOW}⚠${NC} CONFIG_VMD=m (module)"
            # Check if module is loaded
            if lsmod | grep -q vmd; then
                log "${GREEN}✓${NC} vmd module is loaded"
            else
                error "✗ vmd module NOT loaded"
                info "Try: sudo modprobe vmd"
                ((vmd_issues++))
            fi
        else
            error "✗ CONFIG_VMD not enabled in kernel"
            ((vmd_issues++))
        fi
    else
        warn "Kernel config file not found: $config_file"
    fi

    # Check loaded module
    log ""
    log "Checking VMD module status..."
    if lsmod | grep -q vmd; then
        log "${GREEN}✓${NC} vmd module loaded:"
        lsmod | grep vmd | tee -a "$DEBUG_LOG"
    else
        warn "vmd module not loaded"
    fi

    # Check dmesg for VMD messages
    log ""
    log "VMD kernel messages:"
    dmesg | grep -i vmd | tail -20 | tee -a "$DEBUG_LOG" || info "No VMD messages in dmesg"

    # Check NVMe devices under VMD
    log ""
    log "NVMe devices (may be under VMD domain):"
    if command -v nvme &>/dev/null; then
        nvme list | tee -a "$DEBUG_LOG"
    else
        lsblk -o NAME,SIZE,MODEL,TRAN | grep nvme | tee -a "$DEBUG_LOG" || info "No NVMe devices visible"
    fi

    # VMD-specific PCI domain
    log ""
    log "Checking PCI domains (VMD creates 10000:XX:XX.X):"
    lspci | grep -E "^(0000:|1[0-9]{4}:)" | head -20 | tee -a "$DEBUG_LOG"

    # Summary
    log ""
    if [ $vmd_issues -eq 0 ]; then
        log "${GREEN}VMD appears to be working correctly${NC}"
    else
        error "${RED}VMD has $vmd_issues issue(s) - see above${NC}"
        info "To fix VMD issues:"
        info "  1. Enable VMD in BIOS/UEFI settings"
        info "  2. Rebuild kernel with CONFIG_VMD=y"
        info "  3. Run: cd $PROJECT_ROOT && grep -i vmd config/kernel-config-fragment.txt"
    fi
}

# ============================================================================
# NVIDIA Driver Diagnostics
# ============================================================================
debug_nvidia() {
    header "NVIDIA Driver Diagnostics"

    local nvidia_issues=0

    # Check if NVIDIA GPU exists
    log "Checking for NVIDIA GPU..."
    if lspci | grep -i nvidia | grep -i vga; then
        log "${GREEN}✓${NC} NVIDIA GPU detected:"
        lspci | grep -i nvidia | grep -i vga | tee -a "$DEBUG_LOG"
    else
        error "✗ No NVIDIA GPU found"
        ((nvidia_issues++))
    fi

    # Check nvidia-smi
    log ""
    log "Checking nvidia-smi..."
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            log "${GREEN}✓${NC} nvidia-smi working:"
            nvidia-smi | tee -a "$DEBUG_LOG"
        else
            error "✗ nvidia-smi failed:"
            nvidia-smi 2>&1 | tee -a "$DEBUG_LOG" || true
            ((nvidia_issues++))
        fi
    else
        error "✗ nvidia-smi not found"
        ((nvidia_issues++))
    fi

    # Check NVIDIA kernel modules
    log ""
    log "Checking NVIDIA kernel modules..."
    if lsmod | grep -E "^nvidia"; then
        log "${GREEN}✓${NC} NVIDIA modules loaded:"
        lsmod | grep -E "^nvidia" | tee -a "$DEBUG_LOG"
    else
        error "✗ No NVIDIA modules loaded"
        ((nvidia_issues++))
    fi

    # Check for nouveau (conflicts with nvidia)
    log ""
    log "Checking for nouveau driver (should be disabled)..."
    if lsmod | grep -q nouveau; then
        error "✗ nouveau driver is loaded (conflicts with NVIDIA)"
        info "Blacklist nouveau: /etc/modprobe.d/blacklist-nouveau.conf"
        ((nvidia_issues++))
    else
        log "${GREEN}✓${NC} nouveau is not loaded"
    fi

    # Check NVIDIA driver version
    log ""
    log "NVIDIA driver info:"
    if [ -f /proc/driver/nvidia/version ]; then
        log "${GREEN}✓${NC} Driver version:"
        cat /proc/driver/nvidia/version | tee -a "$DEBUG_LOG"
    else
        warn "/proc/driver/nvidia/version not found"
    fi

    # Check kernel headers match
    log ""
    log "Checking kernel headers for DKMS..."
    local kernel_ver=$(uname -r)
    if [ -d "/usr/lib/modules/${kernel_ver}/build" ]; then
        log "${GREEN}✓${NC} Kernel headers installed for $kernel_ver"
    else
        error "✗ Kernel headers missing for $kernel_ver"
        info "Install with: sudo pacman -S linux-headers"
        ((nvidia_issues++))
    fi

    # Check DKMS status
    log ""
    log "DKMS module status:"
    if command -v dkms &>/dev/null; then
        dkms status | tee -a "$DEBUG_LOG" || info "No DKMS modules installed"
    else
        warn "DKMS not installed"
    fi

    # Check modprobe.d configs
    log ""
    log "NVIDIA modprobe configurations:"
    if [ -d /etc/modprobe.d ]; then
        ls -la /etc/modprobe.d/*nvidia* /etc/modprobe.d/*nouveau* 2>/dev/null | tee -a "$DEBUG_LOG" || info "No nvidia/nouveau configs"
    fi

    # Check dmesg for NVIDIA errors
    log ""
    log "NVIDIA kernel messages (last 30 lines):"
    dmesg | grep -i nvidia | tail -30 | tee -a "$DEBUG_LOG" || info "No NVIDIA messages in dmesg"

    # Check Xorg log
    log ""
    log "Checking Xorg log for NVIDIA..."
    if [ -f /var/log/Xorg.0.log ]; then
        grep -i nvidia /var/log/Xorg.0.log | tail -20 | tee -a "$DEBUG_LOG" || info "No NVIDIA entries in Xorg log"
    fi

    # Summary
    log ""
    if [ $nvidia_issues -eq 0 ]; then
        log "${GREEN}NVIDIA driver appears to be working correctly${NC}"
    else
        error "${RED}NVIDIA driver has $nvidia_issues issue(s) - see above${NC}"
        info "To fix NVIDIA issues:"
        info "  1. Ensure kernel headers match: sudo pacman -S linux-headers"
        info "  2. Reinstall NVIDIA driver: sudo pacman -S nvidia-dkms"
        info "  3. Rebuild DKMS modules: sudo dkms autoinstall"
        info "  4. Blacklist nouveau: echo 'blacklist nouveau' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf"
        info "  5. Regenerate initramfs: sudo mkinitcpio -P"
        info "  6. Reboot"
    fi
}

# ============================================================================
# Thunderbolt / DisplayPort Diagnostics
# ============================================================================
debug_thunderbolt_displayport() {
    header "Thunderbolt 5 / DisplayPort Diagnostics"

    local tb_issues=0

    # Check Thunderbolt devices
    log "Checking Thunderbolt devices with boltctl..."
    if command -v boltctl &>/dev/null; then
        log "Thunderbolt devices:"
        boltctl list | tee -a "$DEBUG_LOG"

        log ""
        log "Detailed device info:"
        boltctl list --verbose | tee -a "$DEBUG_LOG"
    else
        error "✗ boltctl not found"
        info "Install with: sudo pacman -S bolt"
        ((tb_issues++))
    fi

    # Check thunderbolt service
    log ""
    log "Checking bolt service..."
    if systemctl is-active --quiet bolt; then
        log "${GREEN}✓${NC} bolt service is active"
    else
        warn "bolt service not active"
        info "Start with: sudo systemctl start bolt && sudo systemctl enable bolt"
    fi

    # Check USB4/Thunderbolt kernel modules
    log ""
    log "Checking Thunderbolt kernel modules..."
    if lsmod | grep -E "^thunderbolt|^usb4"; then
        log "${GREEN}✓${NC} Thunderbolt modules loaded:"
        lsmod | grep -E "^thunderbolt|^usb4" | tee -a "$DEBUG_LOG"
    else
        error "✗ No Thunderbolt/USB4 modules loaded"
        ((tb_issues++))
    fi

    # Check Thunderbolt devices in sysfs
    log ""
    log "Thunderbolt devices in sysfs:"
    if [ -d /sys/bus/thunderbolt/devices ]; then
        for dev in /sys/bus/thunderbolt/devices/*; do
            if [ -d "$dev" ]; then
                local dev_name=$(basename "$dev")
                local dev_info=""
                [ -f "$dev/device_name" ] && dev_info=$(cat "$dev/device_name" 2>/dev/null)
                log "  $dev_name: $dev_info"
            fi
        done
    else
        warn "/sys/bus/thunderbolt/devices not found"
    fi

    # Check DisplayPort detection
    log ""
    log "Checking connected displays..."
    if [ -d /sys/class/drm ]; then
        log "DRM connectors:"
        for connector in /sys/class/drm/card*-*/status; do
            if [ -f "$connector" ]; then
                local status=$(cat "$connector")
                local name=$(basename $(dirname "$connector"))
                if [ "$status" = "connected" ]; then
                    log "  ${GREEN}✓${NC} $name - connected"

                    # Get EDID info
                    local edid_path="$(dirname $connector)/edid"
                    if [ -f "$edid_path" ] && command -v edid-decode &>/dev/null; then
                        log "    Monitor info:"
                        edid-decode "$edid_path" 2>/dev/null | grep -E "Monitor name|Manufacturer" | sed 's/^/    /' | tee -a "$DEBUG_LOG"
                    fi

                    # Get available modes
                    local modes_path="$(dirname $connector)/modes"
                    if [ -f "$modes_path" ]; then
                        log "    Available modes:"
                        head -5 "$modes_path" | sed 's/^/      /' | tee -a "$DEBUG_LOG"
                    fi
                else
                    info "  ○ $name - $status"
                fi
            fi
        done
    else
        error "✗ /sys/class/drm not found"
        ((tb_issues++))
    fi

    # Check xrandr output
    log ""
    log "XRandR display configuration:"
    if command -v xrandr &>/dev/null && [ -n "${DISPLAY:-}" ]; then
        xrandr --query | tee -a "$DEBUG_LOG"
    else
        warn "xrandr not available or no X11 session"
    fi

    # Check for DisplayPort Alt Mode
    log ""
    log "Checking DisplayPort Alt Mode support..."
    if [ -d /sys/class/typec ]; then
        for port in /sys/class/typec/port*; do
            if [ -d "$port" ]; then
                local port_name=$(basename "$port")
                log "  $port_name:"
                [ -f "$port/data_role" ] && log "    Data role: $(cat $port/data_role 2>/dev/null)"
                [ -f "$port/power_role" ] && log "    Power role: $(cat $port/power_role 2>/dev/null)"

                # Check for DP alt modes
                for mode in $port/port*-partner/port*-partner.*/mode; do
                    if [ -f "$mode" ]; then
                        log "    Alt mode: $(cat $mode 2>/dev/null)"
                    fi
                done
            fi
        done
    else
        info "USB Type-C information not available"
    fi

    # Check dmesg for Thunderbolt/DP messages
    log ""
    log "Thunderbolt/DisplayPort kernel messages (last 30):"
    dmesg | grep -iE "thunderbolt|usb4|displayport|dp.*alt.*mode" | tail -30 | tee -a "$DEBUG_LOG" || info "No TB/DP messages"

    # Check Razer dock specifically
    log ""
    log "Checking for Razer Thunderbolt 5 Dock..."
    if lsusb | grep -i razer; then
        log "${GREEN}✓${NC} Razer device detected:"
        lsusb | grep -i razer | tee -a "$DEBUG_LOG"
    else
        warn "No Razer device found in lsusb"
    fi

    if lspci | grep -i razer; then
        log "${GREEN}✓${NC} Razer PCIe device:"
        lspci | grep -i razer | tee -a "$DEBUG_LOG"
    fi

    # Summary
    log ""
    if [ $tb_issues -eq 0 ]; then
        log "${GREEN}Thunderbolt/DisplayPort appears to be working${NC}"
    else
        error "${RED}Thunderbolt/DisplayPort has $tb_issues issue(s) - see above${NC}"
        info "To fix Thunderbolt/DisplayPort issues:"
        info "  1. Authorize dock: sudo boltctl authorize <device-uuid>"
        info "  2. Check USB4/TB modules: sudo modprobe thunderbolt usb4"
        info "  3. Enable bolt service: sudo systemctl enable --now bolt"
        info "  4. Check physical connection and try different ports"
        info "  5. Update dock firmware via Windows if available"
        info "  6. Run monitor setup: bash $PROJECT_ROOT/scripts/setup-monitor.sh"
    fi
}

# ============================================================================
# Kernel Configuration Check
# ============================================================================
debug_kernel_config() {
    header "Kernel Configuration Analysis"

    local kernel_ver=$(uname -r)
    local config_file="/boot/config-${kernel_ver}"

    if [ ! -f "$config_file" ]; then
        config_file="/proc/config.gz"
        if [ -f "$config_file" ]; then
            log "Using /proc/config.gz"
        else
            warn "Kernel config not available"
            return
        fi
    fi

    log "Checking critical kernel options for this system..."

    local critical_options=(
        "CONFIG_VMD"
        "CONFIG_THUNDERBOLT"
        "CONFIG_USB4"
        "CONFIG_USB4_DMA_TEST"
        "CONFIG_DRM"
        "CONFIG_DRM_NVIDIA"
        "CONFIG_NOUVEAU"
        "CONFIG_FB_EFI"
        "CONFIG_X86_INTEL_LPSS"
        "CONFIG_INTEL_MEI"
        "CONFIG_TYPEC"
        "CONFIG_TYPEC_DP_ALTMODE"
    )

    for opt in "${critical_options[@]}"; do
        if [ -f "/proc/config.gz" ]; then
            local value=$(zcat /proc/config.gz 2>/dev/null | grep "^${opt}=" || echo "not set")
        else
            local value=$(grep "^${opt}=" "$config_file" 2>/dev/null || echo "not set")
        fi

        if [[ "$value" == *"=y"* ]]; then
            log "${GREEN}✓${NC} $opt=y (built-in)"
        elif [[ "$value" == *"=m"* ]]; then
            log "${YELLOW}⚠${NC} $opt=m (module)"
        else
            warn "$opt is not set"
        fi
    done
}

# ============================================================================
# Generate Fix Script
# ============================================================================
generate_fix_script() {
    header "Generating Fix Script"

    local fix_script="${PROJECT_ROOT}/scripts/apply-fixes.sh"

    cat > "$fix_script" << 'FIXEOF'
#!/bin/bash
#
# Auto-generated fix script based on debug analysis
#

set -euo pipefail

echo "Applying fixes for detected issues..."

# Fix 1: Ensure NVIDIA driver and DKMS
if ! nvidia-smi &>/dev/null; then
    echo "Installing/reinstalling NVIDIA driver..."
    sudo pacman -S --needed nvidia-dkms nvidia-utils
    sudo dkms autoinstall
fi

# Fix 2: Blacklist nouveau
if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
    echo "Blacklisting nouveau driver..."
    echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
    sudo mkinitcpio -P
fi

# Fix 3: Enable bolt service
if ! systemctl is-active --quiet bolt; then
    echo "Enabling Thunderbolt bolt service..."
    sudo systemctl enable --now bolt
fi

# Fix 4: Load Thunderbolt modules
if ! lsmod | grep -q thunderbolt; then
    echo "Loading Thunderbolt modules..."
    sudo modprobe thunderbolt
    sudo modprobe usb4
fi

# Fix 5: Authorize all Thunderbolt devices
if command -v boltctl &>/dev/null; then
    echo "Authorizing Thunderbolt devices..."
    for uuid in $(boltctl list | grep "└─" | awk '{print $2}'); do
        sudo boltctl authorize "$uuid" 2>/dev/null || true
    done
fi

echo "Fixes applied. Please reboot for changes to take effect."
FIXEOF

    chmod +x "$fix_script"
    log "${GREEN}Fix script generated: $fix_script${NC}"
    info "Run with: sudo bash $fix_script"
}

# ============================================================================
# Main
# ============================================================================
main() {
    header "ARCH System Debugger - Comprehensive Diagnostics"

    echo -e "${CYAN}"
    cat << 'EOF'
  ╔═══════════════════════════════════════════════════════════════╗
  ║              System Debug & Diagnostics                       ║
  ║                                                               ║
  ║  Checking:                                                    ║
  ║  • VMD (Intel Volume Management Device)                       ║
  ║  • NVIDIA Driver Status                                       ║
  ║  • Thunderbolt 5 / DisplayPort                                ║
  ║  • Razer Dock Detection                                       ║
  ║  • Samsung Odyssey Monitor                                    ║
  ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    log "Debug log: $DEBUG_LOG"
    log ""

    # Run all diagnostics
    debug_system_overview
    debug_vmd
    debug_nvidia
    debug_thunderbolt_displayport
    debug_kernel_config
    generate_fix_script

    header "Debug Complete"

    log ""
    log "Full debug log saved to: $DEBUG_LOG"
    log ""
    log "Summary of issues found:"
    echo ""

    # Count issues from log
    local total_errors=$(grep -c "ERROR" "$DEBUG_LOG" || echo "0")
    local total_warnings=$(grep -c "WARN" "$DEBUG_LOG" || echo "0")

    if [ "$total_errors" -gt 0 ]; then
        error "Found $total_errors error(s)"
    fi

    if [ "$total_warnings" -gt 0 ]; then
        warn "Found $total_warnings warning(s)"
    fi

    if [ "$total_errors" -eq 0 ] && [ "$total_warnings" -eq 0 ]; then
        log "${GREEN}✓ No major issues detected!${NC}"
    else
        info "Review the debug log and run: sudo bash scripts/apply-fixes.sh"
    fi
}

main "$@"
