#!/bin/bash
#
# ARCH NVIDIA Driver Builder for RTX 5090 (Blackwell SM120)
# Builds and installs the latest NVIDIA drivers for EndeavourOS
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build/nvidia"
LOG_DIR="${PROJECT_ROOT}/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# NVIDIA Configuration
# RTX 5090 requires driver 570+ with Blackwell support
NVIDIA_DRIVER_BRANCH="${NVIDIA_DRIVER_BRANCH:-570}"
USE_OPEN_KERNEL="${USE_OPEN_KERNEL:-yes}"
DKMS_INSTALL="${DKMS_INSTALL:-yes}"

log() { echo -e "${GREEN}[NVIDIA]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

# ============================================================================
# Detect NVIDIA GPU
# ============================================================================
detect_nvidia_gpu() {
    header "Detecting NVIDIA GPU"

    if ! lspci 2>/dev/null | grep -i nvidia > /dev/null; then
        error "No NVIDIA GPU detected!"
        return 1
    fi

    local gpu_info=$(lspci -nn | grep -i nvidia | head -1)
    log "Detected: $gpu_info"

    # Extract PCI ID
    local pci_id=$(echo "$gpu_info" | grep -oP '\[\w{4}:\w{4}\]' | tr -d '[]')
    log "PCI ID: $pci_id"

    # Check for RTX 50 series (Blackwell)
    if echo "$gpu_info" | grep -qiE "5090|5080|5070|50[0-9]{2}"; then
        log "${GREEN}Detected RTX 50 series (Blackwell/SM120)${NC}"
        echo "BLACKWELL=yes"

        # RTX 5090 requires driver 570+
        if [ "${NVIDIA_DRIVER_BRANCH}" -lt 570 ]; then
            warn "RTX 5090 requires driver 570+, updating branch"
            NVIDIA_DRIVER_BRANCH=570
        fi
    fi

    # Save GPU info
    mkdir -p "${PROJECT_ROOT}/config"
    cat > "${PROJECT_ROOT}/config/nvidia-gpu.txt" << EOF
GPU_INFO="$gpu_info"
PCI_ID="$pci_id"
DRIVER_BRANCH=$NVIDIA_DRIVER_BRANCH
ARCHITECTURE=Blackwell
SM_VERSION=120
EOF
}

# ============================================================================
# Check Dependencies
# ============================================================================
check_dependencies() {
    header "Checking Dependencies"

    local deps=(
        "gcc" "make" "linux-headers" "dkms" "pkg-config"
    )

    local missing=()

    # Check for kernel headers
    local kernel_version=$(uname -r)
    if [ ! -d "/usr/lib/modules/${kernel_version}/build" ]; then
        missing+=("linux-headers")
    fi

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null && ! pacman -Qi "$dep" &>/dev/null 2>&1; then
            case "$dep" in
                "linux-headers") continue ;; # Already checked
                *) missing+=("$dep") ;;
            esac
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log "Installing missing dependencies: ${missing[*]}"
        sudo pacman -S --needed --noconfirm "${missing[@]}" || {
            # Try installing linux-headers for current kernel
            sudo pacman -S --needed --noconfirm linux-headers base-devel dkms
        }
    fi

    log "All dependencies satisfied"
}

# ============================================================================
# Get Latest Driver Version
# ============================================================================
get_latest_driver_version() {
    header "Fetching Latest Driver Version"

    local version=""

    # Try NVIDIA's version API
    log "Querying NVIDIA for latest ${NVIDIA_DRIVER_BRANCH}.xx driver..."

    # Method 1: Check NVIDIA download page
    version=$(curl -s "https://download.nvidia.com/XFree86/Linux-x86_64/" 2>/dev/null | \
        grep -oP "${NVIDIA_DRIVER_BRANCH}\.[0-9]+\.[0-9]+" | sort -V | tail -1) || true

    # Method 2: Use known latest version
    if [ -z "$version" ]; then
        case "$NVIDIA_DRIVER_BRANCH" in
            570) version="570.86.16" ;;  # Latest 570 branch for Blackwell
            565) version="565.77" ;;
            560) version="560.35.03" ;;
            *) version="${NVIDIA_DRIVER_BRANCH}.00" ;;
        esac
        warn "Using fallback version: $version"
    fi

    log "Latest driver version: $version"
    echo "$version"
}

