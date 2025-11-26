# Fix Thunderbolt / DisplayPort

Troubleshoot Razer Thunderbolt 5 Dock and Samsung Odyssey monitor detection.

## Run Thunderbolt/DisplayPort Fix
```bash
cd /home/user/ARCH && bash scripts/fix-thunderbolt-displayport.sh
```

## What It Fixes

1. **Thunderbolt Management**
   - Installs and enables bolt service
   - Authorizes all Thunderbolt devices
   - Sets auto-authorization policy

2. **Kernel Modules**
   - Loads thunderbolt/usb4 modules
   - Loads Type-C and DisplayPort Alt Mode modules

3. **PCIe Tunneling**
   - Verifies PCIe devices through Thunderbolt
   - Checks hotplug events

4. **DisplayPort Detection**
   - Forces DRM connector detection
   - Rescans display devices
   - Checks EDID information

5. **Display Configuration**
   - Configures xrandr for connected displays
   - Sets high refresh rate modes (144Hz/240Hz)
   - Detects Samsung Odyssey specifically

6. **Udev Rules**
   - Creates auto-authorization rules
   - Configures bolt to handle new devices

## After Running

Check results:
```bash
# Thunderbolt devices
boltctl list

# Connected displays
xrandr --query

# DRM connectors
cat /sys/class/drm/card*-*/status
```

## Common Issues Fixed

- Razer Thunderbolt 5 Dock not detected
- Samsung Odyssey monitor not showing up
- DisplayPort not working through dock
- Thunderbolt devices require manual authorization
- PCIe tunneling not working
- DisplayPort Alt Mode not enabled

## Troubleshooting

If monitor still not detected:

1. **Physical Connection**
   - Verify DisplayPort cable is properly connected
   - Try different DP ports on the dock
   - Check monitor power and input source

2. **BIOS Settings**
   - Enable Thunderbolt in BIOS
   - Set Thunderbolt security to "No Security" or "User Authorization"

3. **Authorization**
   ```bash
   # List devices
   boltctl list

   # Authorize specific device
   sudo boltctl authorize <device-uuid>
   ```

4. **Kernel Messages**
   ```bash
   dmesg | grep -iE "thunderbolt|displayport"
   ```

5. **Reboot**
   Sometimes a reboot with dock connected helps

## NVIDIA Compatibility

The Thunderbolt/DP fix checks NVIDIA driver status. If NVIDIA driver is not working, the external display may not work even if Thunderbolt is properly configured.

Fix NVIDIA first if needed:
```bash
bash scripts/fix-nvidia.sh
```
