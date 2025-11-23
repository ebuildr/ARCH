# Test Kernel Build

Run the kernel test suite to verify the build before installation.

## Quick Test
```bash
cd /home/user/ARCH && bash scripts/test-kernel.sh quick
```

## Full Test Suite
```bash
cd /home/user/ARCH && bash scripts/test-kernel.sh test
```

## Test Options

| Command | Description |
|---------|-------------|
| `test` | Full test suite (default) |
| `quick` | Quick sanity check |
| `config` | Configuration validation only |
| `hardware` | Hardware support verification |
| `modules` | Module build verification |
| `debug` | Debug analysis |
| `errors` | Analyze build errors |

## Debug Mode
```bash
cd /home/user/ARCH && DEBUG=yes VERBOSE=yes bash scripts/test-kernel.sh test
```

## What It Tests

1. **Kernel Image** - Verifies bzImage exists and is valid
2. **Modules** - Checks critical modules are built
3. **Configuration** - Validates required kernel options
4. **Boot Compatibility** - EFI, filesystem, NVMe support
5. **Hardware Support** - Arrow Lake, RTX 5090, TB5, WiFi 7
6. **DKMS Compatibility** - Ensures NVIDIA driver can build

## Expected Output
```
✓ bzImage found
✓ System.map found
✓ CONFIG_USB4=y
✓ NVIDIA: DRM subsystem enabled
✓ Thunderbolt 5: USB4 core enabled
✓ WiFi: Intel iwlwifi enabled

ALL TESTS PASSED - Kernel is ready for installation!
```
