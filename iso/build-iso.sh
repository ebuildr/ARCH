#!/bin/bash
#
# ARCH Custom ISO Builder
# Creates a bootable Arch Linux ISO with pre-configured kernel builder
#
# Requirements:
#   - archiso package
#   - root/sudo access
#   - ~10GB free space
#

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ISO_DIR="${SCRIPT_DIR}"
WORK_DIR="${ISO_DIR}/work"
OUT_DIR="${ISO_DIR}/out"
PROFILE_DIR="${ISO_DIR}/profile"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() { echo -e "${GREEN}[ISO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

# ============================================================================
# Banner
# ============================================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
   █████╗ ██████╗  ██████╗██╗  ██╗     ██╗███████╗ ██████╗
  ██╔══██╗██╔══██╗██╔════╝██║  ██║     ██║██╔════╝██╔═══██╗
  ███████║██████╔╝██║     ███████║     ██║███████╗██║   ██║
  ██╔══██║██╔══██╗██║     ██╔══██║     ██║╚════██║██║   ██║
  ██║  ██║██║  ██║╚██████╗██║  ██║     ██║███████║╚██████╔╝
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝     ╚═╝╚══════╝ ╚═════╝

  Arch Linux Custom ISO Builder
  Version ${VERSION}

  MSI Raider 18 HX - Optimized Installation Media

EOF
    echo -e "${NC}"
}

# ============================================================================
# Check Requirements
# ============================================================================
check_requirements() {
    header "Checking Requirements"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root (for archiso)"
        info "Run with: sudo bash iso/build-iso.sh"
        exit 1
    fi

    # Check for archiso
    if ! pacman -Q archiso &>/dev/null; then
        log "Installing archiso..."
        pacman -Sy --needed --noconfirm archiso
    else
        log "✓ archiso installed"
    fi

    # Check disk space
    local available=$(df -BG "${ISO_DIR}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available" -lt 10 ]; then
        warn "Low disk space: ${available}GB available"
        warn "Recommended: 10GB+ free space"
    else
        log "✓ Disk space: ${available}GB available"
    fi

    log "✓ All requirements met"
}

# ============================================================================
# Create ISO Profile
# ============================================================================
create_profile() {
    header "Creating ISO Profile"

    # Copy base releng profile
    log "Copying archiso releng profile..."
    rm -rf "${PROFILE_DIR}"
    cp -r /usr/share/archiso/configs/releng "${PROFILE_DIR}"

    # Customize packages
    log "Adding custom packages..."
    cat >> "${PROFILE_DIR}/packages.x86_64" << 'EOF'

# ARCH Custom Kernel Builder Dependencies
base-devel
git
wget
curl
bc
flex
bison
libelf
pahole
openssl
perl
python
dkms
linux-headers

# Hardware Support
intel-ucode
nvidia-dkms
nvidia-utils
nvidia-settings
bolt
thunderbolt-utils
usbutils
pciutils

# Network
networkmanager
networkmanager-openvpn
wireless_tools
wpa_supplicant

# Display
xorg-server
xorg-xrandr
xorg-xinit
mesa

# Utilities
vim
nano
htop
tmux
tree
ncdu
lsof
strace
rsync
zip
unzip
edid-decode

# Build Tools
cmake
ninja
meson
pkgconf

EOF

    log "✓ Profile created"
}

