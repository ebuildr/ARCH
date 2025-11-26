# Fix NVIDIA Driver

Troubleshoot and repair NVIDIA RTX 5090 (Blackwell) driver issues.

## Run NVIDIA Fix
```bash
cd /home/user/ARCH && bash scripts/fix-nvidia.sh
```

## What It Fixes

1. **Conflicting Drivers**
   - Removes nouveau driver
   - Blacklists conflicting modules

2. **NVIDIA Installation**
   - Installs correct nvidia-dkms package
   - Installs nvidia-utils and supporting packages

3. **Kernel Headers**
   - Verifies matching kernel headers
   - Installs missing headers

4. **Module Configuration**
   - Enables DRM mode setting for Wayland
   - Enables GSP firmware (required for RTX 5090/Blackwell)
   - Configures power management

5. **Initramfs**
   - Adds NVIDIA modules to initramfs
   - Regenerates for all kernels

6. **DKMS**
   - Removes old NVIDIA builds
   - Rebuilds modules for current kernel

7. **Xorg Configuration**
   - Creates proper Xorg config for RTX 5090

## After Running

**REBOOT REQUIRED** for changes to take effect.

After reboot, verify:
```bash
nvidia-smi                    # Should show RTX 5090
lsmod | grep nvidia           # Should list nvidia modules
glxinfo | grep NVIDIA         # OpenGL info
```

## Common Issues Fixed

- `nvidia-smi` not working
- NVIDIA modules not loading
- nouveau driver conflicts
- Missing kernel headers
- DKMS build failures
- Wayland compatibility issues
- GSP firmware not enabled (Blackwell requirement)

## Manual Check

If issues persist after fix:
```bash
# Check kernel messages
dmesg | grep -i nvidia

# Check module loading
sudo modprobe nvidia

# Verify DKMS status
dkms status
```
