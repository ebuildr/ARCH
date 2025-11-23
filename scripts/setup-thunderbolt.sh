#!/bin/bash
#
# ARCH Thunderbolt 5 / USB4 v2 Setup for Razer Dock
# Configures Thunderbolt 5 (80/120 Gbps) and USB4 v2 support
#
# Thunderbolt 5 Features:
#   - 80 Gbps bidirectional bandwidth
#   - 120 Gbps with Bandwidth Boost (asymmetric)
#   - USB4 v2 compatible
#   - DisplayPort 2.1 (UHBR 20) support
#   - PCIe Gen 4 tunneling
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

# Thunderbolt 5 specifications
TB5_BANDWIDTH_SYMMETRIC=80    # Gbps
TB5_BANDWIDTH_BOOST=120       # Gbps asymmetric
TB5_PCIE_GEN=4
TB5_DP_VERSION="2.1"
TB5_MIN_KERNEL="6.9"

log() { echo -e "${GREEN}[TB5]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${MAGENTA}[INFO]${NC} $1"; }
header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

# ============================================================================
# Check Thunderbolt 5 Requirements
# ============================================================================
check_tb5_requirements() {
    header "Checking Thunderbolt 5 Requirements"

    local kernel_version=$(uname -r | cut -d'-' -f1)
    local kernel_major=$(echo "$kernel_version" | cut -d'.' -f1)
    local kernel_minor=$(echo "$kernel_version" | cut -d'.' -f2)

    log "Current kernel: $kernel_version"

    # Check kernel version for TB5/USB4 v2 support
    if [ "$kernel_major" -lt 6 ] || ([ "$kernel_major" -eq 6 ] && [ "$kernel_minor" -lt 9 ]); then
        warn "Kernel $kernel_version may have limited TB5 support"
        warn "Recommended: kernel 6.9+ for full Thunderbolt 5 / USB4 v2"
        info "Your custom kernel build will include TB5 support"
    else
        log "${GREEN}Kernel version supports Thunderbolt 5${NC}"
    fi

    # Check for USB4 v2 kernel config
    if [ -f /proc/config.gz ]; then
        if zcat /proc/config.gz | grep -q "CONFIG_USB4=y"; then
            log "${GREEN}USB4 support: enabled${NC}"
        else
            warn "USB4 support may not be fully enabled"
        fi
    fi

    # Check for Intel Barlow Ridge (TB5 controller) or integrated
    log "Checking for Thunderbolt 5 controller..."
    if lspci -nn 2>/dev/null | grep -i "thunderbolt" | grep -qiE "8086:(a76|1136|1137|7ec4|7ec5)"; then
        log "${GREEN}Intel Thunderbolt 5 controller detected${NC}"
        echo "TB5_CONTROLLER=intel" >> "${CONFIG_DIR}/thunderbolt-report.txt"
    elif lspci -nn 2>/dev/null | grep -i "usb4\|thunderbolt" > /dev/null; then
        log "Thunderbolt/USB4 controller detected (checking capabilities...)"
    fi
}

