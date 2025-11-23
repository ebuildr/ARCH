#!/bin/bash
#
# Pre-reboot kernel validation script
# Verifies custom kernel is ready to boot before you reboot
#
# Usage: ./check-kernel.sh [kernel-version]
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

ERRORS=0
WARNINGS=0

log() { echo -e "$1"; }
pass() { echo -e "${PASS} $1"; }
fail() { echo -e "${FAIL} $1"; ((ERRORS++)); }
warn() { echo -e "${WARN} $1"; ((WARNINGS++)); }
header() {
    echo -e "\n${CYAN}━━━ $1 ━━━${NC}"
}

# ============================================================================
# Find Target Kernel
# ============================================================================
find_target_kernel() {
    local target="${1:-}"

    if [ -n "$target" ]; then
        echo "$target"
        return
    fi

    # Look for custom kernel in /usr/lib/modules
    for dir in /usr/lib/modules/*custom*; do
        if [ -d "$dir" ]; then
            basename "$dir"
            return
        fi
    done

    # Look for most recent kernel that isn't running
    local running=$(uname -r)
    for dir in /usr/lib/modules/*/; do
        local ver=$(basename "$dir")
        if [ "$ver" != "$running" ] && [ -d "$dir/kernel" ]; then
            echo "$ver"
            return
        fi
    done

    echo ""
}

# ============================================================================
# Check: Kernel Image
# ============================================================================
check_kernel_image() {
    local kernel="$1"
    header "Kernel Image"

    local vmlinuz=""

    # Try different naming conventions
    for name in "vmlinuz-linux-custom" "vmlinuz-${kernel}" "vmlinuz-linux-${kernel}"; do
        if [ -f "/boot/${name}" ]; then
            vmlinuz="/boot/${name}"
            break
        fi
    done

    if [ -z "$vmlinuz" ]; then
        # Search for any matching vmlinuz
        vmlinuz=$(find /boot -maxdepth 1 -name "vmlinuz*custom*" -o -name "vmlinuz*${kernel}*" 2>/dev/null | head -1)
    fi

    if [ -n "$vmlinuz" ] && [ -f "$vmlinuz" ]; then
        local size=$(stat -c%s "$vmlinuz" 2>/dev/null || echo 0)
        local size_mb=$((size / 1024 / 1024))
        if [ "$size" -gt 5000000 ]; then
            pass "Kernel image exists: $vmlinuz (${size_mb}MB)"
        else
            fail "Kernel image too small: $vmlinuz (${size_mb}MB) - may be corrupted"
        fi
    else
        fail "Kernel image not found in /boot for $kernel"
        log "    Expected: /boot/vmlinuz-linux-custom or /boot/vmlinuz-${kernel}"
    fi
}

# ============================================================================
# Check: Initramfs
# ============================================================================
check_initramfs() {
    local kernel="$1"
    header "Initramfs"

    local initrd=""
    local fallback=""

    # Try different naming conventions
    for name in "initramfs-linux-custom.img" "initramfs-${kernel}.img"; do
        if [ -f "/boot/${name}" ]; then
            initrd="/boot/${name}"
            break
        fi
    done

    for name in "initramfs-linux-custom-fallback.img" "initramfs-${kernel}-fallback.img"; do
        if [ -f "/boot/${name}" ]; then
            fallback="/boot/${name}"
            break
        fi
    done

    if [ -n "$initrd" ] && [ -f "$initrd" ]; then
        local size=$(stat -c%s "$initrd" 2>/dev/null || echo 0)
        local size_mb=$((size / 1024 / 1024))
        if [ "$size" -gt 10000000 ]; then
            pass "Initramfs exists: $initrd (${size_mb}MB)"
        else
            warn "Initramfs seems small: $initrd (${size_mb}MB)"
        fi
    else
        fail "Initramfs not found for $kernel"
        log "    Run: sudo mkinitcpio -k $kernel -g /boot/initramfs-linux-custom.img"
    fi

    if [ -n "$fallback" ] && [ -f "$fallback" ]; then
        pass "Fallback initramfs exists: $fallback"
    else
        warn "Fallback initramfs not found (recommended for recovery)"
        log "    Run: sudo mkinitcpio -k $kernel -g /boot/initramfs-linux-custom-fallback.img -S autodetect"
    fi
}

# ============================================================================
# Check: Kernel Modules Directory
# ============================================================================
check_modules_dir() {
    local kernel="$1"
    header "Kernel Modules"

    local moddir="/usr/lib/modules/${kernel}"

    if [ -d "$moddir" ]; then
        pass "Modules directory exists: $moddir"

        # Check for essential modules
        local mod_count=$(find "$moddir" -name "*.ko*" 2>/dev/null | wc -l)
        if [ "$mod_count" -gt 100 ]; then
            pass "Module count: $mod_count modules"
        else
            warn "Low module count: $mod_count (expected >100)"
        fi

        # Check modules.dep
        if [ -f "${moddir}/modules.dep" ]; then
            pass "modules.dep exists"
        else
            fail "modules.dep missing - run: sudo depmod $kernel"
        fi
    else
        fail "Modules directory not found: $moddir"
    fi
}

