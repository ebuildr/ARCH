# Setup Samsung Odyssey Monitor

Configure Samsung Odyssey monitor via Razer Thunderbolt 5 Dock DisplayPort.

## Full Setup
```bash
cd /home/user/ARCH && bash scripts/setup-monitor.sh
```

## Individual Commands

| Command | Description |
|---------|-------------|
| `detect` | Detect connected monitors |
| `configure` | Create display configuration |
| `test` | Test display setup |
| `help` | Show xrandr commands |

```bash
# Detect monitors only
bash scripts/setup-monitor.sh detect

# Just configure (no test)
bash scripts/setup-monitor.sh configure

# Test current setup
bash scripts/setup-monitor.sh test
```

## What It Configures

- **Xorg**: High refresh rate, VRR, HDR, G-Sync Compatible
- **Wayland**: GNOME/KDE VRR support, HDR
- **NVIDIA**: GPU settings for external display via TB5
- **Modelines**: Custom modes for 144Hz/240Hz

## Supported Odyssey Models

- Odyssey G9 (5120x1440 @ 240Hz)
- Odyssey G7 (2560x1440 @ 240Hz)
- Odyssey Neo G9 (Mini-LED)
- Odyssey OLED G9
- Odyssey Ark (3840x2160 @ 165Hz)

## Quick xrandr Commands

```bash
# List displays
xrandr --query

# Set 4K @ 144Hz
xrandr --output DP-1 --mode 3840x2160 --rate 144

# Set as primary
xrandr --output DP-1 --primary
```
