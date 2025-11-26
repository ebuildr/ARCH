#!/bin/bash
#
# ARCH NVIDIA Driver Fix - Troubleshoot and repair NVIDIA RTX 5090 drivers
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/logs"
FIX_LOG="${LOG_DIR}/nvidia-fix-$(date +%Y%m%d-%H%M%S).log"

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

header "NVIDIA RTX 5090 Driver Fix"

log "Fix log: $FIX_LOG"

# ============================================================================
# Step 1: Remove conflicting drivers
# ============================================================================
header "Step 1: Remove Conflicting Drivers"

log "Checking for nouveau driver..."
if lsmod | grep -q nouveau; then
    warn "nouveau driver is loaded - removing..."
    sudo rmmod nouveau 2>/dev/null || warn "Could not unload nouveau (may need reboot)"
fi

log "Blacklisting nouveau..."
sudo mkdir -p /etc/modprobe.d
cat << 'EOF' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
# Blacklist nouveau driver (conflicts with NVIDIA proprietary)
blacklist nouveau
options nouveau modeset=0
EOF

log "Blacklisting nvidiafb (can cause issues)..."
cat << 'EOF' | sudo tee /etc/modprobe.d/blacklist-nvidiafb.conf
# Blacklist nvidiafb (legacy framebuffer driver)
blacklist nvidiafb
blacklist rivafb
blacklist rivatv
blacklist nv
EOF

# ============================================================================
# Step 2: Install correct NVIDIA packages
# ============================================================================
header "Step 2: Install NVIDIA Driver Packages"

log "Determining kernel type..."
KERNEL_VERSION=$(uname -r)
if [[ "$KERNEL_VERSION" == *"lts"* ]]; then
    NVIDIA_PKG="nvidia-lts"
    log "Detected LTS kernel: using $NVIDIA_PKG"
elif [[ "$KERNEL_VERSION" == *"zen"* ]]; then
    NVIDIA_PKG="nvidia-zen"
    log "Detected Zen kernel: using $NVIDIA_PKG"
else
    NVIDIA_PKG="nvidia"
    log "Detected standard kernel: using $NVIDIA_PKG"
fi

log "Installing NVIDIA packages for RTX 5090 (Blackwell)..."
info "This requires NVIDIA driver 570+..."

# For custom kernels, always use DKMS
if [[ "$KERNEL_VERSION" == *"arch-custom"* ]] || [[ "$KERNEL_VERSION" == *"custom"* ]]; then
    log "Custom kernel detected - using nvidia-dkms"
    NVIDIA_PKG="nvidia-dkms"
fi

log "Installing: $NVIDIA_PKG nvidia-utils nvidia-settings"
sudo pacman -S --needed --noconfirm $NVIDIA_PKG nvidia-utils nvidia-settings 2>&1 | tee -a "$FIX_LOG"

log "Installing additional NVIDIA components..."
sudo pacman -S --needed --noconfirm \
    libglvnd \
    egl-wayland \
    libvdpau \
    libva-nvidia-driver \
    opencl-nvidia \
    2>&1 | tee -a "$FIX_LOG"

# ============================================================================
# Step 3: Ensure kernel headers are installed
# ============================================================================
header "Step 3: Verify Kernel Headers"

log "Kernel version: $KERNEL_VERSION"
log "Checking for matching kernel headers..."

HEADERS_PATH="/usr/lib/modules/${KERNEL_VERSION}/build"
if [ -d "$HEADERS_PATH" ]; then
    log "${GREEN}✓${NC} Kernel headers found: $HEADERS_PATH"
else
    error "Kernel headers NOT found for $KERNEL_VERSION"

    if [[ "$KERNEL_VERSION" == *"lts"* ]]; then
        log "Installing linux-lts-headers..."
        sudo pacman -S --needed --noconfirm linux-lts-headers
    elif [[ "$KERNEL_VERSION" == *"zen"* ]]; then
        log "Installing linux-zen-headers..."
        sudo pacman -S --needed --noconfirm linux-zen-headers
    else
        log "Installing linux-headers..."
        sudo pacman -S --needed --noconfirm linux-headers
    fi
fi

# ============================================================================
# Step 4: Configure NVIDIA module parameters
# ============================================================================
header "Step 4: Configure NVIDIA Module Parameters"

log "Creating NVIDIA modprobe configuration..."
cat << 'EOF' | sudo tee /etc/modprobe.d/nvidia.conf
# NVIDIA RTX 5090 (Blackwell) Configuration
# Enable DRM kernel mode setting (required for Wayland)
options nvidia-drm modeset=1 fbdev=1

# Enable GSP firmware (required for RTX 5090/Blackwell)
options nvidia NVreg_EnableGpuFirmware=1

# Power management for laptops
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp

# Dynamic power management
options nvidia NVreg_DynamicPowerManagement=0x02

# Preserve video memory across suspend/resume
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

log "NVIDIA module parameters configured for RTX 5090"

# ============================================================================
# Step 5: Configure initramfs
# ============================================================================
header "Step 5: Configure Initramfs"

