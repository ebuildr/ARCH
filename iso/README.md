# ARCH Custom ISO Builder

Build a custom Arch Linux installation ISO with the ARCH kernel builder pre-installed.

## What It Does

Creates a bootable ISO that includes:
- Full Arch Linux installation environment
- ARCH kernel builder pre-configured
- All required dependencies for custom kernel builds
- NVIDIA RTX 5090 driver tools
- Thunderbolt 5 support utilities
- Automated installation script

## Requirements

**Host System:**
- Arch Linux or EndeavourOS (required for archiso)
- 10GB+ free disk space
- Root/sudo access

**Install archiso:**
```bash
sudo pacman -S archiso
```

## Build the ISO

```bash
cd /home/user/ARCH/iso
sudo bash build-iso.sh
```

**Build time:** 15-30 minutes depending on internet speed

**Output:** `iso/out/arch-msi-raider-YYYY.MM.DD-x86_64.iso`

## Write ISO to USB

### Method 1: dd (Recommended)
```bash
# Find USB device
lsblk

# Write ISO (replace sdX with your USB device)
sudo dd if=iso/out/arch-msi-raider-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

### Method 2: cp (Simple)
```bash
sudo cp iso/out/arch-msi-raider-*.iso /dev/sdX
sync
```

### Method 3: Ventoy
Simply copy the ISO to your Ventoy USB drive

## Boot from USB

1. **Insert USB** into MSI Raider 18 HX
2. **Press F11** during boot to access boot menu
3. **Select USB device**
4. **Boot into live environment**

## Installation Options

### Option 1: Automated Installation (Recommended)

The ISO includes an automated installer:

```bash
# After booting the ISO
cd ~/ARCH/iso
bash install-arch.sh
```

The installer will:
- Partition your disk
- Install base Arch Linux
- Set up user account
- Install GRUB bootloader
- Copy ARCH kernel builder to /home/user/ARCH
- Configure network and basic services

**Interactive prompts:**
- Target disk selection
- Username and password
- Hostname

### Option 2: Manual Installation

Use the standard Arch installation process:

```bash
# 1. Connect to network
iwctl  # for WiFi
# or
systemctl start NetworkManager

# 2. Partition disk
cfdisk /dev/nvme0n1

# 3. Format partitions
mkfs.fat -F32 /dev/nvme0n1p1   # EFI
mkfs.ext4 /dev/nvme0n1p2       # Root

# 4. Mount
mount /dev/nvme0n1p2 /mnt
mkdir /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot

# 5. Install base system
pacstrap /mnt base linux linux-firmware

# 6. Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 7. Chroot and configure
arch-chroot /mnt

# 8. Copy ARCH project
cp -r /root/ARCH /home/user/
chown -R user:user /home/user/ARCH

# 9. Continue with standard Arch installation...
```

### Option 3: archinstall (GUI)

```bash
archinstall
```

After installation, copy ARCH project:
```bash
cp -r /root/ARCH /mnt/home/user/
arch-chroot /mnt chown -R user:user /home/user/ARCH
```

## After Installation

Once Arch is installed and you've rebooted:

```bash
# 1. Scan your hardware
cd ~/ARCH
./arch-builder.sh scan

# 2. Build custom kernel
./arch-builder.sh build

# 3. Install NVIDIA drivers
./arch-builder.sh nvidia

# 4. Setup Thunderbolt
./arch-builder.sh thunderbolt

# 5. Setup monitor
./arch-builder.sh monitor

# Or do everything at once:
./arch-builder.sh all
```

## ISO Contents

The custom ISO includes these additional packages:
- **Build tools:** base-devel, git, cmake, ninja
- **Kernel build:** bc, flex, bison, libelf, pahole
- **NVIDIA:** nvidia-dkms, nvidia-utils
- **Thunderbolt:** bolt, thunderbolt-utils
- **Utilities:** vim, htop, tmux, xorg-xrandr
- **ARCH project:** Complete kernel builder in ~/ARCH

## BIOS Settings for MSI Raider 18 HX

Before installation, configure BIOS:

1. **Press DEL** during boot to enter BIOS
2. **Advanced → Integrated Peripherals:**
   - Thunderbolt: **Enabled**
   - VMD Controller: **Enabled** (optional, but recommended)
3. **Security → Secure Boot:**
   - Secure Boot: **Disabled** (easier for custom kernels)
4. **Boot:**
   - Boot Mode: **UEFI**
   - Fast Boot: **Disabled**

## Customizing the ISO

Edit `iso/build-iso.sh` to:
- Add more packages (edit `packages.x86_64` section)
- Change default configuration
- Add additional scripts
- Customize welcome messages

Rebuild after changes:
```bash
sudo bash iso/build-iso.sh clean
sudo bash iso/build-iso.sh build
```

## Troubleshooting

### Build Fails
```bash
# Clean and retry
sudo bash iso/build-iso.sh clean
sudo bash iso/build-iso.sh build
```

### ISO Won't Boot
- Verify USB write completed: `sync`
- Try different USB port
- Check BIOS boot order
- Disable Secure Boot

### Installation Errors
- Check disk space (need 20GB+ for root)
- Verify internet connection
- Check target disk is correct

## File Structure

```
iso/
├── build-iso.sh          # Main ISO builder
├── README.md             # This file
├── profile/              # archiso profile (generated)
├── work/                 # Build workspace (temporary)
└── out/                  # Final ISO output
    └── arch-msi-raider-YYYY.MM.DD-x86_64.iso
```

## Advanced: Network Installation

The ISO supports network installation. After booting:

```bash
# 1. Connect to WiFi
iwctl
[iwd]# device list
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect "Your-WiFi-SSID"

# 2. Verify connection
ping archlinux.org

# 3. Proceed with installation
```

## Size Information

- **ISO Size:** ~1.5-2GB
- **Installed System:** ~5-8GB (before kernel build)
- **After kernel build:** +2-3GB
- **Recommended disk:** 50GB+ for comfort

## Credits

Built with:
- [archiso](https://wiki.archlinux.org/title/Archiso) - Official Arch Linux ISO building tool
- [ARCH](https://github.com/ebuildr/ARCH) - Custom kernel builder for MSI Raider 18 HX

## Support

For issues with:
- **ISO building:** Check archiso documentation
- **ARCH kernel builder:** See main README.md
- **Arch installation:** Visit [Arch Wiki](https://wiki.archlinux.org/title/Installation_guide)
