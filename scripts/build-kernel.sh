#!/bin/bash
#
# ARCH Kernel Builder for EndeavourOS
# Builds latest stable kernel with hardware-specific configurations
#
# Debug Mode: DEBUG=yes ./build-kernel.sh
# Verbose:    VERBOSE=yes ./build-kernel.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PROJECT_ROOT}/config"
BUILD_DIR="${PROJECT_ROOT}/build"
LOG_DIR="${PROJECT_ROOT}/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Kernel Configuration
KERNEL_MAJOR="${KERNEL_MAJOR:-6}"
KERNEL_MINOR="${KERNEL_MINOR:-}"
KERNEL_ORG_URL="https://www.kernel.org"
KERNEL_CDN="https://cdn.kernel.org/pub/linux/kernel"

# Build Options
JOBS="${JOBS:-$(nproc)}"
INSTALL_KERNEL="${INSTALL_KERNEL:-no}"
SIGN_MODULES="${SIGN_MODULES:-no}"

# Debug Options
DEBUG="${DEBUG:-no}"
VERBOSE="${VERBOSE:-no}"
RUN_TESTS="${RUN_TESTS:-yes}"

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { [ "$DEBUG" = "yes" ] && echo -e "${MAGENTA}[DEBUG]${NC} $1" || true; }
header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

# ============================================================================
# Check Dependencies
# ============================================================================
check_dependencies() {
    header "Checking Build Dependencies"

    local deps=(
        "gcc" "make" "flex" "bison" "bc" "perl" "openssl"
        "libelf" "pahole" "cpio" "xz" "zstd" "git" "wget" "curl"
    )

    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null && ! pacman -Qi "$dep" &>/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        warn "Missing dependencies: ${missing[*]}"
        log "Installing missing dependencies..."

        # Map generic names to Arch packages
        local arch_pkgs=()
        for dep in "${missing[@]}"; do
            case "$dep" in
                gcc) arch_pkgs+=("gcc") ;;
                libelf) arch_pkgs+=("libelf") ;;
                pahole) arch_pkgs+=("pahole") ;;
                openssl) arch_pkgs+=("openssl") ;;
                *) arch_pkgs+=("$dep") ;;
            esac
        done

        sudo pacman -S --needed --noconfirm base-devel bc libelf pahole cpio perl \
            openssl zstd xz wget curl git xmlto docbook-xsl kmod inetutils
    fi

    log "All dependencies satisfied"
}

# ============================================================================
# Fetch Latest Kernel Version
# ============================================================================
get_latest_kernel_version() {
    header "Fetching Latest Stable Kernel Version"

    # Try to get version from kernel.org
    log "Querying kernel.org for latest stable version..."

    local version=""

    # Method 1: Parse releases.json
    version=$(curl -s "https://www.kernel.org/releases.json" 2>/dev/null | \
        grep -oP '"version"\s*:\s*"\K[0-9]+\.[0-9]+(\.[0-9]+)?"' | \
        grep "^${KERNEL_MAJOR}\." | head -1) || true

    # Method 2: Parse kernel.org HTML
    if [ -z "$version" ]; then
        version=$(curl -s "https://www.kernel.org/" 2>/dev/null | \
            grep -oP 'linux-\K[0-9]+\.[0-9]+(\.[0-9]+)?' | \
            grep "^${KERNEL_MAJOR}\." | sort -V | tail -1) || true
    fi

    # Method 3: Fallback to known recent version
    if [ -z "$version" ]; then
        warn "Could not fetch version from kernel.org, using fallback"
        version="${KERNEL_MAJOR}.12.5"
    fi

    echo "$version"
}

# ============================================================================
# Download Kernel Source
# ============================================================================
download_kernel() {
    local version="$1"

    header "Downloading Kernel $version"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    local major_ver="${version%%.*}"
    local tarball="linux-${version}.tar.xz"
    local url="${KERNEL_CDN}/v${major_ver}.x/${tarball}"
    local sign_url="${url}.sign"

    if [ -d "linux-${version}" ]; then
        log "Kernel source already exists, skipping download"
        return 0
    fi

    if [ ! -f "$tarball" ]; then
        log "Downloading ${tarball}..."
        wget -q --show-progress "$url" -O "$tarball" || {
            error "Failed to download kernel"
            return 1
        }
    fi

    # Verify signature if available
    if [ "$SIGN_MODULES" = "yes" ]; then
        log "Downloading signature..."
        wget -q "$sign_url" -O "${tarball}.sign" 2>/dev/null || true

        if [ -f "${tarball}.sign" ]; then
            log "Importing kernel signing keys..."
            gpg --locate-keys torvalds@kernel.org gregkh@kernel.org 2>/dev/null || true

            log "Verifying signature..."
            xz -cd "$tarball" | gpg --verify "${tarball}.sign" - 2>/dev/null && \
                log "Signature verified!" || warn "Signature verification failed (continuing)"
        fi
    fi

    log "Extracting kernel source..."
    tar xf "$tarball"

    log "Kernel source ready at ${BUILD_DIR}/linux-${version}"
}