log "Updating mkinitcpio.conf..."
if ! grep -q "nvidia nvidia_modeset nvidia_uvm nvidia_drm" /etc/mkinitcpio.conf; then
    sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
    log "Added NVIDIA modules to mkinitcpio.conf"
else
    log "NVIDIA modules already in mkinitcpio.conf"
fi

log "Regenerating initramfs for all kernels..."
sudo mkinitcpio -P 2>&1 | tee -a "$FIX_LOG"

# ============================================================================
# Step 6: Rebuild DKMS modules
# ============================================================================
header "Step 6: Rebuild DKMS Modules"

if command -v dkms &>/dev/null; then
    log "Checking DKMS status..."
    dkms status | tee -a "$FIX_LOG"

    log "Removing old NVIDIA DKMS builds..."
    for ver in $(dkms status | grep nvidia | awk -F', ' '{print $1}' | awk -F': ' '{print $2}' | sort -u); do
        sudo dkms remove nvidia/$ver --all 2>/dev/null || true
    done

    log "Rebuilding NVIDIA DKMS modules..."
    sudo dkms autoinstall 2>&1 | tee -a "$FIX_LOG"

    log "DKMS status after rebuild:"
    dkms status | tee -a "$FIX_LOG"
else
    warn "DKMS not installed"
    info "Install with: sudo pacman -S dkms"
fi

# ============================================================================
# Step 7: Configure Xorg (if using X11)
# ============================================================================
header "Step 7: Configure Xorg"

log "Creating Xorg NVIDIA configuration..."
sudo mkdir -p /etc/X11/xorg.conf.d/

cat << 'EOF' | sudo tee /etc/X11/xorg.conf.d/10-nvidia.conf
# NVIDIA RTX 5090 Xorg Configuration
Section "Device"
    Identifier "NVIDIA GeForce RTX 5090"
    Driver "nvidia"
    VendorName "NVIDIA Corporation"

    # Enable GSP firmware (Blackwell requirement)
    Option "EnableGpuFirmware" "1"

    # DRM mode setting
    Option "DRM" "on"

    # Allow external GPUs (Thunderbolt eGPUs)
    Option "AllowExternalGpus" "True"
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Option "AllowNVIDIAGPUScreens"
EndSection
EOF

log "Xorg configuration created"

# ============================================================================
# Step 8: Configure systemd service for NVIDIA
# ============================================================================
header "Step 8: Enable NVIDIA System Services"

log "Enabling NVIDIA suspend/resume services..."
sudo systemctl enable nvidia-suspend.service 2>/dev/null || info "nvidia-suspend.service not available"
sudo systemctl enable nvidia-hibernate.service 2>/dev/null || info "nvidia-hibernate.service not available"
sudo systemctl enable nvidia-resume.service 2>/dev/null || info "nvidia-resume.service not available"
sudo systemctl enable nvidia-persistenced.service 2>/dev/null || info "nvidia-persistenced.service not available"

# ============================================================================
# Step 9: Test NVIDIA driver
# ============================================================================
header "Step 9: Load NVIDIA Modules (Test)"

log "Attempting to load NVIDIA modules..."
sudo modprobe nvidia 2>&1 | tee -a "$FIX_LOG" || warn "Could not load nvidia module (may need reboot)"
sudo modprobe nvidia_modeset 2>&1 | tee -a "$FIX_LOG" || warn "Could not load nvidia_modeset"
sudo modprobe nvidia_uvm 2>&1 | tee -a "$FIX_LOG" || warn "Could not load nvidia_uvm"
sudo modprobe nvidia_drm 2>&1 | tee -a "$FIX_LOG" || warn "Could not load nvidia_drm"

log ""
log "Checking loaded NVIDIA modules:"
lsmod | grep nvidia | tee -a "$FIX_LOG" || warn "No NVIDIA modules loaded"

# ============================================================================
# Summary
# ============================================================================
header "NVIDIA Driver Fix Complete"

log ""
log "Summary of changes:"
log "  ✓ Nouveau driver blacklisted"
log "  ✓ NVIDIA $NVIDIA_PKG installed"
log "  ✓ Kernel headers verified"
log "  ✓ Module parameters configured for RTX 5090"
log "  ✓ Initramfs regenerated"
log "  ✓ DKMS modules rebuilt"
log "  ✓ Xorg configured"
log "  ✓ System services enabled"
log ""

if lsmod | grep -q nvidia; then
    log "${GREEN}✓ NVIDIA modules are loaded!${NC}"
    log ""
    log "Testing nvidia-smi..."
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi | tee -a "$FIX_LOG" || warn "nvidia-smi failed - reboot may be required"
    fi
else
    warn "NVIDIA modules not loaded yet"
    info "This is expected - modules will load on next boot"
fi

log ""
log "${YELLOW}IMPORTANT: Reboot required for all changes to take effect${NC}"
log ""
log "After reboot, verify with:"
log "  nvidia-smi"
log "  lsmod | grep nvidia"
log "  glxinfo | grep NVIDIA"
log ""
log "Full log saved to: $FIX_LOG"
