#!/bin/bash
#
# ARCH - Arch Linux Custom Kernel & Hardware Builder
# Main orchestration script for EndeavourOS
#
# Supports:
#   - Intel Core Ultra 9 285HX (Arrow Lake)
#   - NVIDIA RTX 5090 (Blackwell SM120)
#   - Thunderbolt 5 / Razer Dock
#   - Samsung Odyssey Monitor
#   - Killer WiFi 7 BE1750x
#

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
CONFIG_DIR="${SCRIPT_DIR}/config"
BUILD_DIR="${SCRIPT_DIR}/build"
LOG_DIR="${SCRIPT_DIR}/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================================
# Banner
# ============================================================================
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    _    ____   ____ _   _
   / \  |  _ \ / ___| | | |
  / _ \ | |_) | |   | |_| |
 / ___ \|  _ <| |___|  _  |
/_/   \_\_| \_\\____|_| |_|

Arch Linux Custom Kernel & Hardware Builder
EOF
    echo -e "${NC}"
    echo -e "${WHITE}Version ${VERSION}${NC}"
    echo -e "${BLUE}For MSI Raider 18 HX / EndeavourOS${NC}"
    echo ""
}

# ============================================================================
# Logging
# ============================================================================
log() { echo -e "${GREEN}[ARCH]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() {
    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ============================================================================
# Help
# ============================================================================
show_help() {
    cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  scan          Scan system hardware and generate kernel configuration
  build         Build the custom kernel
  nvidia        Build/install NVIDIA drivers for RTX 5090
  thunderbolt   Configure Thunderbolt 5 / Razer dock
  monitor       Setup Samsung Odyssey monitor via DisplayPort
  all           Run complete setup (scan + build + nvidia + thunderbolt + monitor)
  status        Show current system status
  clean         Clean build directories

Options:
  -h, --help           Show this help message
  -v, --version        Show version
  -j, --jobs N         Number of parallel build jobs (default: auto)
  -k, --kernel VER     Specify kernel version (default: latest stable)
  --install            Install kernel after building
  --no-nvidia          Skip NVIDIA driver setup
  --no-thunderbolt     Skip Thunderbolt setup
  --no-monitor         Skip monitor setup

Examples:
  $(basename "$0") scan                    # Scan hardware only
  $(basename "$0") build                   # Build kernel with scanned config
  $(basename "$0") build --install         # Build and install kernel
  $(basename "$0") all --install           # Complete setup with installation
  $(basename "$0") nvidia                  # Install NVIDIA drivers only
  $(basename "$0") monitor                 # Setup Samsung Odyssey monitor

Environment Variables:
  KERNEL_MAJOR         Kernel major version (default: 6)
  KERNEL_MINOR         Kernel minor version (default: latest)
  JOBS                 Parallel build jobs (default: nproc)
  INSTALL_KERNEL       Install after build (yes/no)
  USE_OPEN_KERNEL      Use NVIDIA open modules (yes/no)

EOF
}

# ============================================================================
# Status
# ============================================================================
show_status() {
    header "System Status"

    # OS
    log "Operating System:"
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo "  Distribution: $NAME $VERSION"
    fi
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"

    # CPU
    log "CPU:"
    if [ -f /proc/cpuinfo ]; then
        echo "  Model: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
        echo "  Cores: $(nproc)"
    fi

    # Memory
    log "Memory:"
    free -h | grep Mem | awk '{print "  Total: " $2 ", Available: " $7}'

    # GPU
    log "Graphics:"
    lspci | grep -i "vga\|3d\|display" | while read line; do
        echo "  $line"
    done

    # NVIDIA Status
    if command -v nvidia-smi &>/dev/null; then
        log "NVIDIA Driver:"
        nvidia-smi --query-gpu=driver_version,name --format=csv,noheader 2>/dev/null | \
            while read line; do echo "  $line"; done
    fi

    # Thunderbolt
    log "Thunderbolt:"
    if [ -d /sys/bus/thunderbolt ]; then
        echo "  Status: Available"
        if command -v boltctl &>/dev/null; then
            boltctl list 2>/dev/null | head -5 || echo "  No devices connected"
        fi
    else
        echo "  Status: Not detected"
    fi

    # Storage
    log "Storage:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "nvme|sd" | while read line; do
        echo "  $line"
    done

    # Build Status
    log "Build Status:"
    if [ -f "${CONFIG_DIR}/hardware-report.txt" ]; then
        echo "  Hardware scan: Complete"
    else
        echo "  Hardware scan: Not run"
    fi
    if [ -d "${BUILD_DIR}/linux-"* ] 2>/dev/null; then
        echo "  Kernel build: In progress/complete"
        ls -d ${BUILD_DIR}/linux-* 2>/dev/null | while read d; do
            echo "    $(basename $d)"
        done
    else
        echo "  Kernel build: Not started"
    fi
}

# ============================================================================
# Clean
# ============================================================================
clean_build() {
    header "Cleaning Build Directories"

    read -p "This will remove all build files. Continue? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Removing build directory..."
        rm -rf "${BUILD_DIR}"

        log "Removing logs..."
        rm -rf "${LOG_DIR}"/*.log

        log "Clean complete"
    else
        log "Clean cancelled"
    fi
}

# ============================================================================
# Scan Hardware
# ============================================================================
run_scan() {
    header "Hardware Scan"

    if [ -f "${SCRIPTS_DIR}/scan-hardware.sh" ]; then
        bash "${SCRIPTS_DIR}/scan-hardware.sh"
    else
        error "scan-hardware.sh not found!"
        return 1
    fi
}

# ============================================================================
# Build Kernel
# ============================================================================
run_build() {
    header "Kernel Build"

    if [ -f "${SCRIPTS_DIR}/build-kernel.sh" ]; then
        bash "${SCRIPTS_DIR}/build-kernel.sh"
    else
        error "build-kernel.sh not found!"
        return 1
    fi
}

# ============================================================================
# NVIDIA Setup
# ============================================================================
run_nvidia() {
    header "NVIDIA Driver Setup"

    if [ -f "${SCRIPTS_DIR}/build-nvidia.sh" ]; then
        bash "${SCRIPTS_DIR}/build-nvidia.sh"
    else
        error "build-nvidia.sh not found!"
        return 1
    fi
}

# ============================================================================
# Thunderbolt Setup
# ============================================================================
run_thunderbolt() {
    header "Thunderbolt Setup"

    if [ -f "${SCRIPTS_DIR}/setup-thunderbolt.sh" ]; then
        bash "${SCRIPTS_DIR}/setup-thunderbolt.sh"
    else
        error "setup-thunderbolt.sh not found!"
        return 1
    fi
}

# ============================================================================
# Monitor Setup
# ============================================================================
run_monitor() {
    header "Monitor Setup"

    if [ -f "${SCRIPTS_DIR}/setup-monitor.sh" ]; then
        bash "${SCRIPTS_DIR}/setup-monitor.sh"
    else
        error "setup-monitor.sh not found!"
        return 1
    fi
}

# ============================================================================
# Complete Setup
# ============================================================================
run_all() {
    header "Complete System Setup"

    log "Starting complete ARCH setup..."
    log "This will:"
    log "  1. Scan your hardware"
    log "  2. Build a custom kernel"
    log "  3. Install NVIDIA RTX 5090 drivers"
    log "  4. Configure Thunderbolt 5 / Razer dock"
    log "  5. Setup Samsung Odyssey monitor"
    echo ""

    read -p "Continue with complete setup? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Setup cancelled"
        return 0
    fi

    local start_time=$(date +%s)

    # Step 1: Scan
    log "Step 1/5: Scanning hardware..."
    run_scan

    # Step 2: Build kernel
    if [ "${SKIP_KERNEL:-}" != "yes" ]; then
        log "Step 2/5: Building kernel..."
        run_build
    else
        log "Step 2/5: Skipping kernel build"
    fi

    # Step 3: NVIDIA
    if [ "${NO_NVIDIA:-}" != "yes" ]; then
        log "Step 3/5: Setting up NVIDIA drivers..."
        run_nvidia
    else
        log "Step 3/5: Skipping NVIDIA setup"
    fi

    # Step 4: Thunderbolt
    if [ "${NO_THUNDERBOLT:-}" != "yes" ]; then
        log "Step 4/5: Configuring Thunderbolt..."
        run_thunderbolt
    else
        log "Step 4/5: Skipping Thunderbolt setup"
    fi

    # Step 5: Monitor
    if [ "${NO_MONITOR:-}" != "yes" ]; then
        log "Step 5/5: Setting up Samsung Odyssey monitor..."
        run_monitor
    else
        log "Step 5/5: Skipping monitor setup"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))

    header "Setup Complete!"
    log "Total time: ${minutes} minutes"
    log ""
    log "Next steps:"
    log "  1. Review generated configurations in ${CONFIG_DIR}"
    log "  2. If kernel was built, install with: sudo make install"
    log "  3. Reboot to use new kernel and drivers"
    log "  4. After reboot, verify with: nvidia-smi && boltctl list"
    log "  5. Configure display with: xrandr --query"
}

# ============================================================================
# Parse Arguments
# ============================================================================
parse_args() {
    COMMAND=""
    JOBS="${JOBS:-$(nproc)}"
    INSTALL_KERNEL="${INSTALL_KERNEL:-no}"
    NO_NVIDIA="no"
    NO_THUNDERBOLT="no"
    NO_MONITOR="no"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            scan|build|nvidia|thunderbolt|monitor|all|status|clean)
                COMMAND="$1"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "ARCH version $VERSION"
                exit 0
                ;;
            -j|--jobs)
                JOBS="$2"
                shift 2
                ;;
            -k|--kernel)
                export KERNEL_MINOR="$2"
                shift 2
                ;;
            --install)
                export INSTALL_KERNEL="yes"
                shift
                ;;
            --no-nvidia)
                NO_NVIDIA="yes"
                shift
                ;;
            --no-thunderbolt)
                NO_THUNDERBOLT="yes"
                shift
                ;;
            --no-monitor)
                NO_MONITOR="yes"
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    export JOBS
    export NO_NVIDIA
    export NO_THUNDERBOLT
    export NO_MONITOR
}

# ============================================================================
# Main
# ============================================================================
main() {
    # Create directories
    mkdir -p "$CONFIG_DIR" "$BUILD_DIR" "$LOG_DIR"

    # Make scripts executable
    chmod +x "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true

    parse_args "$@"

    show_banner

    case "${COMMAND:-}" in
        scan)
            run_scan
            ;;
        build)
            run_build
            ;;
        nvidia)
            run_nvidia
            ;;
        thunderbolt)
            run_thunderbolt
            ;;
        monitor)
            run_monitor
            ;;
        all)
            run_all
            ;;
        status)
            show_status
            ;;
        clean)
            clean_build
            ;;
        "")
            log "No command specified. Use --help for usage."
            echo ""
            show_status
            ;;
        *)
            error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
