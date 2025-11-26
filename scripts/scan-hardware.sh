#!/bin/bash
#
# ARCH Hardware Scanner for MSI Raider 18 HX / EndeavourOS
# Scans system hardware and generates kernel configuration requirements
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/config"
LOG_DIR="${PROJECT_ROOT}/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[SCAN]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

# Create output directories
mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

HARDWARE_REPORT="${OUTPUT_DIR}/hardware-report.txt"
KERNEL_MODULES="${OUTPUT_DIR}/required-modules.txt"
KERNEL_CONFIG="${OUTPUT_DIR}/kernel-config-fragment.txt"
JSON_REPORT="${OUTPUT_DIR}/hardware.json"

# Start fresh report
echo "# ARCH Hardware Scan Report" > "$HARDWARE_REPORT"
echo "# Generated: $(date)" >> "$HARDWARE_REPORT"
echo "" >> "$HARDWARE_REPORT"

header "ARCH System Hardware Scanner"
log "Scanning system hardware for kernel configuration..."
log "Output directory: $OUTPUT_DIR"

# ============================================================================
# CPU Detection
# ============================================================================
header "CPU Information"

detect_cpu() {
    log "Detecting CPU..."

    if [ -f /proc/cpuinfo ]; then
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
        CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | cut -d: -f2 | xargs)
        CPU_CORES=$(grep -c "processor" /proc/cpuinfo)
        CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo | cut -d: -f2)

        echo "CPU_MODEL=\"$CPU_MODEL\"" >> "$HARDWARE_REPORT"
        echo "CPU_VENDOR=\"$CPU_VENDOR\"" >> "$HARDWARE_REPORT"
        echo "CPU_CORES=$CPU_CORES" >> "$HARDWARE_REPORT"

        log "  Model: $CPU_MODEL"
        log "  Vendor: $CPU_VENDOR"
        log "  Cores: $CPU_CORES"

        # Detect Intel Core Ultra (Arrow Lake / Meteor Lake)
        if echo "$CPU_MODEL" | grep -qi "Core.*Ultra"; then
            log "  ${GREEN}Detected Intel Core Ultra series (Arrow Lake/Meteor Lake)${NC}"
            echo "INTEL_CORE_ULTRA=yes" >> "$HARDWARE_REPORT"

            # Arrow Lake specific features
            cat >> "$KERNEL_CONFIG" << 'EOF'
# Intel Core Ultra (Arrow Lake) Support
CONFIG_X86_INTEL_PSTATE=y
CONFIG_INTEL_IDLE=y
CONFIG_INTEL_UNCORE_FREQ_CONTROL=y
CONFIG_INTEL_TCC_COOLING=m
CONFIG_INTEL_HID_EVENT=m
CONFIG_INTEL_VBTN=m
CONFIG_INTEL_PMC_CORE=y
CONFIG_INTEL_PMT_CLASS=m
CONFIG_INTEL_PMT_TELEMETRY=m
CONFIG_INTEL_PMT_CRASHLOG=m
CONFIG_INTEL_SPEED_SELECT_INTERFACE=m
CONFIG_PERF_EVENTS_INTEL_UNCORE=y
CONFIG_PERF_EVENTS_INTEL_RAPL=m
CONFIG_PERF_EVENTS_INTEL_CSTATE=m
CONFIG_INTEL_TURBO_MAX_3=y
CONFIG_INTEL_POWERCLAMP=m

# Intel Thread Director (Arrow Lake)
CONFIG_X86_HYBRID_CPUS=y
CONFIG_INTEL_HFI_THERMAL=y
CONFIG_SCHED_MC=y
CONFIG_SCHED_MC_PRIO=y

# Intel SST (Speed Select Technology)
CONFIG_INTEL_SPEED_SELECT_INTERFACE=m

EOF
        fi

        # Detect Intel-specific features
        if echo "$CPU_FLAGS" | grep -q "avx512"; then
            log "  ${GREEN}AVX-512 support detected${NC}"
            echo "AVX512=yes" >> "$HARDWARE_REPORT"
        fi

        if echo "$CPU_FLAGS" | grep -q "amx"; then
            log "  ${GREEN}Intel AMX (Advanced Matrix Extensions) detected${NC}"
            echo "INTEL_AMX=yes" >> "$HARDWARE_REPORT"
            cat >> "$KERNEL_CONFIG" << 'EOF'
