# Scan Hardware

Scan the system hardware and generate kernel configuration.

Run the hardware scanner to detect:
- CPU (Intel Core Ultra 9 285HX / Arrow Lake)
- GPU (NVIDIA RTX 5090 / Intel Xe)
- Thunderbolt 5 controllers
- WiFi 7 (Killer BE1750x)
- NVMe storage
- Audio devices

Execute:
```bash
cd /home/user/ARCH && bash scripts/scan-hardware.sh
```

After scanning, review the generated files:
- `config/hardware-report.txt` - Human-readable hardware report
- `config/kernel-config-fragment.txt` - Kernel config options
- `config/required-modules.txt` - Required kernel modules
- `config/hardware.json` - Machine-readable JSON report
