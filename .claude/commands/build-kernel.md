# Build Custom Kernel

Build the latest stable Linux kernel with hardware-specific optimizations.

This will:
1. Fetch the latest stable kernel from kernel.org
2. Apply hardware-specific configurations for MSI Raider 18 HX
3. Build the kernel with all CPU cores
4. Create Arch Linux packages

Execute:
```bash
cd /home/user/ARCH && bash scripts/build-kernel.sh
```

Options:
- Set `KERNEL_MAJOR=6` and `KERNEL_MINOR=12` to specify version
- Set `JOBS=8` to limit parallel jobs
- Set `INSTALL_KERNEL=yes` to auto-install after build

The build typically takes 15-60 minutes depending on hardware.
