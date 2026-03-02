#!/usr/bin/env bash

# ==========================================
# Raspberry Pi Health Check Script v4.0
# ==========================================
# Features:
# - Hardware Health (Power, Temp, Throttling Decode)
# - CPU Load & Top Processes
# - Memory & Disk (Usage + Speed)
# - System Logs (Kernel/Journal errors)
# - Service Status (SSH, Docker, etc.)
# - Advanced Network (Wi-Fi link, Bluetooth)
# ==========================================

# Strict mode
set -Eeuo pipefail

# --- Configuration ---
# Services to check (add/remove as needed)
CHECK_SERVICES=("ssh" "cron" "docker" "dhcpcd" "NetworkManager" "wpa_supplicant")

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Variables ---
SUMMARY_POWER="UNKNOWN"
SUMMARY_TEMP="UNKNOWN"
SUMMARY_DISK="UNKNOWN"
SUMMARY_NET="UNKNOWN"
SUMMARY_SERVICES="UNKNOWN"
SUMMARY_LOGS="UNKNOWN"
tmpfile=""

# --- Helpers ---

cleanup() {
  if [[ -n "${tmpfile}" && -f "${tmpfile}" ]]; then
    rm -f "${tmpfile}" || true
  fi
}
trap cleanup EXIT

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

print_header() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

decode_throttled() {
  # Decodes the hex value from vcgencmd get_throttled
  # Bit mapping:
  # 0: Under-voltage detected        16: Under-voltage has occurred
  # 1: Arm frequency capped          17: Arm frequency capped has occurred
  # 2: Currently throttled           18: Throttling has occurred
  # 3: Soft temp limit active        19: Soft temp limit has occurred
  
  local hex=$1
  # Convert hex to decimal for bitwise operations
  local val=$((hex))
  local status_msg=""

  if [[ $val -eq 0 ]]; then
     echo "No throttling history."
     return
  fi

  # Active Issues
  (( (val & 0x1) )) && status_msg+="${RED}[ACTIVE] Under-voltage detected! ${NC}\n"
  (( (val & 0x2) )) && status_msg+="${RED}[ACTIVE] ARM Frequency Capped! ${NC}\n"
  (( (val & 0x4) )) && status_msg+="${RED}[ACTIVE] Throttling! ${NC}\n"
  (( (val & 0x8) )) && status_msg+="${RED}[ACTIVE] Soft Temp Limit! ${NC}\n"

  # Past Issues
  (( (val & 0x10000) )) && status_msg+="${YELLOW}[PAST] Under-voltage occurred ${NC}\n"
  (( (val & 0x20000) )) && status_msg+="${YELLOW}[PAST] ARM Frequency Capped occurred ${NC}\n"
  (( (val & 0x40000) )) && status_msg+="${YELLOW}[PAST] Throttling occurred ${NC}\n"
  (( (val & 0x80000) )) && status_msg+="${YELLOW}[PAST] Soft Temp Limit occurred ${NC}\n"

  echo -e "$status_msg"
}

# --- Main Script ---

echo -e "${BLUE}Starting Raspberry Pi Diagnostic Tool v4.0...${NC}"

# 1. System Information
print_header "System Information"
model="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "Unknown")"
hostname="$(hostname)"
echo "Hostname:   $hostname"
echo "Model:      $model"
echo "Kernel:     $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Uptime:     $(uptime -p)"

# 2. CPU Load
print_header "CPU Load"
uptime_load=$(uptime | awk -F'load average:' '{ print $2 }')
echo -e "Load Average:${uptime_load}"
echo "Top Processes (by CPU):"
# Shows top header + 3 processes
top -b -n1 | head -n 10 | tail -n 4 || echo "Unable to run top"

# 3. Power & Throttling (Decoded)
print_header "Power & Throttling Status"
if has_cmd vcgencmd; then
  throttled_output="$(vcgencmd get_throttled || true)"
  throttled_hex="$(echo "${throttled_output}" | cut -d'=' -f2)"

  if [[ "${throttled_hex}" == "0x0" ]]; then
    echo -e "Status: ${GREEN}OK (Power supply stable)${NC}"
    SUMMARY_POWER="${GREEN}PASS${NC}"
  else
    echo -e "Status: ${RED}WARNING (${throttled_hex})${NC}"
    decode_throttled "${throttled_hex}"
    SUMMARY_POWER="${RED}FAIL/WARN${NC}"
  fi
else
  echo -e "${YELLOW}vcgencmd not found (Not a RPi?)${NC}"
  SUMMARY_POWER="N/A"
fi

# 4. Temperature Check
print_header "Temperature Check"
if has_cmd vcgencmd; then
  temp_output="$(vcgencmd measure_temp || true)"
  temp_val="$(echo "${temp_output}" | sed -n 's/.*=\([0-9.]*\).*/\1/p')"
  
  if [[ -n "${temp_val}" ]]; then
    echo "Current Temp: ${temp_val}°C"
    temp_int="${temp_val%.*}"
    if [[ "${temp_int}" -lt 60 ]]; then
      SUMMARY_TEMP="${GREEN}PASS (${temp_val}°C)${NC}"
    elif [[ "${temp_int}" -lt 80 ]]; then
       SUMMARY_TEMP="${YELLOW}WARN (${temp_val}°C)${NC}"
    else
       SUMMARY_TEMP="${RED}FAIL (${temp_val}°C)${NC}"
    fi
  fi