# ============================================================================
# Install via Arch Packages (Recommended)
# ============================================================================
install_via_pacman() {
    header "Installing NVIDIA Driver via Pacman"

    log "This is the recommended method for EndeavourOS"

    # Determine which packages to install
    local packages=()

    if [ "$USE_OPEN_KERNEL" = "yes" ]; then
        log "Using NVIDIA Open Kernel Modules (recommended for RTX 5090)"
        packages+=("nvidia-open" "nvidia-open-dkms")
    else
        log "Using NVIDIA Proprietary Kernel Modules"
        packages+=("nvidia" "nvidia-dkms")
    fi

    # Common packages
    packages+=(
        "nvidia-utils"
        "nvidia-settings"
        "lib32-nvidia-utils"
        "opencl-nvidia"
        "cuda"
        "cuda-tools"
    )

    # For latest drivers, might need chaotic-aur or AUR
    log "Checking for beta/latest drivers in repos..."

    # Try official repos first
    if pacman -Ss nvidia-open &>/dev/null; then
        log "Installing from official repositories..."
        sudo pacman -S --needed --noconfirm "${packages[@]}" || {
            warn "Some packages not available, trying alternatives..."
        }
    fi

    # Enable nvidia-drm modeset
    log "Configuring NVIDIA DRM modeset..."
    sudo mkdir -p /etc/modprobe.d/
    echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf

    # Early KMS
    log "Enabling early KMS for NVIDIA..."
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    if [ -f "$mkinitcpio_conf" ]; then
        if ! grep -q "nvidia" "$mkinitcpio_conf"; then
            sudo sed -i 's/MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$mkinitcpio_conf"
            sudo mkinitcpio -P
        fi
    fi

    log "NVIDIA driver installation complete!"
}

# ============================================================================
# Build from Source (Alternative)
# ============================================================================
build_from_source() {
    local version="$1"

    header "Building NVIDIA Driver from Source"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    local driver_file="NVIDIA-Linux-x86_64-${version}.run"
    local download_url="https://download.nvidia.com/XFree86/Linux-x86_64/${version}/${driver_file}"

    # Download driver
    if [ ! -f "$driver_file" ]; then
        log "Downloading NVIDIA driver ${version}..."
        wget -q --show-progress "$download_url" -O "$driver_file" || {
            error "Failed to download driver"
            return 1
        }
        chmod +x "$driver_file"
    fi

    # Extract without installing
    log "Extracting driver package..."
    ./"$driver_file" --extract-only

    local extracted_dir="NVIDIA-Linux-x86_64-${version}"

    if [ ! -d "$extracted_dir" ]; then
        error "Extraction failed"
        return 1
    fi

    cd "$extracted_dir"

    # Build options for RTX 5090
    log "Building kernel modules..."

    local build_opts=""
    if [ "$USE_OPEN_KERNEL" = "yes" ]; then
        build_opts="--kernel-source-path=/usr/src/linux"
        log "Building Open Kernel Modules..."
        cd kernel-open
    else
        cd kernel
    fi

    # Build
    make -j$(nproc) NV_VERBOSE=1 2>&1 | tee "${LOG_DIR}/nvidia-build.log"

    log "Kernel modules built successfully"

    # DKMS setup
    if [ "$DKMS_INSTALL" = "yes" ]; then
        log "Setting up DKMS..."

        local dkms_dir="/usr/src/nvidia-${version}"
        sudo mkdir -p "$dkms_dir"

        # Copy source
        cd "$BUILD_DIR/$extracted_dir"
        sudo cp -r kernel "$dkms_dir/"
        sudo cp -r kernel-open "$dkms_dir/" 2>/dev/null || true

        # Create dkms.conf
        sudo tee "$dkms_dir/dkms.conf" > /dev/null << EOF
PACKAGE_NAME="nvidia"
PACKAGE_VERSION="${version}"
BUILT_MODULE_NAME[0]="nvidia"
BUILT_MODULE_NAME[1]="nvidia-modeset"
BUILT_MODULE_NAME[2]="nvidia-uvm"
BUILT_MODULE_NAME[3]="nvidia-drm"
DEST_MODULE_LOCATION[0]="/updates/dkms"
DEST_MODULE_LOCATION[1]="/updates/dkms"
DEST_MODULE_LOCATION[2]="/updates/dkms"
DEST_MODULE_LOCATION[3]="/updates/dkms"
AUTOINSTALL="yes"
EOF

        sudo dkms add -m nvidia -v "$version" 2>/dev/null || true
        sudo dkms build -m nvidia -v "$version"
        sudo dkms install -m nvidia -v "$version"
    fi

    log "NVIDIA driver build complete"
}