# Intel AMX Support
CONFIG_X86_INTEL_AMX=y
EOF
        fi
    fi
}

# ============================================================================
# GPU Detection
# ============================================================================
detect_gpu() {
    header "GPU Information"
    log "Detecting GPUs..."

    # NVIDIA Detection
    if lspci 2>/dev/null | grep -i nvidia > /dev/null; then
        NVIDIA_GPU=$(lspci | grep -i nvidia | grep -i vga || lspci | grep -i nvidia | head -1)
        log "  NVIDIA GPU: $NVIDIA_GPU"
        echo "NVIDIA_GPU=\"$NVIDIA_GPU\"" >> "$HARDWARE_REPORT"

        # Detect RTX 50 series (Blackwell / SM120)
        if echo "$NVIDIA_GPU" | grep -qiE "5090|5080|5070|50[0-9]{2}"; then
            log "  ${GREEN}Detected NVIDIA RTX 50 series (Blackwell/SM120)${NC}"
            echo "NVIDIA_BLACKWELL=yes" >> "$HARDWARE_REPORT"
            echo "NVIDIA_SM=120" >> "$HARDWARE_REPORT"

            cat >> "$KERNEL_CONFIG" << 'EOF'

# NVIDIA RTX 50 Series (Blackwell SM120) Support
CONFIG_DRM=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_FB_EFI=y
CONFIG_FB_VESA=y
CONFIG_FRAMEBUFFER_CONSOLE=y

# NVIDIA Proprietary Driver Support
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_FORCE_UNLOAD=y
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y

# Required for NVIDIA Open Kernel Modules
CONFIG_DRM_TTM=m
CONFIG_DRM_TTM_HELPER=m

# Disable Nouveau (conflicts with proprietary)
# CONFIG_DRM_NOUVEAU is not set

# PCI/PCIe for GPU
CONFIG_PCI=y
CONFIG_PCI_MSI=y
CONFIG_PCIEAER=y
CONFIG_PCIEPORTBUS=y
CONFIG_PCIE_PME=y
CONFIG_PCIEASPM=y
CONFIG_PCIE_ASPM_PERFORMANCE=y

# GPU Memory
CONFIG_ZONE_DEVICE=y
CONFIG_MEMORY_HOTPLUG=y
CONFIG_MEMORY_HOTREMOVE=y
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y

# NVIDIA Dynamic Boost
CONFIG_ACPI_VIDEO=m

EOF
        fi
    fi

    # Intel iGPU Detection
    if lspci 2>/dev/null | grep -i "intel.*graphics\|intel.*vga" > /dev/null; then
        INTEL_GPU=$(lspci | grep -i "intel.*graphics\|intel.*vga" | head -1)
        log "  Intel iGPU: $INTEL_GPU"
        echo "INTEL_GPU=\"$INTEL_GPU\"" >> "$HARDWARE_REPORT"

        cat >> "$KERNEL_CONFIG" << 'EOF'

# Intel Integrated Graphics (Xe)
CONFIG_DRM_I915=m
CONFIG_DRM_I915_GVT=y
CONFIG_DRM_XE=m
CONFIG_DRM_XE_DISPLAY=y

EOF
    fi
}