# ============================================================================
# Add Custom Files
# ============================================================================
add_custom_files() {
    header "Adding Custom Files"

    local airootfs="${PROFILE_DIR}/airootfs"
    mkdir -p "${airootfs}/root/ARCH"

    log "Copying ARCH project files..."

    # Copy main project files
    rsync -av --exclude='iso' --exclude='build' --exclude='logs' --exclude='.git' \
        "${PROJECT_ROOT}/" "${airootfs}/root/ARCH/"

    # Make scripts executable
    chmod +x "${airootfs}/root/ARCH/arch-builder.sh"
    chmod +x "${airootfs}/root/ARCH/scripts/"*.sh

    # Create welcome message
    cat > "${airootfs}/root/.zshrc" << 'EOF'
# ARCH Custom ISO Welcome

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║  Welcome to ARCH Custom Installation ISO                     ║"
echo "║  MSI Raider 18 HX - Hardware Optimized                       ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "ARCH Kernel Builder is located at: ~/ARCH"
echo ""
echo "Quick Start:"
echo "  1. Install Arch Linux (use archinstall or manual)"
echo "  2. After installation, copy ARCH to /home/user/:"
echo "     cp -r ~/ARCH /mnt/home/user/"
echo "     arch-chroot /mnt chown -R user:user /home/user/ARCH"
echo ""
echo "Or run automated installer:"
echo "  cd ~/ARCH/iso && bash install-arch.sh"
echo ""
echo "For more info:"
echo "  cd ~/ARCH && cat README.md"
echo ""

# Useful aliases
alias arch-scan='cd ~/ARCH && bash scripts/scan-hardware.sh'
alias arch-build='cd ~/ARCH && bash scripts/build-kernel.sh'
alias arch-status='cd ~/ARCH && bash arch-builder.sh status'
alias arch-help='cd ~/ARCH && bash arch-builder.sh --help'

EOF

    # Create auto-start script for live environment
    mkdir -p "${airootfs}/etc/systemd/system/getty@tty1.service.d"
    cat > "${airootfs}/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root - $TERM
EOF

    log "✓ Custom files added"
}

