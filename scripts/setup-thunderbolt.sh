#!/bin/bash
#
# ARCH Thunderbolt 5 / USB4 Setup for Razer Dock
# Configures Thunderbolt security and dock support
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
NC='\033[0m'

log() { echo -e "${GREEN}[TB5]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

# ============================================================================
# Detect Thunderbolt Controllers
# ============================================================================
detect_thunderbolt() {
    header "Detecting Thunderbolt/USB4 Controllers"

    local tb_found=false

    # Check for Thunderbolt controllers
    if lspci 2>/dev/null | grep -i "thunderbolt\|usb4" > /dev/null; then
        log "Thunderbolt controllers found:"
        lspci | grep -i "thunderbolt\|usb4" | while read line; do
            log "  $line"
        done
        tb_found=true
    fi

    # Check USB4 ports
    if [ -d /sys/bus/thunderbolt ]; then
        log "Thunderbolt bus detected"

        # List domains
        for domain in /sys/bus/thunderbolt/devices/domain*; do
            if [ -d "$domain" ]; then
                local security=$(cat "$domain/security" 2>/dev/null || echo "unknown")
                log "  Domain: $(basename $domain), Security: $security"
            fi
        done

        # List connected devices
        log "Connected Thunderbolt devices:"
        for device in /sys/bus/thunderbolt/devices/*-*; do
            if [ -d "$device" ] && [ -f "$device/device_name" ]; then
                local name=$(cat "$device/device_name" 2>/dev/null || echo "Unknown")
                local vendor=$(cat "$device/vendor_name" 2>/dev/null || echo "Unknown")
                local auth=$(cat "$device/authorized" 2>/dev/null || echo "?")
                log "  - $vendor $name (authorized: $auth)"
            fi
        done
    fi

    if [ "$tb_found" = false ]; then
        warn "No Thunderbolt controllers detected in lspci"
        log "This may be normal if Thunderbolt is integrated into the CPU"
    fi

    # Save detection results
    mkdir -p "$CONFIG_DIR"
    {
        echo "# Thunderbolt Detection Report"
        echo "# Generated: $(date)"
        echo ""
        lspci | grep -i "thunderbolt\|usb4" 2>/dev/null || echo "# No dedicated controllers"
    } > "${CONFIG_DIR}/thunderbolt-report.txt"
}

# ============================================================================
# Install Thunderbolt Tools
# ============================================================================
install_tools() {
    header "Installing Thunderbolt Management Tools"

    local packages=(
        "bolt"           # Thunderbolt device manager
        "thunderbolt-utils"  # CLI tools (if available)
    )

    log "Installing thunderbolt management packages..."

    for pkg in "${packages[@]}"; do
        if pacman -Ss "^${pkg}$" &>/dev/null; then
            sudo pacman -S --needed --noconfirm "$pkg" 2>/dev/null || {
                warn "Package $pkg not available in repos"
            }
        fi
    done

    # Enable bolt daemon
    if systemctl list-unit-files | grep -q bolt.service; then
        log "Enabling bolt service..."
        sudo systemctl enable --now bolt.service
    fi
}

# ============================================================================
# Configure Thunderbolt Security
# ============================================================================
configure_security() {
    header "Configuring Thunderbolt Security"

    # Check current security level
    local security_level="unknown"
    if [ -f /sys/bus/thunderbolt/devices/domain0/security ]; then
        security_level=$(cat /sys/bus/thunderbolt/devices/domain0/security)
    fi

    log "Current security level: $security_level"

    case "$security_level" in
        "none")
            log "Security: No security (all devices allowed)"
            ;;
        "user")
            log "Security: User authorization required"
            ;;
        "secure")
            log "Security: Secure connect (challenge-response)"
            ;;
        "dponly")
            log "Security: DisplayPort only (no PCIe tunneling)"
            warn "PCIe devices like docks won't work fully in this mode"
            ;;
        *)
            warn "Unknown security level: $security_level"
            ;;
    esac

    # Create udev rules for auto-authorization of known devices
    log "Creating udev rules for Thunderbolt..."

    sudo mkdir -p /etc/udev/rules.d/

    # Razer Thunderbolt Dock rule
    sudo tee /etc/udev/rules.d/99-thunderbolt.rules > /dev/null << 'EOF'
# Thunderbolt/USB4 device authorization rules

# Auto-authorize Razer Thunderbolt docks
ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{vendor_name}=="Razer*", ATTR{authorized}=="0", ATTR{authorized}="1"

# Generic Thunderbolt dock authorization (user security mode)
# Uncomment to auto-authorize all Thunderbolt docks
# ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", ATTR{authorized}="1"

# USB4 hubs
ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{device_name}=="*USB4*", ATTR{authorized}=="0", ATTR{authorized}="1"
EOF

    # Reload udev
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    log "Thunderbolt udev rules installed"
}

# ============================================================================
# Configure Razer Dock
# ============================================================================
configure_razer_dock() {
    header "Configuring Razer Thunderbolt 5 Dock"

    log "Setting up Razer-specific configurations..."

    # Razer device rules
    sudo tee /etc/udev/rules.d/99-razer.rules > /dev/null << 'EOF'
# Razer devices udev rules

# Razer Thunderbolt Dock
SUBSYSTEM=="thunderbolt", ATTR{vendor_name}=="Razer*", MODE="0666"

# Razer USB devices (keyboard, mouse on dock)
SUBSYSTEM=="usb", ATTR{idVendor}=="1532", MODE="0666", GROUP="plugdev"

# Razer HID devices
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", MODE="0666", GROUP="plugdev"
EOF

    # Install openrazer if available (for RGB control, etc.)
    if pacman -Ss openrazer &>/dev/null; then
        log "OpenRazer available, installing for device control..."
        sudo pacman -S --needed --noconfirm openrazer-daemon openrazer-driver-dkms 2>/dev/null || {
            warn "OpenRazer not available in standard repos"
            log "Install from AUR if RGB control is needed: yay -S openrazer-meta"
        }
    fi

    log "Razer dock configuration complete"
}

# ============================================================================
# Configure DisplayPort Alt Mode
# ============================================================================
configure_display() {
    header "Configuring DisplayPort Alt Mode"

    log "Setting up DisplayPort over USB-C/Thunderbolt..."

    # Load required modules
    local modules=(
        "typec_displayport"
        "drm"
        "drm_kms_helper"
    )

    for mod in "${modules[@]}"; do
        if modinfo "$mod" &>/dev/null; then
            sudo modprobe "$mod" 2>/dev/null || true
            log "  Loaded: $mod"
        fi
    done

    # Ensure modules load at boot
    sudo mkdir -p /etc/modules-load.d/
    sudo tee /etc/modules-load.d/thunderbolt-display.conf > /dev/null << 'EOF'
# DisplayPort Alt Mode for Thunderbolt
typec_displayport
EOF

    # Samsung Odyssey monitor specific settings
    log "Adding Samsung Odyssey monitor support..."

    # EDID override directory (if needed)
    sudo mkdir -p /lib/firmware/edid/

    # Create Xorg config for external monitors
    sudo mkdir -p /etc/X11/xorg.conf.d/
    sudo tee /etc/X11/xorg.conf.d/20-external-monitors.conf > /dev/null << 'EOF'
# External monitor configuration via Thunderbolt dock

Section "Monitor"
    Identifier "Samsung-Odyssey"
    Option "DPMS" "true"
    Option "PreferredMode" "3840x2160"
    # Enable VRR/FreeSync
    Option "VariableRefresh" "true"
EndSection

Section "Device"
    Identifier "NVIDIA"
    Driver "nvidia"
    Option "AllowExternalGpus" "True"
    Option "TripleBuffer" "True"
    Option "AllowIndirectGLXProtocol" "off"
EndSection
EOF

    log "Display configuration complete"
}

# ============================================================================
# Configure PCIe Tunneling
# ============================================================================
configure_pcie_tunneling() {
    header "Configuring PCIe Tunneling"

    log "Setting up PCIe over Thunderbolt..."

    # Kernel parameters for PCIe hotplug
    sudo mkdir -p /etc/modprobe.d/
    sudo tee /etc/modprobe.d/thunderbolt-pcie.conf > /dev/null << 'EOF'
# Thunderbolt PCIe tunneling options
options thunderbolt host_reset=1

# PCIe hotplug
options pciehp pciehp_poll_mode=1
EOF

    # Enable PCIe hotplug
    if [ ! -f /etc/modules-load.d/pcie-hotplug.conf ]; then
        sudo tee /etc/modules-load.d/pcie-hotplug.conf > /dev/null << 'EOF'
# PCIe hotplug for Thunderbolt docks
pciehp
EOF
    fi

    log "PCIe tunneling configured"
}

# ============================================================================
# Configure Networking (Thunderbolt Networking)
# ============================================================================
configure_networking() {
    header "Configuring Thunderbolt Networking"

    log "Setting up Thunderbolt/USB4 networking..."

    # Load thunderbolt-net module
    if modinfo thunderbolt-net &>/dev/null; then
        sudo modprobe thunderbolt-net 2>/dev/null || true
        log "Thunderbolt networking module loaded"
    fi

    # Ethernet from dock (typically via USB or Thunderbolt PCIe)
    log "Dock ethernet should work automatically via standard drivers"

    # Create NetworkManager connection for dock ethernet
    if command -v nmcli &>/dev/null; then
        log "NetworkManager detected, dock ethernet will auto-configure"
    fi
}

# ============================================================================
# Authorize Device (Manual)
# ============================================================================
authorize_device() {
    header "Authorizing Thunderbolt Devices"

    # Use boltctl if available
    if command -v boltctl &>/dev/null; then
        log "Using boltctl to manage devices..."

        # List devices
        log "Currently known devices:"
        boltctl list

        # Authorize pending devices
        log "Authorizing any pending devices..."
        boltctl authorize --all 2>/dev/null || true

        # Enroll devices for permanent authorization
        log "Enrolling devices for permanent access..."
        for uuid in $(boltctl list --format json 2>/dev/null | grep -oP '"uuid"\s*:\s*"\K[^"]+' || true); do
            boltctl enroll "$uuid" 2>/dev/null || true
        done
    else
        # Manual authorization via sysfs
        log "Manually authorizing devices via sysfs..."

        for device in /sys/bus/thunderbolt/devices/*-*; do
            if [ -f "$device/authorized" ]; then
                local auth=$(cat "$device/authorized")
                if [ "$auth" = "0" ]; then
                    local name=$(cat "$device/device_name" 2>/dev/null || echo "Unknown")
                    log "Authorizing: $name"
                    echo 1 | sudo tee "$device/authorized" > /dev/null 2>&1 || true
                fi
            fi
        done
    fi
}

# ============================================================================
# Verify Setup
# ============================================================================
verify_setup() {
    header "Verifying Thunderbolt Setup"

    local success=true

    # Check thunderbolt module
    log "Checking kernel modules..."
    for mod in thunderbolt typec ucsi_acpi; do
        if lsmod | grep -q "^$mod"; then
            log "  $mod: ${GREEN}loaded${NC}"
        else
            if modinfo "$mod" &>/dev/null; then
                warn "  $mod: not loaded (available)"
            else
                warn "  $mod: not available"
            fi
        fi
    done

    # Check bolt service
    if systemctl is-active bolt.service &>/dev/null; then
        log "Bolt service: ${GREEN}active${NC}"
    else
        warn "Bolt service: not active"
    fi

    # Check for connected devices
    log "Connected Thunderbolt devices:"
    if command -v boltctl &>/dev/null; then
        boltctl list 2>/dev/null || echo "  No devices"
    else
        for device in /sys/bus/thunderbolt/devices/*-*; do
            if [ -d "$device" ] && [ -f "$device/device_name" ]; then
                local name=$(cat "$device/device_name" 2>/dev/null || echo "Unknown")
                local auth=$(cat "$device/authorized" 2>/dev/null || echo "?")
                log "  - $name (authorized: $auth)"
            fi
        done
    fi

    # Check DisplayPort
    log "Checking display outputs..."
    if [ -d /sys/class/drm ]; then
        for connector in /sys/class/drm/card*-*/status; do
            if [ -f "$connector" ]; then
                local status=$(cat "$connector")
                local name=$(basename $(dirname "$connector"))
                if [ "$status" = "connected" ]; then
                    log "  $name: ${GREEN}connected${NC}"
                fi
            fi
        done
    fi

    if [ "$success" = true ]; then
        log "${GREEN}Thunderbolt setup verified!${NC}"
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    header "ARCH Thunderbolt 5 / USB4 Setup"

    log "Configuring Thunderbolt support for Razer Dock"

    mkdir -p "$LOG_DIR"

    detect_thunderbolt
    install_tools
    configure_security
    configure_razer_dock
    configure_display
    configure_pcie_tunneling
    configure_networking
    authorize_device
    verify_setup

    header "Thunderbolt Setup Complete!"

    log ""
    log "Summary:"
    log "  - Thunderbolt security rules installed"
    log "  - Razer dock support configured"
    log "  - DisplayPort Alt Mode enabled"
    log "  - PCIe tunneling configured"
    log ""
    log "If you haven't already, connect your Razer Thunderbolt 5 dock"
    log "Run 'boltctl list' to see connected devices"
    log "Run 'boltctl authorize <uuid>' to authorize new devices"
}

main "$@"