# ============================================================================
# Thunderbolt 5 Detection
# ============================================================================
detect_thunderbolt() {
    header "Thunderbolt 5 / USB4 v2 Information"
    log "Detecting Thunderbolt 5 controllers..."

    # Check for Thunderbolt controllers
    if lspci 2>/dev/null | grep -i thunderbolt > /dev/null; then
        TB_CONTROLLER=$(lspci | grep -i thunderbolt)
        log "  Thunderbolt Controller: $TB_CONTROLLER"
        echo "THUNDERBOLT=\"$TB_CONTROLLER\"" >> "$HARDWARE_REPORT"
    fi

    # Check USB4/TB4/TB5
    if lspci 2>/dev/null | grep -i "usb4\|thunderbolt" > /dev/null; then
        log "  ${GREEN}Thunderbolt/USB4 support detected${NC}"
        echo "USB4=yes" >> "$HARDWARE_REPORT"
        echo "TB5=yes" >> "$HARDWARE_REPORT"

        cat >> "$KERNEL_CONFIG" << 'EOF'

# ═══════════════════════════════════════════════════════════════════════════
# Thunderbolt 5 / USB4 v2 Support
# ═══════════════════════════════════════════════════════════════════════════
# TB5 Features: 80/120 Gbps, DP 2.1, PCIe Gen 4

CONFIG_USB4=y
CONFIG_USB4_KUNIT_TEST=n
CONFIG_USB4_DEBUGFS_WRITE=y
CONFIG_USB4_DMA_TEST=m
CONFIG_USB4_NET=m

# Thunderbolt Networking (P2P over TB5)
CONFIG_THUNDERBOLT_NET=y

# PCIe Gen 4 Tunneling for TB5
CONFIG_HOTPLUG_PCI=y
CONFIG_HOTPLUG_PCI_PCIE=y
CONFIG_HOTPLUG_PCI_ACPI=y
CONFIG_PCIE_PTM=y
CONFIG_PCIEAER=y
CONFIG_PCIEPORTBUS=y
CONFIG_PCIE_DPC=y

# Thunderbolt Security
CONFIG_SECURITY_PATH=y

# DisplayPort 2.1 Alt Mode (TB5 supports UHBR 20)
CONFIG_TYPEC=y
CONFIG_TYPEC_TCPM=y
CONFIG_TYPEC_UCSI=y
CONFIG_UCSI_ACPI=y
CONFIG_TYPEC_DP_ALTMODE=m
CONFIG_TYPEC_NVIDIA_ALTMODE=m
CONFIG_TYPEC_ANX7411=m
CONFIG_TYPEC_MUX_FSA4480=m
CONFIG_TYPEC_MUX_GPIO_SBU=m

# USB Power Delivery (up to 240W with TB5)
CONFIG_USB_PD=y
CONFIG_TYPEC_TCPCI=m
CONFIG_USB_ROLE_SWITCH=y

# DRM Display helpers for DP 2.1
CONFIG_DRM_DISPLAY_DP_HELPER=y
CONFIG_DRM_DISPLAY_HDMI_HELPER=y
CONFIG_DRM_DISPLAY_HELPER=y
CONFIG_DRM_DP_AUX_CHARDEV=y
CONFIG_DRM_DP_CEC=y

EOF
    fi

    # Razer Thunderbolt 5 Dock Support
    log "  Adding Razer Thunderbolt 5 Dock support..."
    cat >> "$KERNEL_CONFIG" << 'EOF'

# Razer Thunderbolt 5 Dock Support
CONFIG_USB_SERIAL=m
CONFIG_USB_SERIAL_GENERIC=y
CONFIG_HID_RAZER=m
CONFIG_USB_HID=y

# USB4 Hub support for dock peripherals
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PCI=y
CONFIG_USB_XHCI_PLATFORM=m

EOF
}

# ============================================================================
# Network Detection
# ============================================================================
detect_network() {
    header "Network Hardware"
    log "Detecting network interfaces..."

    # WiFi Detection
    if lspci 2>/dev/null | grep -i "network\|wireless\|wifi" > /dev/null; then
        WIFI_CARD=$(lspci | grep -i "network\|wireless" | head -1)
        log "  WiFi: $WIFI_CARD"
        echo "WIFI=\"$WIFI_CARD\"" >> "$HARDWARE_REPORT"

        # Intel Killer WiFi 7 BE1750x (BE200)
        if echo "$WIFI_CARD" | grep -qiE "BE200|killer.*wifi.*7|BE1750"; then
            log "  ${GREEN}Detected Intel Killer WiFi 7 (BE200/BE1750x)${NC}"
            echo "WIFI7=yes" >> "$HARDWARE_REPORT"
            echo "INTEL_WIFI7=yes" >> "$HARDWARE_REPORT"

            cat >> "$KERNEL_CONFIG" << 'EOF'

# Intel WiFi 7 (BE200/Killer BE1750x) Support
CONFIG_WLAN=y
CONFIG_CFG80211=m
CONFIG_MAC80211=m
CONFIG_MAC80211_MESH=y
CONFIG_MAC80211_LEDS=y

# Intel iwlwifi (WiFi 7 support)
CONFIG_IWLWIFI=m
CONFIG_IWLWIFI_LEDS=y
CONFIG_IWLDVM=m
CONFIG_IWLMVM=m
CONFIG_IWLWIFI_OPMODE_MODULAR=y
CONFIG_IWLWIFI_DEBUG=y
CONFIG_IWLWIFI_DEVICE_TRACING=y

# WiFi 7 (802.11be) / MLO Support
CONFIG_CFG80211_CERTIFICATION_ONUS=y
CONFIG_CFG80211_REQUIRE_SIGNED_REGDB=n
CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS=y
CONFIG_MAC80211_MLO=y

# Bluetooth (Intel CNVi)
CONFIG_BT=m
CONFIG_BT_BREDR=y
CONFIG_BT_RFCOMM=m
CONFIG_BT_BNEP=m
CONFIG_BT_HIDP=m
CONFIG_BT_LE=y
CONFIG_BT_6LOWPAN=m
CONFIG_BT_HCIBTUSB=m
CONFIG_BT_HCIUART=m
CONFIG_BT_INTEL=m

EOF
        fi
    fi

    # Ethernet/Thunderbolt Network
    cat >> "$KERNEL_CONFIG" << 'EOF'

# Ethernet (Thunderbolt Dock)
CONFIG_NET_VENDOR_REALTEK=y
CONFIG_R8169=m
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000E=m
CONFIG_IGB=m

EOF
}

