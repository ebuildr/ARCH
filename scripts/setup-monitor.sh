#!/bin/bash
#
# ARCH Monitor Setup - Samsung Odyssey via Razer TB5 Dock
# Configures DisplayPort output through Thunderbolt 5 dock
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PROJECT_ROOT}/config"
LOG_DIR="${PROJECT_ROOT}/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() { echo -e "${GREEN}[MONITOR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${MAGENTA}[INFO]${NC} $1"; }
header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

# ============================================================================
# Detect Connected Monitors
# ============================================================================
detect_monitors() {
    header "Detecting Connected Monitors"

    log "Scanning for displays..."

    # Check DRM subsystem
    if [ -d /sys/class/drm ]; then
        log "Connected displays:"
        for connector in /sys/class/drm/card*-*/status; do
            if [ -f "$connector" ]; then
                local status=$(cat "$connector")
                local name=$(basename $(dirname "$connector"))
                local enabled=$(cat "$(dirname $connector)/enabled" 2>/dev/null || echo "unknown")

                if [ "$status" = "connected" ]; then
                    log "  ${GREEN}✓${NC} $name - connected (enabled: $enabled)"

                    # Get EDID info if available
                    local edid_path="$(dirname $connector)/edid"
                    if [ -f "$edid_path" ] && command -v edid-decode &>/dev/null; then
                        local monitor_name=$(edid-decode "$edid_path" 2>/dev/null | grep "Monitor name" | cut -d: -f2 | xargs)
                        [ -n "$monitor_name" ] && log "      Name: $monitor_name"
                    fi

                    # Get modes
                    local modes_path="$(dirname $connector)/modes"
                    if [ -f "$modes_path" ]; then
                        local top_mode=$(head -1 "$modes_path")
                        log "      Best mode: $top_mode"
                    fi
                else
                    info "  ○ $name - disconnected"
                fi
            fi
        done
    fi

    # Use xrandr if available
    if command -v xrandr &>/dev/null && [ -n "${DISPLAY:-}" ]; then
        log ""
        log "XRandR output:"
        xrandr --query | grep -E "connected|disconnected" | while read line; do
            log "  $line"
        done
    fi

    # NVIDIA specific
    if command -v nvidia-smi &>/dev/null; then
        log ""
        log "NVIDIA displays:"
        nvidia-smi --query-gpu=name,display_active,display_mode --format=csv,noheader 2>/dev/null || true
    fi
}

# ============================================================================
# Configure Samsung Odyssey Monitor
# ============================================================================
configure_samsung_odyssey() {
    header "Configuring Samsung Odyssey Monitor"

    log "Setting up Samsung Odyssey via Razer TB5 Dock DisplayPort..."

    # Detect which Odyssey model (G9, G7, etc.)
    info "Samsung Odyssey series supported:"
    info "  - Odyssey G9 (5120x1440 @ 240Hz)"
    info "  - Odyssey G7 (2560x1440 @ 240Hz)"
    info "  - Odyssey Neo G9 (5120x1440 @ 240Hz Mini-LED)"
    info "  - Odyssey OLED G9 (5120x1440 @ 240Hz OLED)"
    info "  - Odyssey Ark (3840x2160 @ 165Hz)"

    # Create comprehensive Xorg config
    sudo mkdir -p /etc/X11/xorg.conf.d/

    sudo tee /etc/X11/xorg.conf.d/30-samsung-odyssey.conf > /dev/null << 'EOF'
# Samsung Odyssey Monitor Configuration
# Connected via Razer Thunderbolt 5 Dock (DisplayPort)

Section "Monitor"
    Identifier "Samsung-Odyssey"

    # Enable DPMS (Display Power Management)
    Option "DPMS" "true"

    # VRR / FreeSync / G-Sync Compatible
    Option "VariableRefresh" "true"

    # Preferred modes (adjust based on your Odyssey model)
    # Odyssey G9/Neo G9: 5120x1440
    # Odyssey G7: 2560x1440
    # Odyssey Ark: 3840x2160
    Option "PreferredMode" "3840x2160"

    # High refresh rate
    Option "RefreshRate" "144"

    # HDR
    Option "HDR" "on"

    # Wide color gamut
    Option "ColorRange" "Full"
EndSection

Section "Device"
    Identifier "NVIDIA-GPU"
    Driver "nvidia"

    # Use NVIDIA for all displays (including TB5 dock)
    Option "AllowExternalGpus" "True"
    Option "AllowEmptyInitialConfiguration" "True"

    # Performance settings
    Option "TripleBuffer" "True"
    Option "AllowIndirectGLXProtocol" "off"

    # G-Sync Compatible / VRR
    Option "AllowGSYNCCompatible" "On"
    Option "AllowVRR" "On"

    # DisplayPort 2.1 compatibility
    Option "ModeValidation" "AllowNon3DVisionModes, NoEdidMaxPClkCheck, NoMaxPClkCheck, NoVertRefreshCheck"

    # Enable GSP firmware (RTX 5090)
    Option "NVreg_EnableGpuFirmware" "1"

    # Preserve video memory on suspend
    Option "PreserveVideoMemoryAllocations" "1"

    # Use NVIDIA for composition
    Option "ForceCompositionPipeline" "Off"
    Option "ForceFullCompositionPipeline" "Off"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "NVIDIA-GPU"
    Monitor "Samsung-Odyssey"
    DefaultDepth 24

    SubSection "Display"
        Depth 24
        # Common high-res modes
        Modes "5120x1440" "3840x2160" "2560x1440" "1920x1080"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
    Option "AllowNVIDIAGPUScreens"
EndSection

Section "Extensions"
    # Enable VRR
    Option "VariableRefresh" "true"
EndSection
EOF

    log "Xorg configuration created"
}

# ============================================================================
# Configure for Wayland (GNOME/KDE)
# ============================================================================
configure_wayland() {
    header "Configuring Wayland for Samsung Odyssey"

    log "Setting up Wayland environment for high refresh rate + VRR..."

    sudo mkdir -p /etc/environment.d/

    sudo tee /etc/environment.d/30-samsung-odyssey.conf > /dev/null << 'EOF'
# Samsung Odyssey Monitor - Wayland Configuration

# NVIDIA Wayland support
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
LIBVA_DRIVER_NAME=nvidia

# VRR / Variable Refresh Rate
MUTTER_DEBUG_ENABLE_VRRT=1
KWIN_DRM_ALLOW_NVIDIA_COLORSPACE=1

# HDR Support
ENABLE_HDR_WSI=1
DXVK_HDR=1

# High refresh rate
__GL_GSYNC_ALLOWED=1
__GL_VRR_ALLOWED=1

# Force NVIDIA for external displays via TB5
__NV_PRIME_RENDER_OFFLOAD=1
__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0

# Disable hardware cursor if issues occur
# WLR_NO_HARDWARE_CURSORS=1
EOF

    # GNOME specific
    if command -v gsettings &>/dev/null; then
        log "Configuring GNOME settings..."

        # Enable VRR in GNOME (if supported)
        gsettings set org.gnome.mutter experimental-features "['variable-refresh-rate']" 2>/dev/null || true

        # Set scaling
        # gsettings set org.gnome.desktop.interface scaling-factor 1
    fi

    # KDE specific
    if [ -d "$HOME/.config/kwinrc" ] || command -v kwriteconfig5 &>/dev/null; then
        log "Configuring KDE Plasma settings..."

        mkdir -p "$HOME/.config"

        # Enable VRR in KDE
        kwriteconfig5 --file kwinrc --group Compositing --key AllowVrr true 2>/dev/null || true
    fi

    log "Wayland configuration complete"
}

# ============================================================================
# Configure NVIDIA Settings
# ============================================================================
configure_nvidia_settings() {
    header "Configuring NVIDIA Display Settings"

    # Create nvidia-settings config
    mkdir -p "$HOME/.nvidia-settings-rc" 2>/dev/null || true

    # NVIDIA X Server Settings for Odyssey
    if command -v nvidia-settings &>/dev/null; then
        log "Applying NVIDIA settings..."

        # These require X11 to be running
        if [ -n "${DISPLAY:-}" ]; then
            # Enable G-Sync Compatible
            nvidia-settings -a "AllowGSYNCCompatible=1" 2>/dev/null || true

            # Enable VRR
            nvidia-settings -a "AllowVRR=1" 2>/dev/null || true

            # Full RGB range
            nvidia-settings -a "CurrentMetaMode=nvidia-auto-select +0+0 {ForceFullCompositionPipeline=Off, AllowGSYNCCompatible=On}" 2>/dev/null || true

            log "NVIDIA settings applied"
        else
            info "X11 not running - NVIDIA settings will apply on next login"
        fi
    fi

    # Persistent nvidia-settings
    sudo tee /etc/X11/xinit/xinitrc.d/nvidia-settings.sh > /dev/null << 'EOF'
#!/bin/bash
# Apply NVIDIA settings on X startup
if command -v nvidia-settings &>/dev/null; then
    nvidia-settings -a "AllowGSYNCCompatible=1" 2>/dev/null || true
    nvidia-settings -a "AllowVRR=1" 2>/dev/null || true
fi
EOF
    sudo chmod +x /etc/X11/xinit/xinitrc.d/nvidia-settings.sh 2>/dev/null || true
}

# ============================================================================
# Configure High Refresh Rate
# ============================================================================
configure_high_refresh() {
    header "Configuring High Refresh Rate"

    log "Setting up for 144Hz+ refresh rates..."

    # Modeline for common Odyssey resolutions
    # These help if auto-detection fails

    sudo tee /etc/X11/xorg.conf.d/31-odyssey-modes.conf > /dev/null << 'EOF'
# Custom modelines for Samsung Odyssey high refresh rates

Section "Monitor"
    Identifier "Samsung-Odyssey-HRR"

    # 3840x2160 @ 144Hz (Odyssey Ark, G8)
    Modeline "3840x2160_144" 1380.00 3840 4152 4576 5312 2160 2163 2168 2273 -hsync +vsync

    # 2560x1440 @ 240Hz (Odyssey G7)
    Modeline "2560x1440_240" 1105.00 2560 2768 3048 3536 1440 1443 1448 1557 -hsync +vsync

    # 5120x1440 @ 240Hz (Odyssey G9)
    Modeline "5120x1440_240" 2098.00 5120 5544 6104 7088 1440 1443 1453 1572 -hsync +vsync

    # 3440x1440 @ 144Hz (Ultrawide)
    Modeline "3440x1440_144" 728.00 3440 3720 4096 4752 1440 1443 1453 1568 -hsync +vsync
EndSection
EOF

    log "Custom modelines configured"
}

# ============================================================================
# Test Display Configuration
# ============================================================================
test_display() {
    header "Testing Display Configuration"

    local success=true

    # Check if NVIDIA driver loaded
    log "Checking NVIDIA driver..."
    if lsmod | grep -q nvidia; then
        log "  ${GREEN}✓${NC} NVIDIA driver loaded"
    else
        warn "  ✗ NVIDIA driver not loaded"
        success=false
    fi

    # Check DRM
    log "Checking DRM devices..."
    if [ -e /dev/dri/card0 ]; then
        log "  ${GREEN}✓${NC} DRM device available"
    fi

    # Check for connected displays
    log "Checking connected displays..."
    local connected=$(cat /sys/class/drm/card*-*/status 2>/dev/null | grep -c "connected" || echo "0")
    if [ "$connected" -gt 0 ]; then
        log "  ${GREEN}✓${NC} $connected display(s) connected"
    else
        warn "  ✗ No displays detected"
        success=false
    fi

    # Check nvidia-smi
    if command -v nvidia-smi &>/dev/null; then
        log "Checking NVIDIA GPU..."
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | while read line; do
            log "  ${GREEN}✓${NC} $line"
        done
    fi

    # Show xrandr if available
    if command -v xrandr &>/dev/null && [ -n "${DISPLAY:-}" ]; then
        log ""
        log "Current display configuration:"
        xrandr --current | grep -E "connected|^\s+[0-9]+x[0-9]+" | head -10
    fi

    echo ""
    if [ "$success" = true ]; then
        log "${GREEN}Display test passed!${NC}"
    else
        warn "Some checks failed - display may need manual configuration"
    fi
}

# ============================================================================
# Show XRandR Commands
# ============================================================================
show_xrandr_help() {
    header "XRandR Quick Commands"

    cat << 'EOF'
Common xrandr commands for Samsung Odyssey:

# List all outputs and modes
xrandr --query

# Set 4K @ 144Hz (if supported)
xrandr --output DP-1 --mode 3840x2160 --rate 144

# Set 1440p @ 240Hz (Odyssey G7)
xrandr --output DP-1 --mode 2560x1440 --rate 240

# Set ultrawide 5120x1440 @ 240Hz (Odyssey G9)
xrandr --output DP-1 --mode 5120x1440 --rate 240

# Enable VRR (FreeSync) - requires kernel 5.12+
xrandr --output DP-1 --set "vrr_capable" 1

# Set as primary display
xrandr --output DP-1 --primary

# Position next to laptop display
xrandr --output DP-1 --right-of eDP-1

# Mirror displays
xrandr --output DP-1 --same-as eDP-1

Note: Replace DP-1 with your actual output name (check with xrandr --query)
      Thunderbolt displays often show as DP-X or DP-1-X
EOF
}

# ============================================================================
# Main
# ============================================================================
main() {
    header "Samsung Odyssey Monitor Setup via Razer TB5 Dock"

    echo -e "${CYAN}"
    cat << 'EOF'
  ╔═══════════════════════════════════════════════════════════════╗
  ║       Samsung Odyssey Monitor Configuration                   ║
  ║       via Razer Thunderbolt 5 Dock (DisplayPort)             ║
  ║                                                               ║
  ║   Features:                                                   ║
  ║   • High refresh rate (144Hz / 240Hz)                        ║
  ║   • VRR / FreeSync / G-Sync Compatible                       ║
  ║   • HDR support                                              ║
  ║   • DisplayPort 2.1 via Thunderbolt 5                        ║
  ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    mkdir -p "$LOG_DIR" "$CONFIG_DIR"

    local command="${1:-all}"

    case "$command" in
        detect)
            detect_monitors
            ;;
        configure)
            configure_samsung_odyssey
            configure_wayland
            configure_nvidia_settings
            configure_high_refresh
            ;;
        test)
            test_display
            ;;
        help)
            show_xrandr_help
            ;;
        all|*)
            detect_monitors
            configure_samsung_odyssey
            configure_wayland
            configure_nvidia_settings
            configure_high_refresh
            test_display
            show_xrandr_help
            ;;
    esac

    header "Monitor Setup Complete!"

    log ""
    log "Configuration files created:"
    log "  /etc/X11/xorg.conf.d/30-samsung-odyssey.conf"
    log "  /etc/X11/xorg.conf.d/31-odyssey-modes.conf"
    log "  /etc/environment.d/30-samsung-odyssey.conf"
    log ""
    log "Next steps:"
    log "  1. Connect Samsung Odyssey to Razer dock via DisplayPort"
    log "  2. Log out and back in (or reboot)"
    log "  3. Use display settings to configure resolution/refresh"
    log ""
    log "Quick commands:"
    log "  xrandr --query                    # List displays"
    log "  xrandr --output DP-1 --auto       # Auto-configure"
    log "  nvidia-settings                   # NVIDIA control panel"
}

main "$@"
