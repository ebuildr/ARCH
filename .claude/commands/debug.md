# Debug System

Comprehensive system diagnostics for hardware, drivers, and kernel issues.

## Full System Diagnostics (Recommended)
```bash
cd /home/user/ARCH && bash scripts/debug-system.sh
```

This checks:
- VMD (Intel Volume Management Device)
- NVIDIA RTX 5090 drivers
- Thunderbolt 5 / DisplayPort
- Razer dock detection
- Samsung Odyssey monitor
- Kernel configuration

## Kernel Build Errors Only
```bash
cd /home/user/ARCH && bash scripts/test-kernel.sh errors
```

## Check Build Log
```bash
cat /home/user/ARCH/logs/kernel-build.log | tail -100
```

## Check Test Log
```bash
ls -la /home/user/ARCH/logs/kernel-test-*.log
cat /home/user/ARCH/logs/kernel-test-*.log | tail -50
```

## Debug Build Command
Run the kernel build with debug output:
```bash
cd /home/user/ARCH && DEBUG=yes VERBOSE=yes bash scripts/build-kernel.sh
```

## Common Issues

### Build Fails
1. Check dependencies: `./arch-builder.sh status`
2. Review build log: `cat logs/kernel-build.log | grep -i error`
3. Clean and retry: `./arch-builder.sh clean && ./arch-builder.sh build`

### Missing Config
1. Run hardware scan: `./arch-builder.sh scan`
2. Check fragment: `cat config/kernel-config-fragment.txt`

### Module Issues
1. Test modules: `bash scripts/test-kernel.sh modules`
2. Check config: `grep CONFIG_MODULES build/linux-*/`.config`

### NVIDIA Compatibility
1. Run DKMS test: `bash scripts/test-kernel.sh test`
2. Check headers: `ls build/linux-*/include/`

## Environment Variables
```bash
DEBUG=yes        # Enable debug output
VERBOSE=yes      # Enable verbose output
RUN_TESTS=no     # Skip automatic tests
JOBS=4           # Limit parallel jobs
```