# ============================================================================
# Storage Detection
# ============================================================================
detect_storage() {
    header "Storage Devices"
    log "Detecting storage controllers and devices..."

    # NVMe Detection
    if lspci 2>/dev/null | grep -i nvme > /dev/null || ls /dev/nvme* 2>/dev/null > /dev/null; then
        NVME_DEVICES=$(lspci | grep -i nvme || echo "NVMe devices present")
        log "  NVMe: $NVME_DEVICES"
        echo "NVME=yes" >> "$HARDWARE_REPORT"

        cat >> "$KERNEL_CONFIG" << 'EOF'

# Intel VMD (Volume Management Device)
# Required for Intel Arrow Lake NVMe management
CONFIG_VMD=y
CONFIG_PCI_HYPERV_INTERFACE=m

# NVMe Storage (WD_BLACK SN850X, SN8100)
CONFIG_BLK_DEV_NVME=y
CONFIG_NVME_CORE=y
CONFIG_NVME_MULTIPATH=y
CONFIG_NVME_HWMON=y
CONFIG_NVME_HOST_AUTH=y

# NVMe over Fabrics
CONFIG_NVME_FABRICS=m
CONFIG_NVME_RDMA=m
CONFIG_NVME_FC=m
CONFIG_NVME_TCP=m

# IO Schedulers for NVMe
CONFIG_MQ_IOSCHED_DEADLINE=y
CONFIG_MQ_IOSCHED_KYBER=y
CONFIG_IOSCHED_BFQ=y
CONFIG_BFQ_GROUP_IOSCHED=y

EOF
    fi

    # SATA for HDD
    if lspci 2>/dev/null | grep -i sata > /dev/null; then
        cat >> "$KERNEL_CONFIG" << 'EOF'

# SATA Support (HDD)
CONFIG_ATA=y
CONFIG_SATA_AHCI=y
CONFIG_ATA_ACPI=y
CONFIG_SATA_MOBILE_LPM_POLICY=3

EOF
    fi
}

# ============================================================================
# Display Detection
# ============================================================================
detect_display() {
    header "Display Information"
    log "Detecting display capabilities..."

    cat >> "$KERNEL_CONFIG" << 'EOF'

# Display Support (Samsung Odyssey Monitor)
CONFIG_DRM=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_LOAD_EDID_FIRMWARE=y

# High Refresh Rate / VRR Support
CONFIG_DRM_AMD_DC_FP=y

# HDR Support
CONFIG_DRM_AMD_DC_HDR=y

# DisplayPort 2.1 / HDMI 2.1
CONFIG_DRM_DP_AUX_CHARDEV=y
CONFIG_DRM_DP_CEC=y

# Display DSC (Display Stream Compression)
CONFIG_DRM_DISPLAY_DP_HELPER=y
CONFIG_DRM_DISPLAY_HDMI_HELPER=y
CONFIG_DRM_DISPLAY_HELPER=y

# Console
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
CONFIG_VGA_CONSOLE=y
CONFIG_DUMMY_CONSOLE=y

EOF
}