# ============================================================================
# Configure Kernel
# ============================================================================
configure_kernel() {
    local version="$1"
    local kernel_dir="${BUILD_DIR}/linux-${version}"

    header "Configuring Kernel"

    cd "$kernel_dir"

    # Start with Arch Linux default config if available
    if [ -f /proc/config.gz ]; then
        log "Using current running kernel config as base..."
        zcat /proc/config.gz > .config
    elif [ -f "/boot/config-$(uname -r)" ]; then
        log "Using installed kernel config as base..."
        cp "/boot/config-$(uname -r)" .config
    else
        log "Generating default x86_64 config..."
        make defconfig
    fi

    # Merge hardware-specific configuration
    if [ -f "${CONFIG_DIR}/kernel-config-fragment.txt" ]; then
        log "Merging hardware-specific configuration..."
        ./scripts/kconfig/merge_config.sh -m .config "${CONFIG_DIR}/kernel-config-fragment.txt"
    fi

    # Apply additional optimizations for modern hardware
    log "Applying optimizations for Intel Arrow Lake / RTX 5090..."

    ./scripts/config --set-str LOCALVERSION "-arch-custom"

    # CPU optimizations
    ./scripts/config --enable X86_64
    ./scripts/config --enable SMP
    ./scripts/config --set-val NR_CPUS 32
    ./scripts/config --enable NUMA
    ./scripts/config --enable SCHED_MC
    ./scripts/config --enable SCHED_SMT
    ./scripts/config --enable X86_INTEL_PSTATE
    ./scripts/config --enable INTEL_IDLE

    # Enable Intel Thread Director for hybrid CPUs
    ./scripts/config --enable X86_HYBRID_CPUS 2>/dev/null || true
    ./scripts/config --enable INTEL_HFI_THERMAL 2>/dev/null || true

    # Performance
    ./scripts/config --enable PREEMPT
    ./scripts/config --enable HZ_1000
    ./scripts/config --set-val HZ 1000

    # NVIDIA support (disable nouveau, prepare for proprietary)
    ./scripts/config --disable DRM_NOUVEAU
    ./scripts/config --module DRM
    ./scripts/config --enable DRM_KMS_HELPER

    # Thunderbolt 5 / USB4
    ./scripts/config --enable USB4
    ./scripts/config --enable TYPEC
    ./scripts/config --module TYPEC_UCSI
    ./scripts/config --module UCSI_ACPI

    # WiFi 7
    ./scripts/config --module CFG80211
    ./scripts/config --module MAC80211
    ./scripts/config --module IWLWIFI
    ./scripts/config --module IWLMVM

    # NVMe
    ./scripts/config --enable BLK_DEV_NVME
    ./scripts/config --enable NVME_CORE
    ./scripts/config --enable NVME_MULTIPATH

    # Audio
    ./scripts/config --module SND_HDA_INTEL
    ./scripts/config --module SND_HDA_CODEC_REALTEK
    ./scripts/config --module SND_HDA_CODEC_HDMI

    # Module signing (optional)
    if [ "$SIGN_MODULES" = "yes" ]; then
        ./scripts/config --enable MODULE_SIG
        ./scripts/config --enable MODULE_SIG_ALL
        ./scripts/config --set-str MODULE_SIG_HASH "sha512"
    fi

    # Update config for any dependencies
    log "Resolving config dependencies..."
    make olddefconfig

    log "Kernel configuration complete"
}

# ============================================================================
# Build Kernel
# ============================================================================
build_kernel() {
    local version="$1"
    local kernel_dir="${BUILD_DIR}/linux-${version}"

    header "Building Kernel"

    cd "$kernel_dir"

    local start_time=$(date +%s)

    log "Building with ${JOBS} parallel jobs..."
    log "This may take 15-60 minutes depending on your hardware..."

    # Build kernel and modules
    make -j${JOBS} 2>&1 | tee "${LOG_DIR}/kernel-build.log"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    log "Build completed in ${minutes}m ${seconds}s"
}

