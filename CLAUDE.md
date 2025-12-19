# ARCH - Arch Linux Custom Kernel & Hardware Builder

This project provides automated tools for building custom Linux kernels and configuring hardware support for the MSI Raider 18 HX laptop running EndeavourOS (Arch Linux).

## Target Hardware

- **Laptop**: MSI Raider 18 HX AI A2XWJG
- **CPU**: Intel Core Ultra 9 285HX (Arrow Lake, hybrid architecture)
- **GPU**: NVIDIA GeForce RTX 5090 Laptop (Blackwell SM120, 24GB)
- **iGPU**: Intel Graphics (Xe)
- **RAM**: 96GB DDR5-5600 (Corsair)
- **Storage**:
  - WD_BLACK SN850X 8TB NVMe
  - WD_BLACK SN8100 4TB NVMe
  - 1TB HDD
- **WiFi**: Killer WiFi 7 BE1750x (Intel BE200)
- **Dock**: Razer Thunderbolt 5 Dock
- **Monitor**: Samsung Odyssey (via Thunderbolt)

## Project Structure

```
ARCH/
├── arch-builder.sh          # Main orchestration script
├── scripts/
│   ├── scan-hardware.sh     # Hardware detection and config generation
│   ├── build-kernel.sh      # Kernel download, configure, and build
│   ├── build-nvidia.sh      # NVIDIA RTX 5090 driver setup
│   ├── setup-thunderbolt.sh # Thunderbolt 5 / Razer dock config
│   ├── debug-system.sh      # Comprehensive system diagnostics
│   ├── fix-all.sh           # Master fix script for all issues
│   ├── fix-nvidia.sh        # NVIDIA driver troubleshooting
│   └── fix-thunderbolt-displayport.sh # TB5/DP fixes
├── iso/
│   ├── build-iso.sh         # Custom Arch Linux ISO builder
│   └── README.md            # ISO building guide
├── config/                  # Generated configurations
│   ├── hardware-report.txt  # Hardware scan results
│   ├── kernel-config-fragment.txt  # Kernel config options
│   ├── required-modules.txt # Required kernel modules
│   └── hardware.json        # Machine-readable hardware data
├── build/                   # Build artifacts
│   ├── linux-X.Y.Z/        # Kernel source and build
│   ├── nvidia/             # NVIDIA driver builds
│   └── packages/           # Generated Arch packages
├── logs/                    # Build logs
└── .claude/
    └── commands/           # Claude Code slash commands
```

## Quick Start

### Full System Setup
```bash
./arch-builder.sh all --install
```

### Individual Steps
```bash
# 1. Scan hardware
./arch-builder.sh scan

# 2. Build kernel
./arch-builder.sh build

# 3. Setup NVIDIA drivers
./arch-builder.sh nvidia

# 4. Setup Thunderbolt
./arch-builder.sh thunderbolt
```

### Check Status
```bash
./arch-builder.sh status
```

## Claude Code Integration

This project includes Claude Code slash commands for easy execution:

### Setup Commands
- `/scan` - Run hardware scanner
- `/build-kernel` - Build custom kernel
- `/nvidia` - Setup NVIDIA RTX 5090 drivers
- `/thunderbolt` - Configure Thunderbolt 5 / Razer dock
- `/monitor` - Setup Samsung Odyssey via DisplayPort

### Testing & Debugging
- `/test` - Test kernel build before installation
- `/debug` - Run comprehensive system diagnostics

### Fix Commands
- `/fix-all` - Fix all detected issues (VMD + NVIDIA + Thunderbolt/DP)
- `/fix-nvidia` - Fix NVIDIA driver issues only
- `/fix-tb` - Fix Thunderbolt/DisplayPort issues only

**Note:** The fix commands are designed to troubleshoot and repair common issues after building and installing the kernel.

## Key Features

### Hardware Scanner (`scan-hardware.sh`)
- Detects all system hardware via lspci, /proc, /sys
- Generates kernel configuration fragments
- Creates JSON report for programmatic access
- Identifies required kernel modules

### Kernel Builder (`build-kernel.sh`)
- Downloads latest stable kernel from kernel.org
- Merges hardware-specific configurations
- Enables Intel Arrow Lake optimizations:
  - Hybrid CPU support (Thread Director)
  - Intel P-state driver
  - Speed Select Technology
- Disables Nouveau (for NVIDIA proprietary)
- Creates Arch Linux packages

### NVIDIA Setup (`build-nvidia.sh`)
- Installs NVIDIA 570+ drivers (required for RTX 5090/Blackwell)
- Supports open kernel modules (recommended)
- Configures Optimus/PRIME for hybrid graphics
- Sets up DRM modeset for Wayland
- Configures power management for laptops

