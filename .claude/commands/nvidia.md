# Setup NVIDIA RTX 5090 Drivers

Install and configure NVIDIA drivers for the RTX 5090 (Blackwell SM120).

This will:
1. Detect your NVIDIA GPU
2. Install the latest NVIDIA 570+ drivers (required for Blackwell)
3. Configure hybrid graphics (Optimus)
4. Set up power management
5. Enable DRM modeset for Wayland

Execute:
```bash
cd /home/user/ARCH && bash scripts/build-nvidia.sh
```

Options:
- Set `USE_OPEN_KERNEL=yes` to use open-source kernel modules (recommended)
- Set `INSTALL_METHOD=source` to build from NVIDIA .run file instead of pacman

After installation, reboot and verify with:
```bash
nvidia-smi
```