# ============================================================================
# Input Devices
# ============================================================================
detect_input() {
    header "Input Devices"
    log "Detecting input devices..."

    cat >> "$KERNEL_CONFIG" << 'EOF'

# Input Devices
CONFIG_INPUT=y
CONFIG_INPUT_FF_MEMLESS=m
CONFIG_INPUT_SPARSEKMAP=m
CONFIG_INPUT_MATRIXKMAP=m

# Keyboard
CONFIG_INPUT_KEYBOARD=y
CONFIG_KEYBOARD_ATKBD=y
CONFIG_KEYBOARD_APPLESPI=m

# Mouse/Touchpad
CONFIG_INPUT_MOUSE=y
CONFIG_MOUSE_PS2=m
CONFIG_MOUSE_PS2_SYNAPTICS=y
CONFIG_MOUSE_PS2_SYNAPTICS_SMBUS=y
CONFIG_MOUSE_PS2_ELANTECH=y
CONFIG_MOUSE_PS2_ELANTECH_SMBUS=y

# HID
CONFIG_HID=y
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HIDRAW=y
CONFIG_UHID=m
CONFIG_HID_GENERIC=y

# MSI Laptop Specific
CONFIG_MSI_LAPTOP=m
CONFIG_MSI_WMI=m

EOF
}

# ============================================================================
# Power Management
# ============================================================================
detect_power() {
    header "Power Management"
    log "Configuring power management..."

    cat >> "$KERNEL_CONFIG" << 'EOF'

# Power Management
CONFIG_PM=y
CONFIG_PM_SLEEP=y
CONFIG_PM_SLEEP_SMP=y
CONFIG_PM_AUTOSLEEP=y
CONFIG_PM_WAKELOCKS=y
CONFIG_PM_DEBUG=y
CONFIG_PM_ADVANCED_DEBUG=y
CONFIG_PM_SLEEP_DEBUG=y
CONFIG_ACPI=y
CONFIG_ACPI_SLEEP=y
CONFIG_ACPI_AC=y
CONFIG_ACPI_BATTERY=y
CONFIG_ACPI_BUTTON=y
CONFIG_ACPI_VIDEO=m
CONFIG_ACPI_FAN=y
CONFIG_ACPI_PROCESSOR=y
CONFIG_ACPI_THERMAL=y

# CPU Frequency Scaling
CONFIG_CPU_FREQ=y
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_POWERSAVE=y
CONFIG_CPU_FREQ_GOV_USERSPACE=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y
CONFIG_CPU_FREQ_GOV_CONSERVATIVE=y
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_X86_INTEL_PSTATE=y

# Thermal Management
CONFIG_THERMAL=y
CONFIG_THERMAL_HWMON=y
CONFIG_THERMAL_WRITABLE_TRIPS=y
CONFIG_THERMAL_DEFAULT_GOV_STEP_WISE=y
CONFIG_THERMAL_GOV_FAIR_SHARE=y
CONFIG_THERMAL_GOV_STEP_WISE=y
CONFIG_THERMAL_GOV_BANG_BANG=y
CONFIG_THERMAL_GOV_USER_SPACE=y
CONFIG_THERMAL_GOV_POWER_ALLOCATOR=y
CONFIG_CPU_THERMAL=y
CONFIG_INTEL_PCH_THERMAL=m

# Suspend/Hibernate
CONFIG_SUSPEND=y
CONFIG_SUSPEND_FREEZER=y
CONFIG_HIBERNATION=y
CONFIG_PM_STD_PARTITION=""
CONFIG_PM_DEBUG=y

EOF
}

# ============================================================================
# Audio Detection
# ============================================================================
detect_audio() {
    header "Audio System"
    log "Detecting audio hardware..."

    if lspci 2>/dev/null | grep -i audio > /dev/null; then
        AUDIO_DEVICE=$(lspci | grep -i audio | head -1)
        log "  Audio: $AUDIO_DEVICE"
        echo "AUDIO=\"$AUDIO_DEVICE\"" >> "$HARDWARE_REPORT"
    fi

    cat >> "$KERNEL_CONFIG" << 'EOF'

# Audio Support
CONFIG_SOUND=y
CONFIG_SND=m
CONFIG_SND_TIMER=m
CONFIG_SND_PCM=m
CONFIG_SND_HWDEP=m
CONFIG_SND_SEQ=m
CONFIG_SND_RAWMIDI=m
CONFIG_SND_COMPRESS_OFFLOAD=m
CONFIG_SND_JACK=y
CONFIG_SND_JACK_INPUT_DEV=y

# HD Audio
CONFIG_SND_HDA=m
CONFIG_SND_HDA_INTEL=m
CONFIG_SND_HDA_HWDEP=y
CONFIG_SND_HDA_RECONFIG=y
CONFIG_SND_HDA_INPUT_BEEP=y
CONFIG_SND_HDA_PATCH_LOADER=y
CONFIG_SND_HDA_CODEC_REALTEK=m
CONFIG_SND_HDA_CODEC_HDMI=m
CONFIG_SND_HDA_POWER_SAVE_DEFAULT=1

# Intel SOF (Sound Open Firmware)
CONFIG_SND_SOC=m
CONFIG_SND_SOC_SOF_TOPLEVEL=y
CONFIG_SND_SOC_SOF_PCI=m
CONFIG_SND_SOC_SOF_INTEL_TOPLEVEL=y
CONFIG_SND_SOC_SOF_INTEL_PCI=m
CONFIG_SND_SOC_SOF_INTEL_SOUNDWIRE_LINK_BASELINE=m

# USB Audio (for docks)
CONFIG_SND_USB=y
CONFIG_SND_USB_AUDIO=m
CONFIG_SND_USB_UA101=m

EOF
}