# ============================================================================
# Package Kernel (Arch-style)
# ============================================================================
package_kernel() {
    local version="$1"
    local kernel_dir="${BUILD_DIR}/linux-${version}"

    header "Creating Arch Package"

    cd "$kernel_dir"

    local pkg_dir="${BUILD_DIR}/packages"
    mkdir -p "$pkg_dir"

    # Create PKGBUILD for pacman
    cat > "${pkg_dir}/PKGBUILD" << EOF
# Maintainer: ARCH Custom Kernel Builder
pkgbase=linux-custom
pkgname=('linux-custom' 'linux-custom-headers')
pkgver=${version//-/_}
pkgrel=1
pkgdesc='Linux kernel optimized for MSI Raider 18 HX (Arrow Lake + RTX 5090)'
url='https://www.kernel.org/'
arch=(x86_64)
license=(GPL-2.0-only)
makedepends=(bc cpio gettext libelf pahole perl tar xz)
options=('!strip')

build() {
    # Kernel already built
    true
}

package_linux-custom() {
    pkgdesc="\${pkgdesc}"
    depends=(coreutils kmod initramfs)
    optdepends=('wireless-regdb: to set the correct wireless channels'
                'linux-firmware: firmware images needed for some devices'
                'nvidia-open: NVIDIA proprietary driver')
    provides=(VIRTUALBOX-GUEST-MODULES WIREGUARD-MODULE KSMBD-MODULE)

    cd "${kernel_dir}"

    local modulesdir="\$pkgdir/usr/lib/modules/${version}-arch-custom"

    # Install modules
    make INSTALL_MOD_PATH="\$pkgdir/usr" INSTALL_MOD_STRIP=1 modules_install

    # Install kernel image
    install -Dm644 arch/x86/boot/bzImage "\$modulesdir/vmlinuz"

    # Used by mkinitcpio to name the kernel
    echo "linux-custom" | install -Dm644 /dev/stdin "\$modulesdir/pkgbase"

    # Remove build and source links
    rm -f "\$modulesdir"/{source,build}
}

package_linux-custom-headers() {
    pkgdesc="Headers and scripts for building modules for Linux kernel"
    depends=('pahole')

    cd "${kernel_dir}"

    local builddir="\$pkgdir/usr/lib/modules/${version}-arch-custom/build"

    # Install headers
    install -Dt "\$builddir" -m644 .config Makefile Module.symvers System.map vmlinux
    install -Dt "\$builddir/kernel" -m644 kernel/Makefile
    install -Dt "\$builddir/arch/x86" -m644 arch/x86/Makefile
    cp -t "\$builddir" -a scripts

    # Install headers
    cp -t "\$builddir" -a include
    cp -t "\$builddir/arch/x86" -a arch/x86/include
    install -Dt "\$builddir/arch/x86/kernel" -m644 arch/x86/kernel/asm-offsets.s

    # Install objtool
    install -Dt "\$builddir/tools/objtool" tools/objtool/objtool 2>/dev/null || true

    # Required for external module builds
    install -Dt "\$builddir/tools/bpf/resolve_btfids" tools/bpf/resolve_btfids/resolve_btfids 2>/dev/null || true
}
EOF

    log "PKGBUILD created at ${pkg_dir}/PKGBUILD"

    # Also create installable packages directly
    log "Installing kernel modules to staging directory..."

    local staging="${pkg_dir}/staging"
    mkdir -p "$staging"

    make INSTALL_MOD_PATH="$staging" modules_install

    # Copy kernel image
    mkdir -p "${staging}/boot"
    cp arch/x86/boot/bzImage "${staging}/boot/vmlinuz-linux-custom"
    cp System.map "${staging}/boot/System.map-linux-custom"
    cp .config "${staging}/boot/config-linux-custom"

    log "Kernel packages staged at ${staging}"
}

# ============================================================================
# Install Kernel
# ============================================================================
install_kernel() {
    local version="$1"

    header "Installing Kernel"

    if [ "$INSTALL_KERNEL" != "yes" ]; then
        warn "Kernel installation skipped (set INSTALL_KERNEL=yes to install)"
        return 0
    fi

    if [ "$EUID" -ne 0 ]; then
        error "Root privileges required for kernel installation"
        log "Run with: sudo INSTALL_KERNEL=yes $0"
        return 1
    fi

    local kernel_dir="${BUILD_DIR}/linux-${version}"
    local staging="${BUILD_DIR}/packages/staging"

    cd "$kernel_dir"

    log "Installing modules..."
    make modules_install

    log "Installing kernel..."
    install -Dm644 arch/x86/boot/bzImage "/boot/vmlinuz-linux-custom"
    install -Dm644 System.map "/boot/System.map-linux-custom"
    install -Dm644 .config "/boot/config-linux-custom"

    # Create initial ramdisk
    log "Creating initramfs..."
    if command -v mkinitcpio &>/dev/null; then
        mkinitcpio -k "${version}-arch-custom" -g "/boot/initramfs-linux-custom.img"
        mkinitcpio -k "${version}-arch-custom" -g "/boot/initramfs-linux-custom-fallback.img" -S autodetect
    fi

    # Update bootloader
    log "Updating bootloader..."
    if command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
    elif [ -d /boot/loader ]; then
        # systemd-boot
        cat > "/boot/loader/entries/linux-custom.conf" << EOF
title   EndeavourOS Linux Custom (${version})
linux   /vmlinuz-linux-custom
initrd  /initramfs-linux-custom.img
options root=LABEL=ROOT rw nvidia_drm.modeset=1
EOF
    fi

    log "Kernel installation complete!"
    log "Reboot to use the new kernel"
}

# ============================================================================
# Run Tests
# ============================================================================
run_tests() {
    local version="$1"

    if [ "$RUN_TESTS" != "yes" ]; then
        debug "Tests skipped (RUN_TESTS=$RUN_TESTS)"
        return 0
    fi

    header "Running Kernel Tests"

    if [ -f "${SCRIPT_DIR}/test-kernel.sh" ]; then
        local test_args=""
        [ "$DEBUG" = "yes" ] && test_args="$test_args --debug"
        [ "$VERBOSE" = "yes" ] && test_args="$test_args --verbose"

        bash "${SCRIPT_DIR}/test-kernel.sh" test $test_args || {
            warn "Some tests failed - review output above"
            return 1
        }
    else
        warn "Test script not found, skipping tests"
    fi

    return 0
}

# ============================================================================
# Main
# ============================================================================
main() {
    header "ARCH Kernel Builder for EndeavourOS"

    log "Project root: $PROJECT_ROOT"
    log "Build directory: $BUILD_DIR"
    log "Parallel jobs: $JOBS"

    # Debug information
    debug "Debug mode: $DEBUG"
    debug "Verbose mode: $VERBOSE"
    debug "Run tests: $RUN_TESTS"
    debug "Install kernel: $INSTALL_KERNEL"

    mkdir -p "$BUILD_DIR" "$LOG_DIR"

    # Check if hardware scan was run
    if [ ! -f "${CONFIG_DIR}/kernel-config-fragment.txt" ]; then
        warn "Hardware configuration not found!"
        log "Running hardware scanner first..."
        "${SCRIPT_DIR}/scan-hardware.sh"
    fi

    check_dependencies

    local version
    if [ -n "${KERNEL_MINOR:-}" ]; then
        version="${KERNEL_MAJOR}.${KERNEL_MINOR}"
    else
        version=$(get_latest_kernel_version)
    fi

    log "Building kernel version: $version"
    debug "Full version string: $version"

    download_kernel "$version"
    configure_kernel "$version"
    build_kernel "$version"
    package_kernel "$version"

    # Run tests before installation
    if ! run_tests "$version"; then
        warn "Tests failed - kernel may have issues"
        if [ "$INSTALL_KERNEL" = "yes" ]; then
            warn "Proceeding with installation despite test failures"
        fi
    fi

    install_kernel "$version"

    header "Build Complete!"
    log "Kernel ${version} has been built successfully"
    log ""
    log "To install manually:"
    log "  cd ${BUILD_DIR}/linux-${version}"
    log "  sudo make modules_install"
    log "  sudo make install"
    log ""
    log "Or use the Arch package:"
    log "  cd ${BUILD_DIR}/packages"
    log "  makepkg -si"
    log ""
    log "To run tests again:"
    log "  ./scripts/test-kernel.sh"
    log ""
    log "Debug options:"
    log "  DEBUG=yes ./scripts/build-kernel.sh      # Debug output"
    log "  VERBOSE=yes ./scripts/test-kernel.sh     # Verbose tests"
}

main "$@"