# ============================================================================
# Configure for Optimus (Hybrid Graphics)
# ============================================================================
configure_optimus() {
    header "Configuring NVIDIA Optimus (Hybrid Graphics)"

    log "MSI Raider 18 HX uses hybrid graphics (Intel + NVIDIA)"

    # Install optimus-manager or prime-run
    log "Installing PRIME render offload support..."

    # Create prime-run script if not exists
    if ! command -v prime-run &>/dev/null; then
        sudo tee /usr/local/bin/prime-run > /dev/null << 'EOF'
#!/bin/bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
exec "$@"
EOF
        sudo chmod +x /usr/local/bin/prime-run
    fi

    # Xorg configuration for hybrid mode
    sudo mkdir -p /etc/X11/xorg.conf.d/
    sudo tee /etc/X11/xorg.conf.d/10-nvidia-optimus.conf > /dev/null << 'EOF'
Section "ServerLayout"
    Identifier "layout"
    Option "AllowNVIDIAGPUScreens"
EndSection

Section "Device"
    Identifier "intel"
    Driver "modesetting"
    BusID "PCI:0:2:0"
    Option "TearFree" "true"
EndSection

Section "Device"
    Identifier "nvidia"
    Driver "nvidia"
    Option "AllowEmptyInitialConfiguration"
EndSection
EOF

    # Environment variables for Wayland
    log "Configuring for Wayland/GNOME/KDE..."
    sudo mkdir -p /etc/environment.d/
    sudo tee /etc/environment.d/10-nvidia.conf > /dev/null << 'EOF'
# NVIDIA environment for Wayland
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
LIBVA_DRIVER_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1
EOF

    log "Optimus configuration complete"
    log "Use 'prime-run <application>' to run apps on NVIDIA GPU"
}

# ============================================================================
# Configure Power Management
# ============================================================================
configure_power_management() {
    header "Configuring Power Management"

    log "Setting up NVIDIA power management for laptops..."

    # udev rules for power management
    sudo tee /etc/udev/rules.d/80-nvidia-pm.rules > /dev/null << 'EOF'
# Enable runtime PM for NVIDIA GPU
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"

# Enable runtime PM for NVIDIA audio
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", TEST=="power/control", ATTR{power/control}="auto"
EOF

    # NVIDIA persistence daemon
    log "Enabling NVIDIA persistence daemon..."
    sudo systemctl enable nvidia-persistenced.service 2>/dev/null || true

    # Suspend/Resume hooks
    log "Setting up suspend/resume hooks..."
    sudo mkdir -p /usr/lib/systemd/system-sleep/
    sudo tee /usr/lib/systemd/system-sleep/nvidia > /dev/null << 'EOF'
#!/bin/bash

case $1 in
    pre)
        # Before suspend
        /usr/bin/nvidia-smi -pm 0 2>/dev/null || true
        ;;
    post)
        # After resume
        /usr/bin/nvidia-smi -pm 1 2>/dev/null || true
        ;;
esac
EOF
    sudo chmod +x /usr/lib/systemd/system-sleep/nvidia

    log "Power management configured"
}

# ============================================================================
# Verify Installation
# ============================================================================
verify_installation() {
    header "Verifying NVIDIA Installation"

    local success=true

    # Check kernel modules
    log "Checking kernel modules..."
    for mod in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
        if lsmod | grep -q "^$mod"; then
            log "  $mod: ${GREEN}loaded${NC}"
        else
            warn "  $mod: not loaded"
            success=false
        fi
    done

    # Check nvidia-smi
    log "Checking nvidia-smi..."
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
        log "  ${GREEN}nvidia-smi working${NC}"
    else
        warn "  nvidia-smi not found"
        success=false
    fi

    # Check Vulkan
    log "Checking Vulkan support..."
    if command -v vulkaninfo &>/dev/null; then
        vulkaninfo --summary 2>/dev/null | grep -i nvidia && log "  ${GREEN}Vulkan working${NC}" || warn "  Vulkan not detected"
    fi

    # Check OpenGL
    log "Checking OpenGL..."
    if command -v glxinfo &>/dev/null; then
        glxinfo | grep "OpenGL renderer" | head -1
    fi

    if [ "$success" = true ]; then
        log "${GREEN}NVIDIA installation verified successfully!${NC}"
    else
        warn "Some components may need a reboot to work properly"
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    header "ARCH NVIDIA Driver Builder for RTX 5090"

    log "Driver branch: ${NVIDIA_DRIVER_BRANCH}"
    log "Open kernel modules: ${USE_OPEN_KERNEL}"

    mkdir -p "$BUILD_DIR" "$LOG_DIR"

    detect_nvidia_gpu
    check_dependencies

    local version=$(get_latest_driver_version)

    # Determine installation method
    local install_method="${INSTALL_METHOD:-pacman}"

    case "$install_method" in
        pacman)
            install_via_pacman
            ;;
        source)
            build_from_source "$version"
            ;;
        *)
            log "Using pacman (default for EndeavourOS)"
            install_via_pacman
            ;;
    esac

    configure_optimus
    configure_power_management
    verify_installation

    header "NVIDIA Setup Complete!"
    log "Driver: ${version}"
    log "GPU: RTX 5090 (Blackwell/SM120)"
    log ""
    log "Please reboot to complete the installation"
    log "After reboot, verify with: nvidia-smi"
}

main "$@"