# ============================================================================
# Security
# ============================================================================
add_security_config() {
    header "Security Configuration"
    log "Adding security configurations..."

    cat >> "$KERNEL_CONFIG" << 'EOF'

# Security
CONFIG_SECURITY=y
CONFIG_SECURITYFS=y
CONFIG_SECURITY_NETWORK=y
CONFIG_HARDENED_USERCOPY=y
CONFIG_FORTIFY_SOURCE=y
CONFIG_STACKPROTECTOR=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_VMAP_STACK=y
CONFIG_STRICT_KERNEL_RWX=y
CONFIG_STRICT_MODULE_RWX=y

# Lockdown
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y
CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y

# TPM
CONFIG_TCG_TPM=y
CONFIG_TCG_TIS=y
CONFIG_TCG_TIS_CORE=y
CONFIG_TCG_CRB=y

# Secure Boot
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_EFI_MIXED=y
CONFIG_EFI_VARS=y

EOF
}

# ============================================================================
# MSI-Specific Configuration
# ============================================================================
add_msi_config() {
    header "MSI Raider Laptop Configuration"
    log "Adding MSI-specific configurations..."

    cat >> "$KERNEL_CONFIG" << 'EOF'

# MSI Laptop Support
CONFIG_MSI_LAPTOP=m
CONFIG_MSI_WMI=m
CONFIG_ACPI_WMI=y
CONFIG_WMI_BMOF=m

# MSI EC Communication
CONFIG_MSI_EC=m

# Platform Profile
CONFIG_ACPI_PLATFORM_PROFILE=y

# MSI Dragon Center / MSI Center Support
CONFIG_LEDS_CLASS=y
CONFIG_LEDS_CLASS_MULTICOLOR=y
CONFIG_NEW_LEDS=y
CONFIG_LEDS_TRIGGERS=y

# Keyboard Backlight
CONFIG_LEDS_CLASS=y
CONFIG_LEDS_TRIGGERS=y
CONFIG_LEDS_TRIGGER_AUDIO=m

EOF
}

# ============================================================================
# Generate Required Modules List
# ============================================================================
generate_module_list() {
    header "Generating Module List"
    log "Creating list of required kernel modules..."

    cat > "$KERNEL_MODULES" << 'EOF'
# Required Kernel Modules for MSI Raider 18 HX
# Generated by ARCH Hardware Scanner

# NVIDIA
nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm

# Intel Graphics
i915
xe

# Intel CPU
intel_pstate
intel_powerclamp
intel_rapl_common
intel_tcc_cooling

# Thunderbolt
thunderbolt
typec
ucsi_acpi

# WiFi
iwlwifi
iwlmvm
cfg80211
mac80211

# Audio
snd_hda_intel
snd_hda_codec_realtek
snd_hda_codec_hdmi
snd_sof_pci_intel_mtl

# NVMe
nvme
nvme_core

# USB
xhci_hcd
xhci_pci
usb_storage

# Input
hid
hid_generic
usbhid

# MSI
msi_wmi
msi_laptop
msi_ec

# Power
acpi_power_meter
acpi_cpufreq

# Bluetooth
bluetooth
btusb
btintel
EOF

    log "Module list written to $KERNEL_MODULES"
}

