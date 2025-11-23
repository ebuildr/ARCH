#!/bin/bash
#
# ARCH Kernel Testing & Debugging Script
# Tests kernel builds before installation and provides debugging tools
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PROJECT_ROOT}/config"
BUILD_DIR="${PROJECT_ROOT}/build"
LOG_DIR="${PROJECT_ROOT}/logs"
TEST_LOG="${LOG_DIR}/kernel-test-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Debug mode
DEBUG="${DEBUG:-no}"
VERBOSE="${VERBOSE:-no}"

log() { echo -e "${GREEN}[TEST]${NC} $1" | tee -a "$TEST_LOG"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$TEST_LOG"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG"; }
debug() { [ "$DEBUG" = "yes" ] && echo -e "${MAGENTA}[DEBUG]${NC} $1" | tee -a "$TEST_LOG" || true; }
header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}" | tee -a "$TEST_LOG"
    echo -e "${CYAN}  $1${NC}" | tee -a "$TEST_LOG"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n" | tee -a "$TEST_LOG"
}

# ============================================================================
# Find Built Kernel
# ============================================================================
find_kernel_build() {
    local kernel_dir=""

    # Find most recent kernel build
    for dir in "${BUILD_DIR}"/linux-*; do
        if [ -d "$dir" ] && [ -f "$dir/vmlinux" ]; then
            kernel_dir="$dir"
        fi
    done

    if [ -z "$kernel_dir" ]; then
        error "No kernel build found in ${BUILD_DIR}"
        error "Run './arch-builder.sh build' first"
        return 1
    fi

    echo "$kernel_dir"
}

# ============================================================================
# Test 1: Verify Kernel Image
# ============================================================================
test_kernel_image() {
    local kernel_dir="$1"

    header "Test 1: Kernel Image Verification"

    local bzimage="${kernel_dir}/arch/x86/boot/bzImage"
    local vmlinux="${kernel_dir}/vmlinux"

    # Check bzImage exists
    if [ -f "$bzimage" ]; then
        local size=$(stat -c%s "$bzimage")
        local size_mb=$((size / 1024 / 1024))
        log "✓ bzImage found: ${size_mb}MB"
        debug "  Path: $bzimage"

        # Verify it's a valid kernel image
        if file "$bzimage" | grep -q "Linux kernel"; then
            log "✓ Valid Linux kernel image"
        else
            warn "⚠ Could not verify kernel image type"
        fi
    else
        error "✗ bzImage not found at $bzimage"
        return 1
    fi

    # Check vmlinux (uncompressed)
    if [ -f "$vmlinux" ]; then
        log "✓ vmlinux (uncompressed) found"
        debug "  Size: $(stat -c%s "$vmlinux" | numfmt --to=iec)"
    fi

    # Check System.map
    if [ -f "${kernel_dir}/System.map" ]; then
        local symbols=$(wc -l < "${kernel_dir}/System.map")
        log "✓ System.map found ($symbols symbols)"
    else
        warn "⚠ System.map not found"
    fi

    return 0
}

# ============================================================================
# Test 2: Module Verification
# ============================================================================
test_modules() {
    local kernel_dir="$1"

    header "Test 2: Kernel Modules Verification"

    local modules_dir="${kernel_dir}/modules_install"
    local module_count=0

    # Count built modules
    if [ -d "${kernel_dir}" ]; then
        module_count=$(find "${kernel_dir}" -name "*.ko" 2>/dev/null | wc -l)
    fi

    log "Built modules: $module_count"

    # Check critical modules
    local critical_modules=(
        "nvidia"
        "iwlwifi"
        "thunderbolt"
        "nvme"
        "snd_hda_intel"
    )

    log "Checking critical module configs..."

    local config="${kernel_dir}/.config"
    if [ -f "$config" ]; then
        for mod in "${critical_modules[@]}"; do
            local config_name="CONFIG_$(echo $mod | tr '[:lower:]' '[:upper:]')"
            if grep -q "^${config_name}=[ym]" "$config" 2>/dev/null; then
                log "  ✓ $mod: enabled"
            elif grep -q "^# ${config_name} is not set" "$config" 2>/dev/null; then
                warn "  ⚠ $mod: disabled"
            else
                debug "  ? $mod: config not found"
            fi
        done
    fi

    # List actual built modules
    if [ "$VERBOSE" = "yes" ]; then
        log "Built .ko files:"
        find "${kernel_dir}" -name "*.ko" -printf "  %f\n" 2>/dev/null | head -20
        local remaining=$((module_count - 20))
        [ $remaining -gt 0 ] && log "  ... and $remaining more"
    fi

    return 0
}

