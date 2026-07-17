#!/bin/bash
# ============================================================
#  TajaDev — Developer Toolkit
#  Containers, VMs, build environments, code editor TUI
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
STATE_DIR="/var/lib/tajados"
CONFIG_DIR="/etc/tajados"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[TajaDev]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

# Containers (using systemd-nspawn)
dev_container_create() {
  local name="$1" distro="${2:-ubuntu}" release="${3:-noble}"
  if [[ "$distro" == "ubuntu" ]]; then
    debootstrap --arch=amd64 "$release" "/var/lib/machines/$name" http://archive.ubuntu.com/ubuntu/
  elif [[ "$distro" == "debian" ]]; then
    debootstrap --arch=amd64 "$release" "/var/lib/machines/$name" http://deb.debian.org/debian/
  fi
  systemd-machinectl enable "$name"
  ok "Container '$name' created ($distro $release)"
}

dev_container_run() { systemd-nspawn -D "/var/lib/machines/$1" "$2"; }
dev_container_shell() { machinectl shell "$1"; }
dev_container_list() { machinectl list-images 2>/dev/null || ls -1 /var/lib/machines/ 2>/dev/null; }
dev_container_stop() { machinectl poweroff "$1" 2>/dev/null; }

# VMs (using qemu)
dev_vm_create() {
  local name="$1" ram="${2:-1024}" disk="${3:-10}"
  local img="/var/lib/vms/${name}.qcow2"
  qemu-img create -f qcow2 "$img" "${disk}G"
  ok "VM '$name' created ($ram MB, ${disk}G disk)"
}

dev_vm_start() { qemu-system-x86_64 -m "$2" -drive file="/var/lib/vms/$1.qcow2" -enable-kvm &; }
dev_vm_list() { ls -1 /var/lib/vms/ 2>/dev/null; }

# Build environments
dev_env_create() {
  local name="$1" lang="$2"
  case "$lang" in
    python) apt-get install -y python3 python3-pip python3-venv build-essential ;;
    node) apt-get install -y nodejs npm ;;
    go) apt-get install -y golang-go ;;
    rust) apt-get install -y rustc cargo ;;
    c) apt-get install -y build-essential cmake gdb ;;
    *) die "Unsupported: $lang" ;;
  esac
  ok "Build env '$name' created for $lang"
}

# Project templates
dev_template_list() {
  echo "python: basic, flask, fastapi"
  echo "node: express, cli"
  echo "c: library, executable"
  echo "bash: script, plugin"
}

dev_template_new() {
  local name="$1" template="$2"
  mkdir -p "$name"
  case "$template" in
    python-basic)
      cat > "$name/main.py" << 'PY'
#!/usr/bin/env python3
def main():
    print("Hello from TajaOS!")
if __name__ == "__main__":
    main()
PY
      cat > "$name/requirements.txt" << 'REQ'
click>=8.0
REQ
      ;;
    python-flask)
      cat > "$name/app.py" << 'PY'
from flask import Flask
app = Flask(__name__)
@app.route("/")
def hello():
    return "Hello from TajaOS!"
PY
      echo "flask" > "$name/requirements.txt"
      ;;
    bash-script)
      cat > "$name/run.sh" << 'SH'
#!/bin/bash
set -euo pipefail
main() { echo "Hello from TajaOS!"; }
main "$@"
SH
      chmod +x "$name/run.sh"
      ;;
    *) die "Unknown template: $template" ;;
  esac
  ok "Project '$name' created from '$template' template"
}

# Log viewer
dev_log_viewer() {
  local service="${1:-}"
  if [[ -n "$service" ]]; then
    journalctl -u "$service" -f --no-pager -n 50
  else
    journalctl -f --no-pager -n 50
  fi
}

# Process monitor (htop-like)
dev_process_monitor() {
  while true; do
    clear
    echo -e "\033[96m=== TajaOS Process Monitor ===\033[0m"
    echo "CPU: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')%  Mem: $(free -m | awk '/Mem:/ {print $3"/"$2"MB"}')"
    echo ""
    ps aux --sort=-%cpu | head -20
    sleep 2
  done
}

usage() {
  cat << USAGE
Usage: tajadev <command> [args]

Containers:
  container-create <name> [distro] [release]
  container-run <name> <cmd>
  container-shell <name>
  container-list
  container-stop <name>

VMs:
  vm-create <name> [ram_mb] [disk_gb]
  vm-start <name> [ram_mb]
  vm-list

Build Env:
  env-create <name> <lang>

Templates:
  template-list
  template-new <name> <template>

Logs: tajadev logs [service]
Monitor: tajadev monitor
USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    container-create) dev_container_create "$@" ;;
    container-run) dev_container_run "$@" ;;
    container-shell) dev_container_shell "$@" ;;
    container-list) dev_container_list ;;
    container-stop) dev_container_stop "$@" ;;
    vm-create) dev_vm_create "$@" ;;
    vm-start) dev_vm_start "$@" ;;
    vm-list) dev_vm_list ;;
    env-create) dev_env_create "$@" ;;
    template-list) dev_template_list ;;
    template-new) dev_template_new "$@" ;;
    logs) dev_log_viewer "$@" ;;
    monitor) dev_process_monitor ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"