else
  # Fallback to thermal zone if vcgencmd missing
  if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
     temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
     temp_val=$((temp_raw / 1000))
     echo "Current Temp: ${temp_val}°C (from sysfs)"
     SUMMARY_TEMP="${GREEN}PASS (${temp_val}°C)${NC}"
  else
     SUMMARY_TEMP="N/A"
  fi
fi

# 5. Memory Usage
print_header "Memory Usage (MB)"
free -m | awk 'NR==1{next} {print "Type: " $1 " | Total: " $2 " | Used: " $3 " | Free: " $4}'

# 6. Disk Usage & Health
print_header "Disk Usage (Root)"
df_output="$(df -h / | tail -1)"
disk_used_pct="$(echo "${df_output}" | awk '{print $5}')"
echo "${df_output}"

# Simple Log Check
print_header "System Health Logs (Last 5 Errors)"
# dmesg (requires sudo usually, try gracefully)
if dmesg >/dev/null 2>&1; then
    echo -e "${CYAN}--- Kernel Errors (dmesg) ---${NC}"
    dmesg -T | grep -iE "error|voltage|fail" | tail -n 5 || echo "No recent kernel errors found."
else
    echo -e "${YELLOW}Skipping dmesg (requires sudo)${NC}"
fi

echo -e "${CYAN}--- System Journal (Recent Critical) ---${NC}"
if has_cmd journalctl; then
    # Check for Error, Critical, Alert, Emergency
    journalctl -p 3..0 -n 5 --no-pager || echo "No critical journal logs found."
else
    echo "journalctl not available."
fi

# 7. Disk Speed
print_header "Disk Speed Test (Write)"
if has_cmd dd; then
  tmpfile="$(mktemp /tmp/pi_speedtest.XXXXXX)"
  echo "Writing 100MB temp file..."
  dd_res="$(dd if=/dev/zero of="${tmpfile}" bs=1M count=100 conv=fdatasync 2>&1 | tail -n 1 || true)"
  write_speed="$(echo "${dd_res}" | awk '{print $(NF-1) " " $NF}')"
  echo "Speed: ${write_speed}"
else
  write_speed="N/A"
fi

# 8. Service Status
print_header "Service Status Check"
failed_services=0
for srv in "${CHECK_SERVICES[@]}"; do
    if systemctl list-unit-files "${srv}.service" >/dev/null 2>&1; then
        if systemctl is-active --quiet "${srv}"; then
            echo -e "${srv}: ${GREEN}ACTIVE${NC}"
        else
             # Check if it is actually failed or just inactive/dead
             status=$(systemctl is-active "${srv}")
             echo -e "${srv}: ${RED}${status^^}${NC}"
             ((failed_services++))
        fi
    else
        echo -e "${srv}: ${YELLOW}NOT INSTALLED${NC}"
    fi
done

if [[ $failed_services -eq 0 ]]; then
    SUMMARY_SERVICES="${GREEN}ALL OK${NC}"
else
    SUMMARY_SERVICES="${RED}$failed_services ISSUES${NC}"
fi

# 9. Network Details
print_header "Network Interfaces"

# Wi-Fi Details
if has_cmd iw; then
    echo -e "${CYAN}--- Wi-Fi (wlan0) ---${NC}"
    if ip link show wlan0 >/dev/null 2>&1; then
        iw dev wlan0 link 2>/dev/null || echo "wlan0 not connected."
    else
        echo "Interface wlan0 not found."
    fi
fi

# Bluetooth
if has_cmd bluetoothctl; then
     echo -e "${CYAN}--- Bluetooth ---${NC}"
     # Check controller status
     if command -v hciconfig >/dev/null 2>&1; then
        hciconfig dev | grep -E "UP|DOWN" || echo "Bluetooth inactive"
     else
        echo "hciconfig tool not found."
     fi
fi

# IP Check
echo -e "${CYAN}--- Connectivity ---${NC}"
local_ip="$(hostname -I 2>/dev/null || true)"
echo "Local IP: ${local_ip:-None}"

# Ping Test
target="1.1.1.1"
if ping -c 2 -W 2 "${target}" >/dev/null 2>&1; then
    latency="$(ping -c 2 "${target}" | tail -1 | awk -F'/' '{print $5}')"
    echo -e "Internet: ${GREEN}ONLINE${NC} (${latency}ms)"
    SUMMARY_NET="${GREEN}PASS${NC}"
else
    echo -e "Internet: ${RED}UNREACHABLE${NC}"
    SUMMARY_NET="${RED}FAIL${NC}"
fi

# --- Final Summary ---
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}        FINAL SUMMARY REPORT v4.0       ${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Model:        $model"
echo -e "Power/Volt:   $SUMMARY_POWER"
echo -e "Temperature:  $SUMMARY_TEMP"
echo -e "Services:     $SUMMARY_SERVICES"
echo -e "Disk Usage:   $disk_used_pct used"
echo -e "Write Speed:  $write_speed"
echo -e "Network:      $SUMMARY_NET"
echo -e "========================================"
echo ""