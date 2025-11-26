# Fix All System Issues

Run comprehensive fix for all three issues:
1. VMD (Intel Volume Management Device)
2. NVIDIA RTX 5090 drivers
3. Thunderbolt 5 / DisplayPort (Razer dock + Samsung Odyssey)

## Interactive Mode (Recommended)
```bash
cd /home/user/ARCH && bash scripts/fix-all.sh
```

## Auto Mode (Skip Confirmations)
```bash
cd /home/user/ARCH && bash scripts/fix-all.sh --yes
```

## What It Does

### Phase 1: Diagnostics
- Runs comprehensive system diagnostics
- Identifies all hardware issues

### Phase 2: VMD Support
- Enables CONFIG_VMD in kernel
- Rebuilds kernel with Intel Arrow Lake NVMe support

### Phase 3: NVIDIA Fix
- Reinstalls NVIDIA drivers for RTX 5090 (Blackwell)
- Configures GSP firmware
- Blacklists nouveau
- Rebuilds DKMS modules

### Phase 4: Thunderbolt/DisplayPort Fix
- Enables and configures bolt service
- Authorizes Thunderbolt devices
- Forces DisplayPort detection
- Configures Samsung Odyssey monitor

## Individual Fixes

If you want to fix only specific issues:

```bash
# Fix NVIDIA only
bash scripts/fix-nvidia.sh

# Fix Thunderbolt/DisplayPort only
bash scripts/fix-thunderbolt-displayport.sh

# Debug only (no fixes)
bash scripts/debug-system.sh
```

## After Running

1. Review the output for any errors
2. Check logs in `logs/` directory
3. **REBOOT REQUIRED** for changes to take effect
4. After reboot, verify:
   - `nvidia-smi` - NVIDIA driver
   - `boltctl list` - Thunderbolt devices
   - `xrandr --query` - Display detection

## Troubleshooting

If fixes don't work:
1. Check individual fix logs in `logs/`
2. Run debug script: `bash scripts/debug-system.sh`
3. Review BIOS settings (Thunderbolt enabled, VMD enabled)
4. Ensure physical connections are secure
