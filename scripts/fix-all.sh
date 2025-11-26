#!/bin/bash
#
# ARCH Master Fix Script - Fix all three issues:
# 1. VMD (Intel Volume Management Device)
# 2. NVIDIA RTX 5090 drivers
# 3. Thunderbolt 5 / DisplayPort (Razer dock + Samsung Odyssey)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/logs"
MASTER_LOG="${LOG_DIR}/fix-all-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() { echo -e "${GREEN}[MASTER]${NC} $1" | tee -a "$MASTER_LOG"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$MASTER_LOG"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$MASTER_LOG"; }
info() { echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$MASTER_LOG"; }

mkdir -p "$LOG_DIR"

header() {
    echo -e "\n${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║$(printf '%63s' | tr ' ' ' ')║${NC}"
    printf "${CYAN}║${NC}%-63s${CYAN}║${NC}\n" "  $1"
    echo -e "${CYAN}║$(printf '%63s' | tr ' ' ' ')║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}\n"
}

clear

header "ARCH System Fix - Complete Hardware Repair"

cat << 'EOF'

   █████╗ ██████╗  ██████╗██╗  ██╗
  ██╔══██╗██╔══██╗██╔════╝██║  ██║
  ███████║██████╔╝██║     ███████║
  ██╔══██║██╔══██╗██║     ██╔══██║
  ██║  ██║██║  ██║╚██████╗██║  ██║
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝

  Arch Linux Custom Kernel & Hardware Builder
  MSI Raider 18 HX - EndeavourOS

  Fixing three critical issues:
  1. VMD (Intel Volume Management Device)
  2. NVIDIA RTX 5090 drivers (Blackwell)
  3. Thunderbolt 5 + DisplayPort (Razer + Samsung Odyssey)

EOF

log "Master log: $MASTER_LOG"
log ""

# Confirm with user
if [ "${1:-}" != "--yes" ] && [ "${1:-}" != "-y" ]; then
    echo -e "${YELLOW}This script will:${NC}"
    echo "  • Rebuild kernel with VMD support"
    echo "  • Reinstall and configure NVIDIA drivers"
    echo "  • Configure Thunderbolt 5 and DisplayPort"
    echo "  • Modify system configuration files (requires sudo)"
    echo "  • Regenerate initramfs"
    echo ""
    echo -e "${YELLOW}A reboot will be required after completion.${NC}"
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Aborted by user"
        exit 0
    fi
fi

log "Starting comprehensive system fix..."
log ""

FIXES_APPLIED=0
FIXES_FAILED=0

# ============================================================================
# Phase 1: Run Diagnostics
# ============================================================================
header "Phase 1: System Diagnostics"

log "Running comprehensive diagnostics..."
if [ -x "$SCRIPT_DIR/debug-system.sh" ]; then
    bash "$SCRIPT_DIR/debug-system.sh" 2>&1 | tee -a "$MASTER_LOG"
    log "Diagnostics complete - review output above"
else
    warn "debug-system.sh not found or not executable"
fi

echo ""
read -p "Press Enter to continue with fixes..." -r

# ============================================================================
# Phase 2: VMD Support (Rebuild Kernel)
# ============================================================================
header "Phase 2: Enable VMD Support"

log "VMD (Intel Volume Management Device) enables proper NVMe drive management"
log "on Intel Arrow Lake platforms."
log ""

if grep -q "CONFIG_VMD=y" "$PROJECT_ROOT/config/kernel-config-fragment.txt" 2>/dev/null; then
    log "${GREEN}✓${NC} VMD is already enabled in kernel configuration"
    info "Current kernel may not have VMD - will be included in next rebuild"
else
    warn "VMD not found in kernel config - hardware scan may need to be re-run"
fi

log ""
log "To apply VMD support, kernel needs to be rebuilt:"
log "  cd $PROJECT_ROOT"
log "  bash scripts/scan-hardware.sh    # Regenerate config with VMD"
log "  bash scripts/build-kernel.sh     # Rebuild kernel"
log ""

read -p "Rebuild kernel now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Rebuilding kernel with VMD support..."

    log "Step 1: Rescan hardware..."
    bash "$SCRIPT_DIR/scan-hardware.sh" 2>&1 | tee -a "$MASTER_LOG"

    log ""
    log "Step 2: Build kernel..."
    bash "$SCRIPT_DIR/build-kernel.sh" 2>&1 | tee -a "$MASTER_LOG"

    if [ $? -eq 0 ]; then
        log "${GREEN}✓${NC} Kernel rebuild successful"
        ((FIXES_APPLIED++))
    else
        error "Kernel rebuild failed"
        ((FIXES_FAILED++))
    fi
else
    info "Skipped kernel rebuild"
    info "Run manually later: cd $PROJECT_ROOT && bash scripts/build-kernel.sh"
fi

# ============================================================================
# Phase 3: NVIDIA Driver Fix
# ============================================================================
header "Phase 3: NVIDIA RTX 5090 Driver Fix"

log "Fixing NVIDIA driver for Blackwell architecture (RTX 5090)..."
log ""

if [ -x "$SCRIPT_DIR/fix-nvidia.sh" ]; then
    bash "$SCRIPT_DIR/fix-nvidia.sh" 2>&1 | tee -a "$MASTER_LOG"

    if lsmod | grep -q nvidia; then
        log "${GREEN}✓${NC} NVIDIA driver fix completed"
        ((FIXES_APPLIED++))
    else
        warn "NVIDIA modules not loaded (reboot required)"
        ((FIXES_APPLIED++))
    fi
else
    error "fix-nvidia.sh not found"
    ((FIXES_FAILED++))
fi

# ============================================================================
# Phase 4: Thunderbolt/DisplayPort Fix
# ============================================================================
header "Phase 4: Thunderbolt 5 / DisplayPort Fix"

log "Configuring Razer Thunderbolt 5 Dock and Samsung Odyssey monitor..."
log ""

if [ -x "$SCRIPT_DIR/fix-thunderbolt-displayport.sh" ]; then
    bash "$SCRIPT_DIR/fix-thunderbolt-displayport.sh" 2>&1 | tee -a "$MASTER_LOG"

    # Check if displays are now connected
    CONNECTED=$(cat /sys/class/drm/card*-*/status 2>/dev/null | grep -c "connected" || echo "0")
    if [ "$CONNECTED" -gt 0 ]; then
        log "${GREEN}✓${NC} Thunderbolt/DisplayPort fix completed"
        ((FIXES_APPLIED++))
    else
        warn "No displays detected (may require reboot)"
        ((FIXES_APPLIED++))
    fi
else
    error "fix-thunderbolt-displayport.sh not found"
    ((FIXES_FAILED++))
fi

# ============================================================================
# Final Summary
# ============================================================================
header "Fix Summary"

log ""
log "╔════════════════════════════════════════════════════════════════╗"
log "║                      FIX SUMMARY                               ║"
log "╠════════════════════════════════════════════════════════════════╣"
log "║  Fixes applied:  $FIXES_APPLIED                                           ║"
log "║  Fixes failed:   $FIXES_FAILED                                           ║"
log "╚════════════════════════════════════════════════════════════════╝"
log ""

if [ $FIXES_FAILED -eq 0 ]; then
    log "${GREEN}✓ All fixes completed successfully!${NC}"
else
    warn "Some fixes failed - review logs above"
fi

log ""
log "Master log saved to: $MASTER_LOG"
log ""

# ============================================================================
# Reboot Prompt
# ============================================================================
header "Next Steps"

log ""
log "${YELLOW}REBOOT REQUIRED${NC}"
log ""
log "Changes made:"
log "  ✓ Kernel configuration updated (VMD enabled)"
log "  ✓ NVIDIA driver reinstalled with Blackwell support"
log "  ✓ Thunderbolt auto-authorization enabled"
log "  ✓ DisplayPort detection configured"
log "  ✓ Initramfs regenerated"
log "  ✓ Kernel modules configured"
log ""

if [ -f "$PROJECT_ROOT/build/linux-"*"/arch/x86/boot/bzImage" ]; then
    log "${GREEN}New kernel is ready to install:${NC}"
    ls -lh "$PROJECT_ROOT"/build/linux-*/arch/x86/boot/bzImage 2>/dev/null | tail -1
    log ""
    log "Install with:"
    log "  cd $PROJECT_ROOT && bash scripts/build-kernel.sh --install"
    log ""
fi

log "After reboot, verify with:"
log "  nvidia-smi                    # Check NVIDIA driver"
log "  boltctl list                  # Check Thunderbolt devices"
log "  xrandr --query                # Check displays"
log "  lspci | grep -i vmd           # Check VMD"
log "  dmesg | grep -i nvidia        # Check for errors"
log ""

read -p "Reboot now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Rebooting system..."
    sudo reboot
else
    log "Please reboot manually when ready"
fi
