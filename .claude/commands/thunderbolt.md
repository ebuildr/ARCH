# Setup Thunderbolt 5 / Razer Dock

Configure Thunderbolt 5 and USB4 support for the Razer Thunderbolt dock.

This will:
1. Install Thunderbolt management tools (bolt)
2. Configure security policies for dock authorization
3. Set up Razer-specific device rules
4. Enable DisplayPort Alt Mode for Samsung Odyssey monitor
5. Configure PCIe tunneling for dock peripherals
6. Set up Thunderbolt networking

Execute:
```bash
cd /home/user/ARCH && bash scripts/setup-thunderbolt.sh
```

After setup, connect your Razer dock and verify:
```bash
boltctl list
```

To authorize a new device:
```bash
boltctl authorize <device-uuid>
```