# ============================================================================
# Test 3: Configuration Validation
# ============================================================================
test_config() {
    local kernel_dir="$1"

    header "Test 3: Configuration Validation"

    local config="${kernel_dir}/.config"

    if [ ! -f "$config" ]; then
        error "✗ .config not found"
        return 1
    fi

    log "Validating kernel configuration..."

    # Required configs for target hardware
    local required_configs=(
        # CPU - Intel Arrow Lake
        "CONFIG_X86_64=y"
        "CONFIG_SMP=y"
        "CONFIG_X86_INTEL_PSTATE=y"

        # GPU - NVIDIA RTX 5090
        "CONFIG_DRM=y"
        "CONFIG_MODULES=y"

        # Thunderbolt 5
        "CONFIG_USB4=y"
        "CONFIG_TYPEC=y"

        # NVMe
        "CONFIG_BLK_DEV_NVME=y"

        # WiFi
        "CONFIG_IWLWIFI=m"

        # Audio
        "CONFIG_SND_HDA_INTEL=m"
    )

    local pass=0
    local fail=0

    for req in "${required_configs[@]}"; do
        local key=$(echo "$req" | cut -d'=' -f1)
        local expected=$(echo "$req" | cut -d'=' -f2)

        if grep -q "^${key}=${expected}" "$config"; then
            log "  ✓ $key=$expected"
            ((pass++))
        elif grep -q "^${key}=" "$config"; then
            local actual=$(grep "^${key}=" "$config" | cut -d'=' -f2)
            warn "  ⚠ $key=$actual (expected $expected)"
            ((fail++))
        else
            warn "  ✗ $key not set"
            ((fail++))
        fi
    done

    log "Config validation: $pass passed, $fail warnings"

    # Check for hardware-specific fragment
    if [ -f "${CONFIG_DIR}/kernel-config-fragment.txt" ]; then
        log "✓ Hardware config fragment exists"
    else
        warn "⚠ Hardware config fragment not found - run scan first"
    fi

    return 0
}

# ============================================================================
# Test 4: Boot Compatibility
# ============================================================================
test_boot_compat() {
    local kernel_dir="$1"

    header "Test 4: Boot Compatibility Check"

    local config="${kernel_dir}/.config"

    log "Checking boot requirements..."

    # EFI support
    if grep -q "CONFIG_EFI=y" "$config"; then
        log "  ✓ EFI boot support"
    else
        warn "  ⚠ EFI not enabled"
    fi

    # EFI stub
    if grep -q "CONFIG_EFI_STUB=y" "$config"; then
        log "  ✓ EFI stub (direct boot capable)"
    fi

    # Initramfs support
    if grep -q "CONFIG_BLK_DEV_INITRD=y" "$config"; then
        log "  ✓ Initramfs support"
    fi

    # Check filesystem support for root
    log "Checking filesystem support..."

    local filesystems=("EXT4" "BTRFS" "XFS" "F2FS")
    for fs in "${filesystems[@]}"; do
        if grep -q "CONFIG_${fs}_FS=[ym]" "$config"; then
            log "  ✓ $fs filesystem"
        fi
    done

    # NVMe as root
    if grep -q "CONFIG_BLK_DEV_NVME=y" "$config"; then
        log "  ✓ NVMe boot support (built-in)"
    elif grep -q "CONFIG_BLK_DEV_NVME=m" "$config"; then
        warn "  ⚠ NVMe as module - ensure initramfs includes it"
    fi

    return 0
}