# ============================================================================
# Create Installation Script
# ============================================================================
create_installer() {
    header "Creating Installation Script"

    cat > "${PROFILE_DIR}/airootfs/root/ARCH/iso/install-arch.sh" << 'INSTALLER_EOF'
#!/bin/bash
#
# ARCH Automated Installer
# Installs Arch Linux with ARCH kernel builder pre-configured
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[INSTALL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

clear
echo -e "${CYAN}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║          ARCH - Automated Arch Linux Installer               ║
║          MSI Raider 18 HX Optimized                          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Confirm installation
echo ""
warn "This will install Arch Linux and erase the target disk!"
echo ""
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log "Installation cancelled"
    exit 0
fi

# Disk selection
echo ""
log "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v loop

echo ""
read -p "Enter target disk (e.g., nvme0n1, sda): " DISK
DISK="/dev/${DISK}"

if [ ! -b "$DISK" ]; then
    error "Invalid disk: $DISK"
fi

warn "All data on $DISK will be ERASED!"
read -p "Type 'YES' to confirm: " final_confirm
if [ "$final_confirm" != "YES" ]; then
    log "Installation cancelled"
    exit 0
fi

# Get user info
echo ""
read -p "Enter username: " USERNAME
read -sp "Enter password: " PASSWORD
echo ""
read -p "Enter hostname [arch-msi]: " HOSTNAME
HOSTNAME="${HOSTNAME:-arch-msi}"

# Partition disk
log "Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 1GiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 1GiB 100%

# Determine partition names
if [[ "$DISK" == *"nvme"* ]]; then
    PART_BOOT="${DISK}p1"
    PART_ROOT="${DISK}p2"
else
    PART_BOOT="${DISK}1"
    PART_ROOT="${DISK}2"
fi

# Format partitions
log "Formatting partitions..."
mkfs.fat -F32 "$PART_BOOT"
mkfs.ext4 -F "$PART_ROOT"

# Mount partitions
log "Mounting partitions..."
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_BOOT" /mnt/boot

# Install base system
log "Installing base system..."
pacstrap /mnt base base-devel linux linux-firmware \
    intel-ucode networkmanager git sudo vim \
    grub efibootmgr

# Generate fstab
log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Configure system
log "Configuring system..."
arch-chroot /mnt bash << CHROOT_EOF
# Set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

# Create user
useradd -m -G wheel,storage,power,audio,video -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd

# Enable sudo for wheel group
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Enable services
systemctl enable NetworkManager

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH
grub-mkconfig -o /boot/grub/grub.cfg

CHROOT_EOF

# Copy ARCH project
log "Installing ARCH kernel builder..."
mkdir -p "/mnt/home/$USERNAME/ARCH"
cp -r /root/ARCH/* "/mnt/home/$USERNAME/ARCH/"
arch-chroot /mnt chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/ARCH"

log ""
log "═══════════════════════════════════════════════════════════════"
log "  Installation Complete!"
log "═══════════════════════════════════════════════════════════════"
log ""
log "Next steps:"
log "  1. Reboot: reboot"
log "  2. Login as: $USERNAME"
log "  3. Build custom kernel:"
log "     cd ~/ARCH"
log "     ./arch-builder.sh scan"
log "     ./arch-builder.sh build"
log "     ./arch-builder.sh nvidia"
log "     ./arch-builder.sh thunderbolt"
log ""

umount -R /mnt
log "You can now reboot"
INSTALLER_EOF

    chmod +x "${PROFILE_DIR}/airootfs/root/ARCH/iso/install-arch.sh"
    log "✓ Installation script created"
}

# ============================================================================
# Customize ISO
# ============================================================================
customize_iso() {
    header "Customizing ISO"

    # Set ISO label
    log "Setting ISO label..."
    sed -i 's/iso_label=.*/iso_label="ARCH_MSI_RAIDER"/' "${PROFILE_DIR}/profiledef.sh"

    # Set ISO name
    sed -i 's/iso_name=.*/iso_name="arch-msi-raider"/' "${PROFILE_DIR}/profiledef.sh"

    # Add boot message
    mkdir -p "${PROFILE_DIR}/airootfs/etc/motd.d"
    cat > "${PROFILE_DIR}/airootfs/etc/motd.d/00-arch-custom" << 'EOF'

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║         ARCH - MSI Raider 18 HX Custom ISO                   ║
║                                                               ║
║  This ISO includes:                                           ║
║    • Custom kernel builder for your hardware                 ║
║    • Intel Core Ultra 9 285HX support                        ║
║    • NVIDIA RTX 5090 driver setup                            ║
║    • Thunderbolt 5 configuration                             ║
║    • Razer dock support                                      ║
║                                                               ║
║  Get started:                                                 ║
║    cd ~/ARCH                                                  ║
║    ./arch-builder.sh --help                                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

EOF

    log "✓ ISO customized"
}

# ============================================================================
# Build ISO
# ============================================================================
build_iso() {
    header "Building ISO"

    log "Starting mkarchiso..."
    log "This may take 15-30 minutes..."

    mkdir -p "$OUT_DIR"

    # Build the ISO
    mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

    if [ $? -eq 0 ]; then
        log ""
        log "═══════════════════════════════════════════════════════════════"
        log "${GREEN}  ✓ ISO BUILD SUCCESSFUL!${NC}"
        log "═══════════════════════════════════════════════════════════════"
        log ""
        log "ISO created:"
        ls -lh "$OUT_DIR"/*.iso
        log ""
        log "Write to USB:"
        log "  sudo dd if=$OUT_DIR/*.iso of=/dev/sdX bs=4M status=progress oflag=sync"
        log ""
        log "Or use:"
        log "  sudo cp $OUT_DIR/*.iso /dev/sdX"
        log "  sync"
        log ""
    else
        error "ISO build failed!"
    fi
}

# ============================================================================
# Clean
# ============================================================================
clean() {
    header "Cleaning Build Files"

    log "Removing work directory..."
    rm -rf "$WORK_DIR"

    log "Removing profile..."
    rm -rf "$PROFILE_DIR"

    log "✓ Clean complete"
}

# ============================================================================
# Main
# ============================================================================
main() {
    show_banner

    case "${1:-build}" in
        build)
            check_requirements
            create_profile
            add_custom_files
            create_installer
            customize_iso
            build_iso
            ;;
        clean)
            clean
            ;;
        *)
            echo "Usage: $0 {build|clean}"
            exit 1
            ;;
    esac
}

main "$@"
