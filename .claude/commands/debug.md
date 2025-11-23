# Debug Kernel Build

Debug and troubleshoot kernel build issues.

## Analyze Build Errors
```bash
cd /home/user/ARCH && bash scripts/test-kernel.sh errors
```

## Full Debug Analysis
```bash
cd /home/user/ARCH && DEBUG=yes bash scripts/test-kernel.sh debug
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