# ============================================================================
# Test 5: Hardware Support Verification
# ============================================================================
test_hardware_support() {
    local kernel_dir="$1"

    header "Test 5: Hardware Support Verification"

    local config="${kernel_dir}/.config"

    log "MSI Raider 18 HX Hardware Support:"
    echo ""

    # Intel Core Ultra 9 285HX (Arrow Lake)
    log "${BLUE}CPU: Intel Core Ultra 9 285HX (Arrow Lake)${NC}"
    local cpu_configs=(
        "CONFIG_X86_INTEL_PSTATE:Intel P-State driver"
        "CONFIG_INTEL_IDLE:Intel idle driver"
        "CONFIG_SCHED_MC:Multi-core scheduling"
        "CONFIG_SCHED_SMT:SMT scheduling"
    )
    for item in "${cpu_configs[@]}"; do
        local cfg=$(echo "$item" | cut -d: -f1)
        local desc=$(echo "$item" | cut -d: -f2)
        if grep -q "^${cfg}=[ym]" "$config"; then
            log "  ✓ $desc"
        else
            warn "  ✗ $desc"
        fi
    done
    echo ""

    # NVIDIA RTX 5090 (Blackwell SM120)
    log "${BLUE}GPU: NVIDIA RTX 5090 (Blackwell SM120)${NC}"
    local gpu_configs=(
        "CONFIG_DRM:DRM subsystem"
        "CONFIG_DRM_KMS_HELPER:KMS helper"
        "CONFIG_MODULES:Module support (for nvidia)"
    )
    for item in "${gpu_configs[@]}"; do
        local cfg=$(echo "$item" | cut -d: -f1)
        local desc=$(echo "$item" | cut -d: -f2)
        if grep -q "^${cfg}=[ym]" "$config"; then
            log "  ✓ $desc"
        else
            warn "  ✗ $desc"
        fi
    done

    # Check Nouveau is disabled
    if grep -q "^# CONFIG_DRM_NOUVEAU is not set" "$config" || ! grep -q "CONFIG_DRM_NOUVEAU" "$config"; then
        log "  ✓ Nouveau disabled (required for NVIDIA proprietary)"
    else
        warn "  ⚠ Nouveau enabled - may conflict with NVIDIA driver"
    fi
    echo ""

    # Thunderbolt 5
    log "${BLUE}Thunderbolt 5 / USB4 v2${NC}"
    local tb_configs=(
        "CONFIG_USB4:USB4/Thunderbolt core"
        "CONFIG_TYPEC:USB Type-C"
        "CONFIG_TYPEC_UCSI:UCSI interface"
        "CONFIG_HOTPLUG_PCI_PCIE:PCIe hotplug"
    )
    for item in "${tb_configs[@]}"; do
        local cfg=$(echo "$item" | cut -d: -f1)
        local desc=$(echo "$item" | cut -d: -f2)
        if grep -q "^${cfg}=[ym]" "$config"; then
            log "  ✓ $desc"
        else
            warn "  ✗ $desc"
        fi
    done
    echo ""

    # WiFi 7
    log "${BLUE}WiFi: Killer WiFi 7 BE1750x (Intel BE200)${NC}"
    local wifi_configs=(
        "CONFIG_IWLWIFI:Intel WiFi driver"
        "CONFIG_IWLMVM:Intel MVM firmware"
        "CONFIG_CFG80211:Wireless config"
        "CONFIG_MAC80211:MAC80211 stack"
    )
    for item in "${wifi_configs[@]}"; do
        local cfg=$(echo "$item" | cut -d: -f1)
        local desc=$(echo "$item" | cut -d: -f2)
        if grep -q "^${cfg}=[ym]" "$config"; then
            log "  ✓ $desc"
        else
            warn "  ✗ $desc"
        fi
    done

    return 0
}

