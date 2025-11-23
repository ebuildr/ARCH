# ARCH - Arch Linux Custom Kernel & Hardware Builder

Build custom Linux kernels optimized for modern hardware on EndeavourOS/Arch Linux.

## Features

- **Hardware Detection**: Automatically scans and identifies all system hardware
- **Custom Kernel Build**: Downloads and builds the latest stable kernel with hardware-specific optimizations
- **NVIDIA RTX 5090 Support**: Full support for Blackwell (SM120) GPUs with 570+ drivers
- **Thunderbolt 5**: Complete setup for USB4/Thunderbolt 5 docks including Razer
- **Intel Arrow Lake**: Optimized for Intel Core Ultra (hybrid CPU architecture)
- **WiFi 7**: Intel Killer BE1750x (BE200) support
- **Claude Code Ready**: Integrated slash commands for AI-assisted operation

## Supported Hardware

| Component | Model | Support |
|-----------|-------|---------|
| CPU | Intel Core Ultra 9 285HX | Full (Arrow Lake) |
| dGPU | NVIDIA RTX 5090 Laptop | Full (Blackwell SM120) |
| iGPU | Intel Xe Graphics | Full |
| WiFi | Killer WiFi 7 BE1750x | Full (iwlwifi) |
| Dock | Razer Thunderbolt 5 | Full |
| Monitor | Samsung Odyssey | Full (DisplayPort) |
| Storage | WD_BLACK NVMe | Full |

## Quick Start

```bash
# Clone the repository
git clone <repo-url> ARCH
cd ARCH

# Make scripts executable
chmod +x arch-builder.sh scripts/*.sh

# Run complete setup
./arch-builder.sh all

# Or run individual components
./arch-builder.sh scan          # Scan hardware
./arch-builder.sh build         # Build kernel
./arch-builder.sh nvidia        # Setup NVIDIA
./arch-builder.sh thunderbolt   # Setup Thunderbolt
```

## Usage

### Main Commands

```bash
./arch-builder.sh [command] [options]

Commands:
  scan          Scan system hardware
  build         Build custom kernel
  nvidia        Install NVIDIA drivers
  thunderbolt   Configure Thunderbolt
  all           Complete setup
  status        Show system status
  clean         Clean build files

Options:
  --install         Install kernel after building
  --no-nvidia       Skip NVIDIA setup
  --no-thunderbolt  Skip Thunderbolt setup
  -j, --jobs N      Parallel build jobs
  -k, --kernel VER  Specify kernel version
```

### Claude Code Commands

If using Claude Code, these slash commands are available:

- `/scan` - Run hardware scanner
- `/build-kernel` - Build custom kernel
- `/nvidia` - Setup NVIDIA drivers
- `/thunderbolt` - Configure Thunderbolt

## Requirements

### EndeavourOS / Arch Linux

```bash
sudo pacman -S --needed base-devel bc libelf pahole perl openssl \
    git wget curl bolt linux-headers dkms
```

### For NVIDIA

```bash
sudo pacman -S --needed nvidia-open nvidia-utils nvidia-settings
```

## Configuration

### Environment Variables

```bash
export KERNEL_MAJOR=6           # Kernel major version
export KERNEL_MINOR=12          # Kernel minor version (optional)
export JOBS=8                   # Parallel build jobs
export INSTALL_KERNEL=yes       # Auto-install kernel
export AUTO_REBOOT=yes          # Auto-reboot after kernel installation
export USE_OPEN_KERNEL=yes      # Use NVIDIA open modules
export NVIDIA_DRIVER_BRANCH=570 # NVIDIA driver branch
```

### Kernel Configuration

After running `scan`, the kernel configuration is generated at:
- `config/kernel-config-fragment.txt`

You can edit this file to add/remove kernel options before building.

## Output Files

After scanning and building:

```
config/
├── hardware-report.txt      # Hardware details
├── kernel-config-fragment.txt # Kernel config
├── required-modules.txt     # Module list
└── hardware.json            # JSON report

build/
├── linux-6.x.y/            # Kernel source
└── packages/               # Arch packages
    ├── PKGBUILD
    └── staging/
```

## Post-Installation

After building and installing:

1. **Reboot** to use the new kernel

2. **Verify kernel**:
   ```bash
   uname -r
   # Should show: 6.x.y-arch-custom
   ```

3. **Verify NVIDIA**:
   ```bash
   nvidia-smi
   ```

4. **Verify Thunderbolt**:
   ```bash
   boltctl list
   ```

## Troubleshooting

### NVIDIA not loading
```bash
# Check module status
lsmod | grep nvidia

# Check for errors
dmesg | grep -i nvidia

# Rebuild with DKMS
sudo dkms autoinstall
```

### Thunderbolt device not authorized
```bash
# List devices
boltctl list

# Authorize device
boltctl authorize <uuid>

# For permanent authorization
boltctl enroll <uuid>
```

### Kernel build fails
```bash
# Check logs
cat logs/kernel-build.log

# Clean and retry
./arch-builder.sh clean
./arch-builder.sh build
```

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions welcome! Please submit issues and pull requests.
