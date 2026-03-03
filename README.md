# Raspberry Pi Health Check Script

[![Bash](https://img.shields.io/badge/Shell-Bash-121011?logo=gnubash)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Raspberry%20Pi-C51A4A?logo=raspberrypi)](https://www.raspberrypi.com/)
[![Status](https://img.shields.io/badge/Status-Active-success)](#)

A fast, all-in-one diagnostic script for Raspberry Pi systems.

`rpi-test.sh` checks CPU load, temperature, power/throttling, memory, disk usage/speed, system logs, service health, and network connectivity, then prints a final summary report.

## Features

- **System info**: Hostname, model, kernel, architecture, uptime
- **Power + throttling**: Reads `vcgencmd get_throttled` and decodes active/past issues
- **Temperature check**: Uses `vcgencmd` (or sysfs fallback)
- **CPU + memory**: Load average, top processes, RAM usage
- **Disk health**: Root usage + write speed test (`dd`)
- **Log scan**: Recent kernel/system critical errors (`dmesg`, `journalctl`)
- **Service status**: Checks core services (SSH, cron, Docker, network services)
- **Network checks**: Wi-Fi details, Bluetooth state, local IP, internet ping test

## What This Script Is

This is a practical health-check utility for Raspberry Pi devices. It is useful for:

- quick post-boot checks,
- routine maintenance,
- troubleshooting power, heat, storage, service, and network issues.

## File

- `rpi-test.sh` - Main diagnostic script

## Requirements

- Bash 4+
- Recommended commands: `vcgencmd`, `top`, `free`, `df`, `dd`, `systemctl`, `journalctl`, `ping`, `ip`
- Optional commands: `iw`, `bluetoothctl`, `hciconfig`

The script handles missing optional tools gracefully.

## Setup

```bash
chmod +x rpi-test.sh
```

## Usage

```bash
./rpi-test.sh
```

## Output Sections

- `System Information`
- `CPU Load`
- `Power & Throttling Status`
- `Temperature Check`
- `Memory Usage`
- `Disk Usage`
- `System Health Logs`
- `Disk Speed Test`
- `Service Status Check`
- `Network Interfaces`
- `FINAL SUMMARY REPORT`

## Customize Service Checks

Edit this array in `rpi-test.sh`:

```bash
CHECK_SERVICES=("ssh" "cron" "docker" "dhcpcd" "NetworkManager" "wpa_supplicant")
```

## Open Source License: MIT

## Troubleshooting

- If `vcgencmd` is missing, install Raspberry Pi firmware/userland tools.
- If `dmesg` access is restricted, run with elevated privileges when appropriate.
- `NOT INSTALLED` service entries are expected on setups where those services are not present.
