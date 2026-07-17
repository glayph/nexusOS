#!/bin/bash
# ============================================================
#  TajaInit — Init System & Service Manager
#  Parallel boot, dependency resolution, health monitoring
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
CONFIG_DIR="/etc/tajados"
STATE_DIR="/var/lib/tajados"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[TajaInit]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

SERVICES_DIR="$TAJADOS_DIR/services"
ENABLED_DIR="$SERVICES_DIR/enabled"
mkdir -p "$SERVICES_DIR" "$ENABLED_DIR"

# ========== Service Definition ==========
service_create() {
  local name="$1" desc="$2" cmd="$3" deps="${4:-}" after="${5:-}"
  cat > "$SERVICES_DIR/$name.service" << SVC
[Unit]
Description=$desc
After=$after
Requires=$deps

[Service]
Type=simple
ExecStart=$cmd
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC
  ok "Service created: $name"
}

service_enable() {
  local name="$1"
  [[ -f "$SERVICES_DIR/$name.service" ]] || die "Service not found: $name"
  ln -sf "$SERVICES_DIR/$name.service" "$ENABLED_DIR/$name.service"
  systemctl daemon-reload
  systemctl enable "$name" 2>/dev/null || true
  ok "Service enabled: $name"
}

service_disable() {
  local name="$1"
  rm -f "$ENABLED_DIR/$name.service"
  systemctl disable "$name" 2>/dev/null || true
  ok "Service disabled: $name"
}

service_start() {
  local name="$1"
  systemctl start "$name" && ok "Service started: $name"
}

service_stop() {
  local name="$1"
  systemctl stop "$name" && ok "Service stopped: $name"
}

service_restart() {
  local name="$1"
  systemctl restart "$name" && ok "Service restarted: $name"
}

service_status() {
  local name="$1"
  systemctl status "$name" --no-pager
}

service_logs() {
  local name="$1" lines="${2:-50}"
  journalctl -u "$name" -n "$lines" --no-pager
}

