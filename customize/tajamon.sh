#!/bin/bash
# ============================================================
#  Tajamon — System Monitor & Diagnostics Dashboard
#  CPU, RAM, Disk, Network, GPU, Temps, Battery, Processes
# ============================================================
set -euo pipefail

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[Tajamon]${N} $*"; }

mon_cpu() {
  echo "=== CPU ==="
  lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core|Socket|MHz'
  echo "Usage: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')%"
  echo "Load: $(cat /proc/loadavg)"
}

mon_mem() {
  echo "=== Memory ==="
  free -h
  echo ""
  swapon --show 2>/dev/null || echo "No swap"
}

mon_disk() {
  echo "=== Disk ==="
  df -h | grep -v tmpfs | grep -v devtmpfs
  echo ""
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL | head -20
}

mon_net() {
  echo "=== Network ==="
  ip -br addr
  echo ""
  echo "Active connections:"
  ss -tun | head -20
}

mon_gpu() {
  echo "=== GPU ==="
  lspci | grep -iE 'vga|3d|display' | head -5
  nvidia-smi 2>/dev/null | head -15 || echo "No NVIDIA GPU detected"
}

mon_temp() {
  echo "=== Temperature ==="
  sensors 2>/dev/null | head -30 || echo "lm-sensors not installed"
  cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | while read t; do echo "Zone: $((t/1000))°C"; done
}

mon_battery() {
  echo "=== Battery ==="
  upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null | head -15
  cat /sys/class/power_supply/BAT0/capacity 2>/dev/null && echo "%" || echo "No battery"
}

mon_processes() {
  echo "=== Top Processes (by CPU) ==="
  ps aux --sort=-%cpu | head -15
  echo ""
  echo "=== Top Processes (by MEM) ==="
  ps aux --sort=-%mem | head -15
}

mon_services() {
  echo "=== Services ==="
  systemctl list-units --type=service --state=running --no-legend | head -20
  echo ""
  systemctl list-units --failed --no-legend | head -10
}

mon_logs() {
  local lines="${1:-20}"
  journalctl -n "$lines" --no-pager -o short-monotonic
}

mon_dashboard() {
  while true; do
    clear
    local cols=$(tput cols)
    printf "\033[96m%*s\033[0m\n" $(( (cols+34)/2 )) "=== TajaOS System Dashboard ==="
    echo ""
    printf "%-20s %s\n" "Date:" "$(date)"
    printf "%-20s %s\n" "Uptime:" "$(uptime -p 2>/dev/null || uptime)"
    printf "%-20s %s\n" "CPU:" "$(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')%"
    printf "%-20s %s\n" "Memory:" "$(free -h | awk '/Mem:/ {print $3"/"$2}')"
    printf "%-20s %s\n" "Disk (/) :" "$(df -h / | tail -1 | awk '{print $3"/"$2}')"
    printf "%-20s %s\n" "Load:" "$(cat /proc/loadavg)"
    printf "%-20s %s\n" "Network:" "$(ip -br addr | grep -v lo | head -3 | awk '{print $1": "$3}' | xargs)"
    echo ""
    echo "=== Top 10 Processes ==="
    ps aux --sort=-%cpu | head -10
    echo ""
    echo "=== Disk I/O ==="
    iostat -x 1 1 2>/dev/null | tail -10 || echo "sysstat not installed"
    echo ""
    echo "Press Ctrl+C to exit"
    sleep 2
  done
}

usage() {
  cat << USAGE
Usage: tajamon <command>

  cpu        CPU info & usage
  mem        Memory usage
  disk       Disk usage & layout
  net        Network interfaces & connections
  gpu        GPU detection & stats
  temp       Temperature sensors
  battery    Battery status
  processes  Top processes
  services   Running & failed services
  logs       Recent system logs
  dashboard  Live dashboard (refresh every 2s)
USAGE
}

main() {
  [[ $# -eq 0 ]] && { mon_dashboard; exit 0; }
  case "$1" in
    cpu) mon_cpu ;;
    mem) mon_mem ;;
    disk) mon_disk ;;
    net) mon_net ;;
    gpu) mon_gpu ;;
    temp) mon_temp ;;
    battery) mon_battery ;;
    processes) mon_processes ;;
    services) mon_services ;;
    logs) mon_logs "${2:-}" ;;
    dashboard) mon_dashboard ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"