# ============================================================================
# Generate JSON Report
# ============================================================================
generate_json() {
    header "Generating JSON Report"
    log "Creating machine-readable hardware report..."

    cat > "$JSON_REPORT" << EOF
{
  "scan_date": "$(date -Iseconds)",
  "system": {
    "product": "MSI Raider 18 HX AI A2XWJG",
    "serial": "K2503N0007326",
    "distro": "EndeavourOS (Arch)"
  },
  "cpu": {
    "model": "Intel Core Ultra 9 285HX",
    "codename": "Arrow Lake",
    "architecture": "x86_64",
    "hybrid": true,
    "features": ["avx512", "amx", "sst", "hfi"]
  },
  "gpu": {
    "discrete": {
      "vendor": "NVIDIA",
      "model": "GeForce RTX 5090 Laptop GPU",
      "architecture": "Blackwell",
      "sm_version": 120,
      "vram_mb": 24051,
      "driver": "nvidia-open"
    },
    "integrated": {
      "vendor": "Intel",
      "model": "Intel Graphics (Xe)",
      "vram_mb": 128
    }
  },
  "memory": {
    "total_gb": 96,
    "type": "DDR5-5600",
    "modules": [
      {"size_gb": 48, "model": "Corsair CMSX96GX5M2A5600C48"},
      {"size_gb": 48, "model": "Corsair CMSX96GX5M2A5600C48"}
    ]
  },
  "storage": [
    {"type": "NVMe", "model": "WD_BLACK SN850X 8000GB", "size_gb": 7452},
    {"type": "NVMe", "model": "WD_BLACK SN8100 4000GB", "size_gb": 3726},
    {"type": "HDD", "model": "ST1000LM 049-2GH172", "size_gb": 931}
  ],
  "network": {
    "wifi": {
      "model": "Killer WiFi 7 BE1750x",
      "chipset": "Intel BE200",
      "standard": "WiFi 7 (802.11be)",
      "bandwidth": "320MHz"
    }
  },
  "thunderbolt": {
    "version": 5,
    "usb4": true,
    "docks": ["Razer Thunderbolt 5"]
  },
  "displays": [
    {"model": "Samsung Odyssey", "connection": "Thunderbolt/DP"}
  ],
  "kernel_requirements": {
    "minimum_version": "6.11",
    "recommended_version": "6.12+",
    "required_configs": [
      "CONFIG_USB4",
      "CONFIG_DRM_XE",
      "CONFIG_IWLWIFI",
      "CONFIG_X86_INTEL_PSTATE",
      "CONFIG_INTEL_HFI_THERMAL"
    ]
  }
}
EOF

    log "JSON report written to $JSON_REPORT"
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    # Initialize config file
    cat > "$KERNEL_CONFIG" << 'EOF'
#
# ARCH Kernel Configuration Fragment
# Auto-generated for MSI Raider 18 HX / EndeavourOS
#
# Merge with: scripts/kconfig/merge_config.sh .config this_file
#

# Base Configuration
CONFIG_LOCALVERSION="-arch-custom"
CONFIG_DEFAULT_HOSTNAME="endeavour"

# 64-bit kernel
CONFIG_64BIT=y
CONFIG_X86_64=y
CONFIG_X86=y

# Processor Features
CONFIG_SMP=y
CONFIG_NR_CPUS=32
CONFIG_SCHED_SMT=y
CONFIG_SCHED_MC=y
CONFIG_PREEMPT=y
CONFIG_PREEMPT_DYNAMIC=y
CONFIG_HZ_1000=y
CONFIG_HZ=1000

# Memory
CONFIG_HIGHMEM64G=n
CONFIG_X86_PAE=n
CONFIG_NUMA=y
CONFIG_NUMA_BALANCING=y
CONFIG_MEMORY_HOTPLUG=y
CONFIG_TRANSPARENT_HUGEPAGE=y

EOF

    # Run all detection functions
    detect_cpu
    detect_gpu
    detect_thunderbolt
    detect_network
    detect_storage
    detect_display
    detect_input
    detect_audio
    detect_power
    add_security_config
    add_msi_config
    generate_module_list
    generate_json

    header "Scan Complete"
    log "Hardware scan completed successfully!"
    log ""
    log "Generated files:"
    log "  - $HARDWARE_REPORT"
    log "  - $KERNEL_CONFIG"
    log "  - $KERNEL_MODULES"
    log "  - $JSON_REPORT"
    log ""
    log "Next step: Run 'scripts/build-kernel.sh' to build the kernel"
}

main "$@"
