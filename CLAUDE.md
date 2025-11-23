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
│   └── setup-thunderbolt.sh # Thunderbolt 5 / Razer dock config
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

- `/scan` - Run hardware scanner
- `/build-kernel` - Build custom kernel
- `/nvidia` - Setup NVIDIA RTX 5090 drivers
- `/thunderbolt` - Configure Thunderbolt 5 / Razer dock

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