# ============================================================================
# Test 6: DKMS Compatibility
# ============================================================================
test_dkms_compat() {
    local kernel_dir="$1"

    header "Test 6: DKMS Compatibility (for NVIDIA)"

    local version=$(cat "${kernel_dir}/include/config/kernel.release" 2>/dev/null || basename "$kernel_dir" | sed 's/linux-//')

    log "Kernel version: $version"

    # Check required files for DKMS
    local dkms_files=(
        ".config"
        "Module.symvers"
        "scripts/basic/fixdep"
        "scripts/mod/modpost"
    )

    local dkms_ready=true

    for file in "${dkms_files[@]}"; do
        if [ -e "${kernel_dir}/${file}" ]; then
            log "  ✓ $file"
        else
            warn "  ✗ $file missing"
            dkms_ready=false
        fi
    done

    # Check for headers
    if [ -d "${kernel_dir}/include" ]; then
        log "  ✓ Kernel headers present"
    else
        warn "  ✗ Kernel headers missing"
        dkms_ready=false
    fi

    if [ "$dkms_ready" = true ]; then
        log "✓ DKMS compatibility: READY"
        log "  NVIDIA driver can be built against this kernel"
    else
        warn "⚠ DKMS compatibility: INCOMPLETE"
        warn "  Run 'make modules_prepare' if needed"
    fi

    return 0
}

# ============================================================================
# Debug: Show Kernel Config Diff
# ============================================================================
debug_config_diff() {
    local kernel_dir="$1"

    header "Debug: Configuration Analysis"

    local config="${kernel_dir}/.config"
    local fragment="${CONFIG_DIR}/kernel-config-fragment.txt"

    if [ ! -f "$config" ]; then
        error "No .config found"
        return 1
    fi

    # Show key differences from default
    log "Custom configurations applied:"

    if [ -f "$fragment" ]; then
        log "From hardware fragment:"
        grep -v "^#" "$fragment" | grep -v "^$" | head -30
    fi

    # Show potentially problematic settings
    log ""
    log "Debug-relevant settings:"
    grep -E "CONFIG_(DEBUG|KASAN|UBSAN|LOCKDEP|PROVE)" "$config" 2>/dev/null | head -20 || log "  No debug configs found"

    return 0
}

# ============================================================================
# Debug: Analyze Build Errors
# ============================================================================
debug_build_errors() {
    header "Debug: Build Error Analysis"

    local build_log="${LOG_DIR}/kernel-build.log"

    if [ ! -f "$build_log" ]; then
        warn "No build log found at $build_log"
        return 0
    fi

    log "Analyzing build log..."

    # Find errors
    local errors=$(grep -c -iE "^error:|fatal error:" "$build_log" 2>/dev/null || echo "0")
    local warnings=$(grep -c -iE "^warning:" "$build_log" 2>/dev/null || echo "0")

    log "Build statistics:"
    log "  Errors: $errors"
    log "  Warnings: $warnings"

    if [ "$errors" -gt 0 ]; then
        error "Build errors found:"
        grep -iE "^error:|fatal error:" "$build_log" | head -10
    fi

    if [ "$VERBOSE" = "yes" ] && [ "$warnings" -gt 0 ]; then
        warn "Sample warnings:"
        grep -iE "^warning:" "$build_log" | head -5
    fi

    return 0
}

# ============================================================================
# Quick Test (Sanity Check)
# ============================================================================
quick_test() {
    local kernel_dir="$1"

    header "Quick Sanity Check"

    local pass=0
    local fail=0

    # Essential checks
    [ -f "${kernel_dir}/arch/x86/boot/bzImage" ] && { log "✓ Kernel image"; ((pass++)); } || { error "✗ Kernel image"; ((fail++)); }
    [ -f "${kernel_dir}/.config" ] && { log "✓ Config file"; ((pass++)); } || { error "✗ Config file"; ((fail++)); }
    [ -f "${kernel_dir}/System.map" ] && { log "✓ System.map"; ((pass++)); } || { error "✗ System.map"; ((fail++)); }
    [ -f "${kernel_dir}/vmlinux" ] && { log "✓ vmlinux"; ((pass++)); } || { warn "⚠ vmlinux"; }

    echo ""
    if [ $fail -eq 0 ]; then
        log "${GREEN}Quick test PASSED ($pass checks)${NC}"
        return 0
    else
        error "${RED}Quick test FAILED ($fail failures)${NC}"
        return 1
    fi
}

