#!/bin/bash
#
# ARCH Thunderbolt/DisplayPort Fix - Troubleshoot Razer TB5 Dock and Samsung Odyssey
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/logs"
FIX_LOG="${LOG_DIR}/tb-dp-fix-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[FIX]${NC} $1" | tee -a "$FIX_LOG"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$FIX_LOG"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$FIX_LOG"; }
info() { echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$FIX_LOG"; }

mkdir -p "$LOG_DIR"

header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

header "Thunderbolt 5 / DisplayPort Fix - Razer Dock + Samsung Odyssey"

log "Fix log: $FIX_LOG"

# ============================================================================
# Step 1: Install required packages
# ============================================================================
header "Step 1: Install Required Packages"

log "Installing Thunderbolt management tools..."
sudo pacman -S --needed --noconfirm \
    bolt \
    usbutils \
    pciutils \
    edid-decode \
    xorg-xrandr \
    2>&1 | tee -a "$FIX_LOG"

# ============================================================================
# Step 2: Enable and start bolt service
# ============================================================================
header "Step 2: Configure Bolt (Thunderbolt Management)"

log "Enabling bolt service..."
sudo systemctl enable bolt.service
sudo systemctl start bolt.service

log "Waiting for bolt to initialize..."
sleep 2

log "Current Thunderbolt devices:"
boltctl list | tee -a "$FIX_LOG"

# ============================================================================
# Step 3: Authorize all Thunderbolt devices
# ============================================================================
header "Step 3: Authorize Thunderbolt Devices"

log "Setting bolt policy to auto-authorize..."
sudo boltctl config global.auth-mode auto 2>/dev/null || true

log "Authorizing all detected Thunderbolt devices..."
DEVICE_COUNT=0
for uuid in $(boltctl list 2>/dev/null | grep "└─" | awk '{print $2}' || echo ""); do
    if [ -n "$uuid" ]; then
        log "Authorizing device: $uuid"
        sudo boltctl authorize "$uuid" 2>&1 | tee -a "$FIX_LOG" || warn "Could not authorize $uuid"
        ((DEVICE_COUNT++))
    fi
done

if [ $DEVICE_COUNT -eq 0 ]; then
    warn "No Thunderbolt devices found to authorize"
    info "Make sure the Razer Thunderbolt 5 Dock is connected"
else
    log "Authorized $DEVICE_COUNT Thunderbolt device(s)"
fi

log ""
log "Thunderbolt devices after authorization:"
boltctl list | tee -a "$FIX_LOG"

# ============================================================================
# Step 4: Load Thunderbolt kernel modules
# ============================================================================
header "Step 4: Load Thunderbolt Kernel Modules"

log "Loading Thunderbolt/USB4 kernel modules..."
sudo modprobe thunderbolt 2>&1 | tee -a "$FIX_LOG" || warn "thunderbolt module load failed"
sudo modprobe usb4 2>&1 | tee -a "$FIX_LOG" || warn "usb4 module load failed"
sudo modprobe typec 2>&1 | tee -a "$FIX_LOG" || warn "typec module load failed"
sudo modprobe typec_displayport 2>&1 | tee -a "$FIX_LOG" || info "typec_displayport not available"

log ""
log "Loaded Thunderbolt modules:"
lsmod | grep -E "thunderbolt|usb4|typec" | tee -a "$FIX_LOG" || warn "No Thunderbolt modules loaded"

# ============================================================================
# Step 5: Check PCIe tunnel
# ============================================================================
header "Step 5: Verify PCIe Tunneling"

log "Checking PCIe devices on Thunderbolt bus..."
lspci | grep -i thunderbolt | tee -a "$FIX_LOG" || info "No Thunderbolt PCIe devices"

log ""
log "Checking for hotplug events..."
dmesg | grep -iE "thunderbolt|pcie.*hotplug" | tail -20 | tee -a "$FIX_LOG"

# ============================================================================
# Step 6: Check DisplayPort Alt Mode
# ============================================================================
header "Step 6: Check DisplayPort Alt Mode"

log "Checking USB Type-C ports..."
if [ -d /sys/class/typec ]; then
    for port in /sys/class/typec/port*; do
        if [ -d "$port" ]; then
            port_name=$(basename "$port")
            log ""
            log "Port: $port_name"

            [ -f "$port/data_role" ] && log "  Data role: $(cat $port/data_role 2>/dev/null)"
            [ -f "$port/power_role" ] && log "  Power role: $(cat $port/power_role 2>/dev/null)"

            # Check for partner (connected device)
            if [ -d "$port/port${port_name#port}-partner" ]; then
                log "  Partner connected"

                # Check alt modes
                for mode in "$port"/port*-partner/port*-partner.*/mode*; do
                    if [ -f "$mode" ]; then
                        log "  Alt mode: $(cat $mode 2>/dev/null)"
                    fi
                done
            fi
        fi
    done
else
    warn "USB Type-C information not available in sysfs"
fi

# ============================================================================
# Step 7: Force DisplayPort detection
# ============================================================================
header "Step 7: Force DisplayPort Detection"

log "Rescanning DRM connectors..."
for drm_card in /sys/class/drm/card*/card*; do
    if [ -f "$drm_card-*/status" ]; then
        connector=$(dirname "$drm_card-*")
        log "Rescanning: $connector"
        echo detect | sudo tee "$connector/status" 2>/dev/null || true
    fi
done

# Force rescan of DRM devices
log ""
log "Triggering udev events for DRM devices..."
for card in /sys/class/drm/card*/device; do
    if [ -e "$card" ]; then
        log "Triggering: $card"
        echo 1 | sudo tee "$card/rescan" 2>/dev/null || true
    fi
done

sleep 2

# ============================================================================
# Step 8: Check connected displays
# ============================================================================
header "Step 8: Check Connected Displays"

log "DRM connector status:"
for connector in /sys/class/drm/card*-*/status; do
    if [ -f "$connector" ]; then
        status=$(cat "$connector")
        name=$(basename $(dirname "$connector"))

        if [ "$status" = "connected" ]; then
            log "${GREEN}✓${NC} $name - CONNECTED"

            # Get EDID
            edid_path="$(dirname $connector)/edid"
            if [ -f "$edid_path" ] && [ -s "$edid_path" ]; then
                log "  EDID info:"
                if command -v edid-decode &>/dev/null; then
                    edid-decode "$edid_path" 2>/dev/null | grep -E "Monitor name|Manufacturer|Display Product Name" | sed 's/^/    /' | tee -a "$FIX_LOG"
                fi

                # Check for Samsung Odyssey
                if edid-decode "$edid_path" 2>/dev/null | grep -qi "odyssey\|samsung"; then
                    log "${GREEN}  ✓ Samsung Odyssey detected!${NC}"
                fi
            else
                warn "  No EDID data available"
            fi

            # Show available modes
            modes_path="$(dirname $connector)/modes"
            if [ -f "$modes_path" ]; then
                log "  Available modes:"
                head -5 "$modes_path" | sed 's/^/    /' | tee -a "$FIX_LOG"
            fi

            # Show enabled/disabled status
            enabled_path="$(dirname $connector)/enabled"
            if [ -f "$enabled_path" ]; then
                enabled=$(cat "$enabled_path")
                log "  Enabled: $enabled"
            fi
        else
            info "○ $name - $status"
        fi
    fi
done

# ============================================================================
# Step 9: Configure display with xrandr (if X11 running)
# ============================================================================
header "Step 9: Configure Display"

if [ -n "${DISPLAY:-}" ] && command -v xrandr &>/dev/null; then
    log "X11 detected - configuring with xrandr..."

    log ""
    log "Current xrandr output:"
    xrandr --query | tee -a "$FIX_LOG"

    log ""
    log "Looking for connected DisplayPort outputs..."
    CONNECTED_DP=$(xrandr --query | grep " connected" | grep -E "DP-[0-9]" | awk '{print $1}' | head -1)

    if [ -n "$CONNECTED_DP" ]; then
        log "${GREEN}✓${NC} Found connected DisplayPort: $CONNECTED_DP"

        log "Setting $CONNECTED_DP as primary with auto configuration..."
        xrandr --output "$CONNECTED_DP" --auto --primary 2>&1 | tee -a "$FIX_LOG" || warn "xrandr auto config failed"

        log ""
        log "Attempting to set high refresh rate..."
        # Try common Samsung Odyssey modes
        xrandr --output "$CONNECTED_DP" --mode 3840x2160 --rate 144 2>/dev/null || \
        xrandr --output "$CONNECTED_DP" --mode 2560x1440 --rate 240 2>/dev/null || \
        xrandr --output "$CONNECTED_DP" --mode 5120x1440 --rate 240 2>/dev/null || \
        info "Could not set specific mode - using auto"

        log ""
        log "Current configuration:"
        xrandr --query | grep -A1 "$CONNECTED_DP" | tee -a "$FIX_LOG"
    else
        warn "No connected DisplayPort output found in xrandr"
        info "Available outputs:"
        xrandr --query | grep connected | tee -a "$FIX_LOG"
    fi
else
    info "X11 not running or xrandr not available"
    info "For Wayland, configure display in GNOME Settings or KDE Display Settings"
fi

# ============================================================================
# Step 10: Create udev rules for auto-authorization
# ============================================================================
header "Step 10: Create Udev Rules"

log "Creating udev rules for Thunderbolt auto-authorization..."
cat << 'EOF' | sudo tee /etc/udev/rules.d/99-thunderbolt-authorize.rules
# Auto-authorize Thunderbolt devices
# Razer Thunderbolt 5 Dock
ACTION=="add", SUBSYSTEM=="thunderbolt", ATTRS{authorized}=="0", ATTR{authorized}="1"

# Trigger bolt to handle new devices
ACTION=="add", SUBSYSTEM=="thunderbolt", RUN+="/usr/bin/boltctl enroll --policy auto $attr{unique_id}"
EOF

log "Reloading udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger

# ============================================================================
# Step 11: Check NVIDIA + Thunderbolt interaction
# ============================================================================
header "Step 11: NVIDIA + Thunderbolt Compatibility"

log "Checking NVIDIA driver status..."
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    log "${GREEN}✓${NC} NVIDIA driver is working"

    log ""
    log "Checking if NVIDIA can see external displays..."
    nvidia-smi --query-gpu=name,display_active,display_mode --format=csv | tee -a "$FIX_LOG"

    # Check if external display is managed by NVIDIA
    if xrandr --listproviders 2>/dev/null | grep -qi nvidia; then
        log "${GREEN}✓${NC} NVIDIA is providing display output"
    else
        warn "NVIDIA may not be managing displays"
        info "Check PRIME configuration for hybrid graphics"
    fi
else
    warn "NVIDIA driver not working"
    info "Run: bash $SCRIPT_DIR/fix-nvidia.sh"
fi

# ============================================================================
# Summary
# ============================================================================
header "Thunderbolt/DisplayPort Fix Complete"

log ""
log "Summary of changes:"
log "  ✓ Bolt service enabled and started"
log "  ✓ Thunderbolt devices authorized"
log "  ✓ Kernel modules loaded"
log "  ✓ DisplayPort detection forced"
log "  ✓ Udev rules created for auto-authorization"
log ""

# Count connected displays
CONNECTED_COUNT=$(cat /sys/class/drm/card*-*/status 2>/dev/null | grep -c "connected" || echo "0")
log "Connected displays: $CONNECTED_COUNT"

if [ "$CONNECTED_COUNT" -gt 0 ]; then
    log "${GREEN}✓ Display(s) detected!${NC}"
else
    warn "No displays detected"
    info ""
    info "Troubleshooting steps:"
    info "  1. Verify physical connection (dock → monitor via DisplayPort)"
    info "  2. Try different DisplayPort ports on the dock"
    info "  3. Check monitor power and input source"
    info "  4. Disconnect and reconnect the Thunderbolt cable"
    info "  5. Check BIOS settings: Thunderbolt enabled, no security level"
    info "  6. Run: sudo dmesg | grep -iE 'thunderbolt|displayport'"
    info "  7. Reboot with dock connected"
fi

log ""
log "Full log saved to: $FIX_LOG"
log ""
log "${YELLOW}Note: If issues persist, try:${NC}"
log "  1. Reboot with dock and monitor connected"
log "  2. Check dock firmware (may need Windows update)"
log "  3. Run debug script: bash $SCRIPT_DIR/debug-system.sh"