service_list() {
  echo "=== Enabled ==="
  ls -1 "$ENABLED_DIR"/*.service 2>/dev/null | xargs -n1 basename | sed 's/.service$//' || echo "None"
  echo -e "\n=== Available ==="
  ls -1 "$SERVICES_DIR"/*.service 2>/dev/null | xargs -n1 basename | sed 's/.service$//' || echo "None"
}

# ========== Parallel Boot Orchestration ==========
boot_analyze() {
  log "Analyzing boot performance..."
  systemd-analyze blame | head -20
  echo ""
  systemd-analyze critical-chain | head -30
}

boot_optimize() {
  log "Optimizing boot..."
  # Disable unnecessary services
  local disable=(
    systemd-resolved
    systemd-timesyncd
    fstrim.timer
    apt-daily.timer
    apt-daily-upgrade.timer
    man-db.timer
    systemd-networkd-wait-online
  )
  for svc in "${disable[@]}"; do
    systemctl disable "$svc" 2>/dev/null && log "Disabled: $svc"
  done
  # Mask debug mounts
  systemctl mask systemd-journald-audit.socket dev-hugepages.mount sys-kernel-debug.mount 2>/dev/null || true
  # Compress initramfs
  echo "COMPRESS=xz" >> /etc/initramfs-tools/initramfs.conf
  update-initramfs -u -k all
  ok "Boot optimized"
}

# ========== Health Monitoring ==========
health_check() {
  local svc="$1"
  systemctl is-active --quiet "$svc" && return 0 || return 1
}

health_monitor() {
  local interval="${1:-30}"
  log "Starting health monitor (interval: ${interval}s)..."
  while true; do
    for svc in "$ENABLED_DIR"/*.service; do
      [[ -f "$svc" ]] || continue
      local name=$(basename "$svc" .service)
      health_check "$name" || {
        warn "Service $name is down! Restarting..."
        service_restart "$name"
        log "Health event: $name restarted at $(date)" >> "$STATE_DIR/health.log"
      }
    done
    sleep "$interval"
  done
}

health_report() {
  echo "=== Service Health Report ==="
  echo "Time: $(date)"
  echo ""
  for svc in "$ENABLED_DIR"/*.service; do
    [[ -f "$svc" ]] || continue
    local name=$(basename "$svc" .service)
    local status=$(systemctl is-active "$name" 2>/dev/null || echo "inactive")
    local since=$(systemctl show -p ActiveEnterTimestamp --value "$name" 2>/dev/null)
    printf "%-30s %-10s %s\n" "$name" "$status" "$since"
  done
}

# ========== Dependency Resolution ==========
deps_resolve() {
  local target="$1"
  local svc_file="$SERVICES_DIR/$target.service"
  [[ -f "$svc_file" ]] || die "Service not found: $target"
  local requires=$(grep -E '^Requires=' "$svc_file" | cut -d= -f2)
  local after=$(grep -E '^After=' "$svc_file" | cut -d= -f2)
  echo "Requires: $requires"
  echo "After: $after"
  for dep in $requires; do
    deps_resolve "$dep"
  done
}

# ========== TUI ==========
tui_menu() {
  while true; do
    local sel
    sel=$(whiptail --title "TajaInit" --menu "Service Manager" 20 70 12 \
      "1" "List Services" \
      "2" "Enable Service" \
      "3" "Disable Service" \
      "4" "Start Service" \
      "5" "Stop Service" \
      "6" "Restart Service" \
      "7" "Service Status" \
      "8" "Service Logs" \
      "9" "Create Service" \
      "10" "Boot Analyze" \
      "11" "Health Report" \
      "12" "Exit" 3>&1 1>&2 2>&3)
    [[ -z "$sel" ]] && break
    case "$sel" in
      1) service_list | whiptail --textbox /dev/stdin 20 70 ;;
      2) local n; n=$(whiptail --inputbox "Service name:" 8 40 3>&1 1>&2 2>&3); service_enable "$n" ;;
      3) local n; n=$(whiptail --inputbox "Service name:" 8 40 3>&1 1>&2 2>&3); service_disable "$n" ;;
      4) local n; n=$(whiptail --inputbox "Service name:" 8 40 3>&1 1>&2 2>&3); service_start "$n" ;;
      5) local n; n=$(whiptail --inputbox "Service name:" 8 40 3>&1 1>&2 2>&3); service_stop "$n" ;;
      6) local n; n=$(whiptail --inputbox "Service name:" 8 40 3>&1 1>&2 2>&3); service_restart "$n" ;;
      7) local n; n=$(whiptail --inputbox "Service name:" 8 40 3>&1 1>&2 2>&3); service_status "$n" | whiptail --textbox /dev/stdin 20 80 ;;
      8) local n; n=$(whiptail --inputbox "Service name:" 8 40 3>&1 1>&2 2>&3); service_logs "$n" | whiptail --textbox /dev/stdin 20 80 ;;
      9) local n d c a; n=$(whiptail --inputbox "Name:" 8 40 3>&1 1>&2 2>&3); d=$(whiptail --inputbox "Description:" 8 40 3>&1 1>&2 2>&3); c=$(whiptail --inputbox "Command:" 8 40 3>&1 1>&2 2>&3); a=$(whiptail --inputbox "After (space-separated):" 8 40 3>&1 1>&2 2>&3); service_create "$n" "$d" "$c" "" "$a" ;;
      10) boot_analyze | whiptail --textbox /dev/stdin 30 100 ;;
      11) health_report | whiptail --textbox /dev/stdin 20 80 ;;
      12) break ;;
    esac
  done
}

# ========== CLI ==========
usage() {
  cat << USAGE
Usage: tajainit <command> [args]

Services:
  tajainit list                        List services
  tajainit enable <name>               Enable service
  tajainit disable <name>              Disable service
  tajainit start <name>                Start service
  tajainit stop <name>                 Stop service
  tajainit restart <name>              Restart service
  tajainit status <name>               Show status
  tajainit logs <name> [lines]         Show logs
  tajainit create <name> <desc> <cmd> [after]  Create service

Boot:
  tajainit boot-analyze                Analyze boot time
  tajainit boot-optimize               Optimize boot

Health:
  tajainit health-report               Show health report
  tajainit health-monitor [interval]   Start monitor daemon

Deps:
  tajainit deps <service>              Resolve dependencies

TUI:
  tajainit tui                         Interactive menu

USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    list) service_list ;;
    enable) service_enable "$@" ;;
    disable) service_disable "$@" ;;
    start) service_start "$@" ;;
    stop) service_stop "$@" ;;
    restart) service_restart "$@" ;;
    status) service_status "$@" ;;
    logs) service_logs "$@" ;;
    create) service_create "$@" ;;
    boot-analyze) boot_analyze ;;
    boot-optimize) boot_optimize ;;
    health-report) health_report ;;
    health-monitor) health_monitor "$@" ;;
    deps) deps_resolve "$@" ;;
    tui) tui_menu ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"