# ============================================================================
# Full Test Suite
# ============================================================================
run_full_test() {
    local kernel_dir="$1"

    header "ARCH Kernel Test Suite"

    log "Testing kernel build at: $kernel_dir"
    log "Test log: $TEST_LOG"
    echo ""

    local total_tests=6
    local passed=0
    local failed=0

    # Run all tests
    test_kernel_image "$kernel_dir" && ((passed++)) || ((failed++))
    test_modules "$kernel_dir" && ((passed++)) || ((failed++))
    test_config "$kernel_dir" && ((passed++)) || ((failed++))
    test_boot_compat "$kernel_dir" && ((passed++)) || ((failed++))
    test_hardware_support "$kernel_dir" && ((passed++)) || ((failed++))
    test_dkms_compat "$kernel_dir" && ((passed++)) || ((failed++))

    # Summary
    header "Test Summary"

    log "Results: $passed/$total_tests tests passed"

    if [ $failed -eq 0 ]; then
        log ""
        log "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        log "${GREEN}║  ALL TESTS PASSED - Kernel is ready for installation!     ║${NC}"
        log "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        log ""
        log "Next steps:"
        log "  1. Install: sudo make modules_install && sudo make install"
        log "  2. Or use: ./arch-builder.sh build --install"
        return 0
    else
        log ""
        warn "╔════════════════════════════════════════════════════════════╗"
        warn "║  $failed TEST(S) FAILED - Review warnings above            ║"
        warn "╚════════════════════════════════════════════════════════════╝"
        return 1
    fi
}

# ============================================================================
# Usage
# ============================================================================
show_usage() {
    cat << EOF
ARCH Kernel Testing & Debugging Script

Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  test          Run full test suite (default)
  quick         Quick sanity check only
  config        Test configuration only
  hardware      Test hardware support only
  modules       Test module builds only
  debug         Run debug analysis
  errors        Analyze build errors

Options:
  -d, --debug       Enable debug output
  -v, --verbose     Verbose output
  -k, --kernel DIR  Specify kernel directory
  -h, --help        Show this help

Environment Variables:
  DEBUG=yes         Enable debug mode
  VERBOSE=yes       Enable verbose mode

Examples:
  $(basename "$0")                    # Run full test suite
  $(basename "$0") quick              # Quick sanity check
  $(basename "$0") hardware -v        # Verbose hardware test
  DEBUG=yes $(basename "$0") debug    # Debug mode analysis

EOF
}

# ============================================================================
# Main
# ============================================================================
main() {
    local command="test"
    local kernel_dir=""

    mkdir -p "$LOG_DIR"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            test|quick|config|hardware|modules|debug|errors)
                command="$1"
                shift
                ;;
            -d|--debug)
                DEBUG="yes"
                shift
                ;;
            -v|--verbose)
                VERBOSE="yes"
                shift
                ;;
            -k|--kernel)
                kernel_dir="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Find kernel directory if not specified
    if [ -z "$kernel_dir" ]; then
        kernel_dir=$(find_kernel_build) || exit 1
    fi

    debug "Kernel directory: $kernel_dir"
    debug "Command: $command"
    debug "Debug mode: $DEBUG"
    debug "Verbose mode: $VERBOSE"

    # Run requested command
    case "$command" in
        test)
            run_full_test "$kernel_dir"
            ;;
        quick)
            quick_test "$kernel_dir"
            ;;
        config)
            test_config "$kernel_dir"
            ;;
        hardware)
            test_hardware_support "$kernel_dir"
            ;;
        modules)
            test_modules "$kernel_dir"
            ;;
        debug)
            debug_config_diff "$kernel_dir"
            debug_build_errors
            ;;
        errors)
            debug_build_errors
            ;;
    esac
}

main "$@"