### Thunderbolt Setup (`setup-thunderbolt.sh`)
- Installs bolt daemon for device management
- Configures security policies
- Auto-authorizes Razer docks
- Enables DisplayPort Alt Mode
- Sets up PCIe tunneling
- Configures Thunderbolt networking

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KERNEL_MAJOR` | 6 | Kernel major version |
| `KERNEL_MINOR` | (latest) | Kernel minor version |
| `JOBS` | (nproc) | Parallel build jobs |
| `INSTALL_KERNEL` | no | Auto-install kernel |
| `USE_OPEN_KERNEL` | yes | Use NVIDIA open modules |
| `NVIDIA_DRIVER_BRANCH` | 570 | NVIDIA driver branch |

## Requirements

### Build Dependencies
- base-devel (gcc, make, etc.)
- bc, flex, bison
- libelf, pahole
- openssl
- perl, python
- wget, curl, git

### Runtime Dependencies
- linux-headers
- dkms
- bolt (Thunderbolt)
- nvidia-utils

## Instructions for Claude Code

**IMPORTANT**: These instructions tell Claude Code how to operate this repository.

### How to Execute Commands

When the user asks to perform any of these tasks, run the corresponding command:

| User Request | Command to Run |
|--------------|----------------|
| "scan hardware" / "detect hardware" | `bash /home/user/ARCH/scripts/scan-hardware.sh` |
| "build kernel" / "compile kernel" | `bash /home/user/ARCH/scripts/build-kernel.sh` |
| "setup nvidia" / "install nvidia" | `bash /home/user/ARCH/scripts/build-nvidia.sh` |
| "setup thunderbolt" / "configure dock" | `bash /home/user/ARCH/scripts/setup-thunderbolt.sh` |
| "setup monitor" / "configure display" | `bash /home/user/ARCH/scripts/setup-monitor.sh` |
| "test kernel" / "verify build" | `bash /home/user/ARCH/scripts/test-kernel.sh` |
| "debug" / "diagnose system" | `bash /home/user/ARCH/scripts/debug-system.sh` |
| "fix all" / "fix everything" | `bash /home/user/ARCH/scripts/fix-all.sh` |
| "fix nvidia" / "repair nvidia" | `bash /home/user/ARCH/scripts/fix-nvidia.sh` |
| "fix thunderbolt" / "fix displayport" / "fix monitor" | `bash /home/user/ARCH/scripts/fix-thunderbolt-displayport.sh` |
| "check status" | `bash /home/user/ARCH/arch-builder.sh status` |
| "full setup" / "setup everything" | `bash /home/user/ARCH/arch-builder.sh all` |

### Working Directory

Always run commands from `/home/user/ARCH`:
```bash
cd /home/user/ARCH && bash scripts/scan-hardware.sh
```

### Debug Mode

When the user asks for debug output or has issues:
```bash
cd /home/user/ARCH && DEBUG=yes VERBOSE=yes bash scripts/build-kernel.sh
```

### Long-Running Commands

Kernel builds take 15-60 minutes. When running `build-kernel.sh`:
1. Warn the user it will take time
2. Consider running in background if appropriate
3. Check `logs/kernel-build.log` for progress

### Checking Results

After running scripts, verify success:
```bash
# After scan
cat /home/user/ARCH/config/hardware-report.txt

# After kernel build
bash /home/user/ARCH/scripts/test-kernel.sh quick

# After NVIDIA setup
nvidia-smi

# After Thunderbolt setup
boltctl list
```

### Error Handling

If a script fails or the user reports issues:
1. Run comprehensive diagnostics: `bash /home/user/ARCH/scripts/debug-system.sh`
2. Check the logs: `cat /home/user/ARCH/logs/*.log | tail -50`
3. Run specific fixes:
   - NVIDIA issues: `bash /home/user/ARCH/scripts/fix-nvidia.sh`
   - Thunderbolt/Monitor: `bash /home/user/ARCH/scripts/fix-thunderbolt-displayport.sh`
   - All issues: `bash /home/user/ARCH/scripts/fix-all.sh`
4. Show the user what went wrong and what was fixed

### Permissions

These operations require sudo (scripts will prompt):
- Installing packages (`pacman -S`)
- Installing kernel modules (`make modules_install`)
- Configuring system services (`systemctl`)
- Writing to `/etc/` directories

### Safety Notes

- Scripts are non-destructive (existing kernels preserved)
- Always run `/test` before `/build-kernel --install`
- Clean command requires confirmation

## Notes for Claude Code

When assisting with this project:

1. **Running Scripts**: All scripts should be run from the project root (`/home/user/ARCH`)

2. **Permissions**: Most operations require sudo for:
   - Installing packages
   - Installing kernel modules
   - Configuring system services

3. **Build Times**: Kernel builds take 15-60 minutes

4. **Verification**: After changes, verify with:
   ```bash
   nvidia-smi          # NVIDIA driver
   boltctl list        # Thunderbolt devices
   uname -r            # Kernel version
   ```

5. **Logs**: Check `logs/` directory for build output

6. **Safety**: The scripts are designed to be non-destructive:
   - Existing kernels are preserved
   - Configuration changes are additive
   - Clean command requires confirmation

## Testing & Debugging

### Test Kernel Build
Before installing, test the kernel build:
```bash
./scripts/test-kernel.sh          # Full test suite
./scripts/test-kernel.sh quick    # Quick sanity check
./scripts/test-kernel.sh hardware # Hardware support check
```

### Debug Mode
Enable debug output for troubleshooting:
```bash
DEBUG=yes ./scripts/build-kernel.sh    # Debug build output
DEBUG=yes ./scripts/test-kernel.sh     # Debug test output
VERBOSE=yes ./scripts/test-kernel.sh   # Verbose test output
```

### Analyze Build Errors
```bash
./scripts/test-kernel.sh errors        # Analyze build log
cat logs/kernel-build.log | tail -100  # View build log
```

### Test Suite Checks
The test suite verifies:
1. **Kernel Image** - bzImage exists and is valid
2. **Modules** - Critical modules (nvidia, iwlwifi, thunderbolt) configured
3. **Configuration** - Required kernel options enabled
4. **Boot Compatibility** - EFI, initramfs, filesystem support
5. **Hardware Support** - Arrow Lake, RTX 5090, TB5, WiFi 7
6. **DKMS Compatibility** - NVIDIA driver can build against kernel

### Environment Variables for Testing
| Variable | Default | Description |
|----------|---------|-------------|
| `DEBUG` | no | Enable debug output |
| `VERBOSE` | no | Enable verbose output |
| `RUN_TESTS` | yes | Run tests after build |