# ============================================================================
# Check: NVIDIA DKMS
# ============================================================================
check_nvidia_dkms() {
    local kernel="$1"
    header "NVIDIA Driver (DKMS)"

    # Check if NVIDIA is needed
    if ! lspci 2>/dev/null | grep -qi nvidia; then
        log "  No NVIDIA GPU detected - skipping"
        return
    fi

    # Check DKMS status
    if ! command -v dkms &>/dev/null; then
        fail "DKMS not installed"
        log "    Run: sudo pacman -S dkms"
        return
    fi

    local nvidia_status=$(dkms status 2>/dev/null | grep -i nvidia || true)

    if [ -z "$nvidia_status" ]; then
        fail "No NVIDIA DKMS module registered"
        log "    Run: sudo pacman -S nvidia-dkms"
        return
    fi

    # Check if built for target kernel
    if echo "$nvidia_status" | grep -q "$kernel.*installed"; then
        pass "NVIDIA DKMS built for $kernel"
    elif echo "$nvidia_status" | grep -q "$kernel"; then
        warn "NVIDIA DKMS status for $kernel: $(echo "$nvidia_status" | grep "$kernel")"
    else
        fail "NVIDIA DKMS NOT built for $kernel"
        log "    Run: sudo dkms autoinstall -k $kernel"
        log "    Or:  sudo dkms install nvidia/<version> -k $kernel"

        # Show available versions
        local nvidia_ver=$(echo "$nvidia_status" | head -1 | grep -oP 'nvidia[^,]*' | head -1)
        if [ -n "$nvidia_ver" ]; then
            log "    Found: $nvidia_ver"
        fi
    fi

    # Check for nvidia modules in kernel directory
    local nvidia_mod=$(find "/usr/lib/modules/${kernel}" -name "nvidia*.ko*" 2>/dev/null | head -1)
    if [ -n "$nvidia_mod" ]; then
        pass "NVIDIA module found: $(basename "$nvidia_mod")"
    else
        fail "No NVIDIA .ko module in /usr/lib/modules/${kernel}"
    fi
}

# ============================================================================
# Check: Kernel Headers (for DKMS)
# ============================================================================
check_headers() {
    local kernel="$1"
    header "Kernel Headers"

    local build_link="/usr/lib/modules/${kernel}/build"

    if [ -L "$build_link" ] || [ -d "$build_link" ]; then
        if [ -f "${build_link}/Makefile" ]; then
            pass "Kernel headers/build directory exists"
        else
            warn "Build link exists but Makefile missing"
        fi
    else
        warn "Kernel headers not found for $kernel"
        log "    DKMS modules may not build"
        log "    Headers should be at: $build_link"
    fi
}

# ============================================================================
# Check: GRUB Entry
# ============================================================================
check_grub() {
    local kernel="$1"
    header "GRUB Bootloader"

    if [ ! -f /boot/grub/grub.cfg ]; then
        warn "GRUB config not found - using different bootloader?"
        return
    fi

    # Check for custom kernel entry
    if grep -q "vmlinuz.*custom\|vmlinuz-${kernel}" /boot/grub/grub.cfg 2>/dev/null; then
        pass "GRUB entry found for custom kernel"

        # Show the entry
        local entry=$(grep -oP "menuentry '[^']*custom[^']*'" /boot/grub/grub.cfg 2>/dev/null | head -1)
        if [ -n "$entry" ]; then
            log "    Entry: $entry"
        fi
    else
        fail "No GRUB entry for custom kernel"
        log "    Run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
        log "    Or:  sudo ./scripts/fix-boot.sh grub"
    fi

    # Check if nvidia_drm.modeset=1 is set
    if grep -q "nvidia_drm.modeset=1" /boot/grub/grub.cfg 2>/dev/null; then
        pass "NVIDIA DRM modeset enabled in GRUB"
    else
        warn "nvidia_drm.modeset=1 not found in kernel params"
        log "    May cause issues with Wayland/display"
    fi
}