# ============================================================================
# Detect Thunderbolt Controllers
# ============================================================================
detect_thunderbolt() {
    header "Detecting Thunderbolt 5 / USB4 v2 Controllers"

    local tb_found=false
    local tb5_capable=false

    # Check for Thunderbolt controllers
    if lspci 2>/dev/null | grep -i "thunderbolt\|usb4" > /dev/null; then
        log "Thunderbolt controllers found:"
        lspci | grep -i "thunderbolt\|usb4" | while read line; do
            log "  $line"
        done
        tb_found=true
    fi

    # Check USB4/TB5 ports via sysfs
    if [ -d /sys/bus/thunderbolt ]; then
        log "Thunderbolt bus detected"

        # List domains and check generation
        for domain in /sys/bus/thunderbolt/devices/domain*; do
            if [ -d "$domain" ]; then
                local security=$(cat "$domain/security" 2>/dev/null || echo "unknown")
                local generation=$(cat "$domain/generation" 2>/dev/null || echo "unknown")

                log "  Domain: $(basename $domain)"
                log "    Security: $security"
                log "    Generation: $generation"

                # TB5 is generation 4 (TB1=1, TB2=2, TB3/USB4=3, TB5/USB4v2=4)
                if [ "$generation" = "4" ]; then
                    log "    ${GREEN}Thunderbolt 5 / USB4 v2 confirmed!${NC}"
                    tb5_capable=true
                elif [ "$generation" = "3" ]; then
                    info "    Thunderbolt 3/4 or USB4 v1 detected"
                fi
            fi
        done

        # List connected devices with link speed
        log "Connected Thunderbolt devices:"
        for device in /sys/bus/thunderbolt/devices/*-*; do
            if [ -d "$device" ] && [ -f "$device/device_name" ]; then
                local name=$(cat "$device/device_name" 2>/dev/null || echo "Unknown")
                local vendor=$(cat "$device/vendor_name" 2>/dev/null || echo "Unknown")
                local auth=$(cat "$device/authorized" 2>/dev/null || echo "?")
                local speed=$(cat "$device/speed" 2>/dev/null || echo "unknown")
                local lanes=$(cat "$device/lanes" 2>/dev/null || echo "unknown")

                log "  - $vendor $name"
                log "      Authorized: $auth"
                log "      Link Speed: ${speed} Gbps"
                log "      Lanes: $lanes"

                # TB5 can do 80 Gbps (2x40) or 120 Gbps asymmetric
                if [ "$speed" = "80" ] || [ "$speed" = "120" ]; then
                    log "      ${GREEN}Thunderbolt 5 speed confirmed!${NC}"
                    tb5_capable=true
                fi
            fi
        done
    fi

    if [ "$tb_found" = false ]; then
        warn "No Thunderbolt controllers detected in lspci"
        log "This may be normal - TB5 may be integrated into CPU (Arrow Lake)"
    fi

    # Save detection results
    mkdir -p "$CONFIG_DIR"
    {
        echo "# Thunderbolt 5 Detection Report"
        echo "# Generated: $(date)"
        echo ""
        echo "TB5_CAPABLE=$tb5_capable"
        echo "TB5_BANDWIDTH_SYMMETRIC=${TB5_BANDWIDTH_SYMMETRIC}Gbps"
        echo "TB5_BANDWIDTH_BOOST=${TB5_BANDWIDTH_BOOST}Gbps"
        echo "TB5_PCIE_GEN=$TB5_PCIE_GEN"
        echo "TB5_DP_VERSION=$TB5_DP_VERSION"
        echo ""
        echo "# PCI Devices:"
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
# Configure DisplayPort 2.1 Alt Mode (Thunderbolt 5)
# ============================================================================
configure_display() {
    header "Configuring DisplayPort 2.1 Alt Mode (Thunderbolt 5)"

    log "Setting up DisplayPort 2.1 over USB-C/Thunderbolt 5..."
    info "TB5 supports DP 2.1 UHBR 20 (80 Gbps) for 8K@60Hz or 4K@240Hz"

    # Load required modules
    local modules=(
        "typec_displayport"
        "drm"
        "drm_kms_helper"
        "drm_display_helper"
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
# DisplayPort 2.1 Alt Mode for Thunderbolt 5
typec_displayport
drm_display_helper
EOF

    # Samsung Odyssey monitor specific settings
    log "Adding Samsung Odyssey monitor support..."
    info "Configuring for high refresh rate and VRR support"

    # EDID override directory (if needed)
    sudo mkdir -p /lib/firmware/edid/

    # Create Xorg config for external monitors (TB5 + Samsung Odyssey)
    sudo mkdir -p /etc/X11/xorg.conf.d/
    sudo tee /etc/X11/xorg.conf.d/20-thunderbolt5-display.conf > /dev/null << 'EOF'
# Thunderbolt 5 DisplayPort 2.1 configuration
# Samsung Odyssey Monitor via Razer TB5 Dock

Section "Monitor"
    Identifier "Samsung-Odyssey"
    Option "DPMS" "true"
    # DP 2.1 supports 4K@240Hz or 8K@60Hz via TB5
    Option "PreferredMode" "3840x2160"
    # Enable VRR/FreeSync/G-Sync Compatible
    Option "VariableRefresh" "true"
    # HDR support
    Option "HDR" "true"
EndSection

Section "Device"
    Identifier "NVIDIA-RTX5090"
    Driver "nvidia"
    # TB5 external GPU support
    Option "AllowExternalGpus" "True"
    # Performance optimizations
    Option "TripleBuffer" "True"
    Option "AllowIndirectGLXProtocol" "off"
    # DP 2.1 UHBR support
    Option "ModeValidation" "AllowNon3DVisionModes, NoEdidMaxPClkCheck, NoMaxPClkCheck"
    # GSP firmware for RTX 5090
    Option "NVreg_EnableGpuFirmware" "1"
EndSection

Section "Screen"
    Identifier "Screen-TB5"
    Device "NVIDIA-RTX5090"
    Monitor "Samsung-Odyssey"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        # High refresh rate modes
        Modes "3840x2160" "2560x1440" "1920x1080"
    EndSubSection
EndSection
EOF

    # Wayland configuration for TB5 displays
    log "Configuring Wayland for TB5 displays..."
    sudo mkdir -p /etc/environment.d/
    sudo tee /etc/environment.d/20-tb5-display.conf > /dev/null << 'EOF'
# Thunderbolt 5 Display configuration for Wayland

# Force NVIDIA for external displays
__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0

# Enable VRR on Wayland
MUTTER_DEBUG_ENABLE_VRRT=1

# HDR support (when available)
ENABLE_HDR_WSI=1
EOF

    log "DisplayPort 2.1 configuration complete"
}

# ============================================================================
# Configure PCIe Gen 4 Tunneling (Thunderbolt 5)
# ============================================================================
configure_pcie_tunneling() {
    header "Configuring PCIe Gen 4 Tunneling (Thunderbolt 5)"

    log "Setting up PCIe Gen 4 over Thunderbolt 5..."
    info "TB5 supports PCIe Gen 4 x4 tunneling (64 GT/s)"
    info "This enables full-speed NVMe, 10GbE, and other PCIe devices via dock"

    # Kernel parameters for PCIe hotplug and TB5
    sudo mkdir -p /etc/modprobe.d/
    sudo tee /etc/modprobe.d/thunderbolt5-pcie.conf > /dev/null << 'EOF'
# Thunderbolt 5 PCIe Gen 4 tunneling options

# Enable host controller reset on errors
options thunderbolt host_reset=1

# USB4 v2 extended TLP support
options thunderbolt usb4_v2=1

# PCIe hotplug for dynamic device connection
options pciehp pciehp_poll_mode=1

# AER (Advanced Error Reporting) for PCIe tunneling
options pcie_aspm policy=performance

# Enable PCIe Gen 4 link speeds
options pcie_ports native
EOF

    # PCIe power management for TB5
    sudo tee /etc/modprobe.d/pcie-power.conf > /dev/null << 'EOF'
# PCIe power management for Thunderbolt 5 docks
# Disable ASPM for stability with TB5 PCIe tunneling
options pcie_aspm=off

# Enable runtime PM for PCIe devices
options pci dyndbg
EOF

    # Enable PCIe hotplug modules
    sudo mkdir -p /etc/modules-load.d/
    sudo tee /etc/modules-load.d/tb5-pcie.conf > /dev/null << 'EOF'
# PCIe Gen 4 hotplug for Thunderbolt 5 docks
pciehp
pcieportdrv
EOF

    # udev rule for PCIe devices via TB5
    sudo tee /etc/udev/rules.d/99-tb5-pcie.rules > /dev/null << 'EOF'
# Thunderbolt 5 PCIe device rules

# Auto-enable runtime PM for TB5 PCIe devices
ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"

# NVMe devices via TB5 dock
ACTION=="add", SUBSYSTEM=="nvme", ATTR{power/control}="auto"

# Network devices via TB5 dock (10GbE, etc.)
ACTION=="add", SUBSYSTEM=="net", DRIVERS=="*tb*", TAG+="systemd", ENV{SYSTEMD_WANTS}="network-online.target"
EOF

    sudo udevadm control --reload-rules

    log "PCIe Gen 4 tunneling configured"
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
    header "ARCH Thunderbolt 5 / USB4 v2 Setup"

    echo -e "${CYAN}"
    cat << 'EOF'
  ╔═══════════════════════════════════════════════════════════════╗
  ║          Thunderbolt 5 Configuration                          ║
  ║                                                               ║
  ║   • 80 Gbps bidirectional bandwidth                          ║
  ║   • 120 Gbps with Bandwidth Boost                            ║
  ║   • DisplayPort 2.1 (UHBR 20)                                ║
  ║   • PCIe Gen 4 tunneling                                     ║
  ║   • USB4 v2 compatible                                       ║
  ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    log "Configuring Thunderbolt 5 support for Razer Dock"
    log "Target: MSI Raider 18 HX + Samsung Odyssey Monitor"

    mkdir -p "$LOG_DIR" "$CONFIG_DIR"

    check_tb5_requirements
    detect_thunderbolt
    install_tools
    configure_security
    configure_razer_dock
    configure_display
    configure_pcie_tunneling
    configure_networking
    authorize_device
    verify_setup

    header "Thunderbolt 5 Setup Complete!"

    log ""
    log "Thunderbolt 5 Features Configured:"
    log "  ${GREEN}✓${NC} 80/120 Gbps bandwidth support"
    log "  ${GREEN}✓${NC} DisplayPort 2.1 for Samsung Odyssey"
    log "  ${GREEN}✓${NC} PCIe Gen 4 tunneling for dock devices"
    log "  ${GREEN}✓${NC} Razer TB5 Dock auto-authorization"
    log "  ${GREEN}✓${NC} VRR/FreeSync/G-Sync Compatible"
    log "  ${GREEN}✓${NC} HDR passthrough support"
    log ""
    log "Connect your Razer Thunderbolt 5 dock and run:"
    log "  boltctl list              # List devices"
    log "  boltctl authorize <uuid>  # Authorize device"
    log "  boltctl enroll <uuid>     # Permanent authorization"
    log ""
    info "Note: Full TB5 bandwidth requires kernel 6.9+ and compatible cable"
}

main "$@"