# ============================================================================
# Check: Key Kernel Config Options
# ============================================================================
check_config() {
    local kernel="$1"
    header "Kernel Configuration"

    local config=""

    # Find config file
    for loc in "/boot/config-linux-custom" "/boot/config-${kernel}" "/usr/lib/modules/${kernel}/build/.config"; do
        if [ -f "$loc" ]; then
            config="$loc"
            break
        fi
    done

    if [ -z "$config" ]; then
        warn "Kernel config not found - cannot verify options"
        return
    fi

    pass "Config found: $config"

    # Critical options for this hardware
    local checks=(
        "CONFIG_MODULES=y:Loadable module support"
        "CONFIG_MODULE_UNLOAD=y:Module unloading"
        "CONFIG_DRM=:DRM graphics support"
        "CONFIG_X86_64=y:x86_64 architecture"
        "CONFIG_SMP=y:SMP support"
        "CONFIG_EFI=y:EFI support"
        "CONFIG_NVME_CORE=:NVMe support"
        "CONFIG_USB4=:Thunderbolt/USB4 support"
    )

    for check in "${checks[@]}"; do
        local opt="${check%%:*}"
        local desc="${check##*:}"
        local key="${opt%%=*}"
        local expected="${opt##*=}"

        local actual=$(grep "^${key}=" "$config" 2>/dev/null | cut -d= -f2 || echo "not set")

        if [ -z "$expected" ]; then
            # Just check if set to y or m
            if [ "$actual" = "y" ] || [ "$actual" = "m" ]; then
                pass "$desc ($key=$actual)"
            else
                warn "$desc not enabled ($key=$actual)"
            fi
        else
            if [ "$actual" = "$expected" ]; then
                pass "$desc ($key=$actual)"
            else
                warn "$desc: expected $expected, got $actual"
            fi
        fi
    done

    # Check nouveau is disabled (for NVIDIA)
    local nouveau=$(grep "^CONFIG_DRM_NOUVEAU=" "$config" 2>/dev/null | cut -d= -f2 || echo "not set")
    if [ "$nouveau" = "n" ] || [ "$nouveau" = "not set" ]; then
        pass "Nouveau disabled (required for NVIDIA proprietary)"
    else
        warn "Nouveau enabled ($nouveau) - may conflict with NVIDIA"
    fi
}

# ============================================================================
# Check: systemd-boot (alternative to GRUB)
# ============================================================================
check_systemd_boot() {
    local kernel="$1"
    header "systemd-boot (if used)"

    if [ ! -d /boot/loader ]; then
        log "  systemd-boot not detected - skipping"
        return
    fi

    if [ -f /boot/loader/entries/linux-custom.conf ]; then
        pass "systemd-boot entry exists"
    else
        warn "No systemd-boot entry for custom kernel"
        log "    Create: /boot/loader/entries/linux-custom.conf"
    fi
}

# ============================================================================
# Summary & Recommendations
# ============================================================================
summary() {
    local kernel="$1"

    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Summary for kernel: ${kernel}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ ALL CHECKS PASSED${NC}"
        echo -e "${GREEN}Safe to reboot into custom kernel${NC}"
        echo
        return 0
    elif [ $ERRORS -eq 0 ]; then
        echo -e "${YELLOW}${BOLD}⚠ $WARNINGS WARNING(S)${NC}"
        echo -e "${YELLOW}Should be safe to reboot, but review warnings above${NC}"
        echo
        return 0
    else
        echo -e "${RED}${BOLD}✗ $ERRORS ERROR(S), $WARNINGS WARNING(S)${NC}"
        echo -e "${RED}DO NOT REBOOT until errors are fixed${NC}"
        echo
        echo "Quick fixes:"
        echo "  sudo dkms autoinstall                    # Build DKMS modules"
        echo "  sudo mkinitcpio -P                       # Regenerate all initramfs"
        echo "  sudo grub-mkconfig -o /boot/grub/grub.cfg  # Update GRUB"
        echo "  sudo depmod $kernel                      # Regenerate modules.dep"
        echo
        echo "Or run: sudo ./scripts/fix-boot.sh all"
        echo
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          Pre-Reboot Kernel Validation Check                   ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local target_kernel=$(find_target_kernel "${1:-}")

    if [ -z "$target_kernel" ]; then
        echo -e "${RED}No custom kernel found to check${NC}"
        echo
        echo "Usage: $0 [kernel-version]"
        echo
        echo "Available kernels in /usr/lib/modules/:"
        ls -1 /usr/lib/modules/ 2>/dev/null || echo "  (none found)"
        exit 1
    fi

    echo -e "Checking kernel: ${BOLD}${target_kernel}${NC}"
    echo -e "Currently running: $(uname -r)"
    echo

    check_kernel_image "$target_kernel"
    check_initramfs "$target_kernel"
    check_modules_dir "$target_kernel"
    check_headers "$target_kernel"
    check_nvidia_dkms "$target_kernel"
    check_config "$target_kernel"
    check_grub "$target_kernel"
    check_systemd_boot "$target_kernel"

    summary "$target_kernel"
}

main "$@"
