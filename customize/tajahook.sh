#!/bin/bash
# ============================================================
#  TajaHook — Event Hook System
#  Lifecycle events, triggers, async execution
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
CONFIG_DIR="/etc/tajados"
STATE_DIR="/var/lib/tajados"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[TajaHook]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

HOOKS_DIR="$TAJADOS_DIR/hooks"
mkdir -p "$HOOKS_DIR"

# Built-in events
BUILTIN_EVENTS=(
  "boot:pre" "boot:post"
  "shutdown:pre" "shutdown:post"
  "network:up" "network:down"
  "user:login" "user:logout"
  "service:start" "service:stop" "service:fail"
  "disk:mount" "disk:unmount" "disk:full"
  "cpu:high" "mem:high" "temp:high"
  "pkg:install" "pkg:remove" "pkg:update"
  "config:change" "config:reload"
  "backup:pre" "backup:post"
  "update:pre" "update:post"
  "security:alert"
)

hook_register() {
  local event="$1" script="$2" priority="${3:-50}"
  [[ -f "$script" ]] || die "Script not found: $script"
  [[ -x "$script" ]] || chmod +x "$script"
  mkdir -p "$HOOKS_DIR/$event"
  local target="$HOOKS_DIR/$event/${priority}_$(basename "$script")"
  ln -sf "$script" "$target"
  ok "Hook registered: $event -> $(basename "$script") (priority $priority)"
}

hook_unregister() {
  local event="$1" script="$2"
  rm -f "$HOOKS_DIR/$event"/"$(basename "$script")" "$HOOKS_DIR/$event"/*_"$(basename "$script")"
  ok "Hook unregistered: $event -> $script"
}

hook_list() {
  local event="${1:-}"
  if [[ -n "$event" ]]; then
    echo "=== Hooks for: $event ==="
    ls -1 "$HOOKS_DIR/$event" 2>/dev/null | sed 's/^[0-9]*_//' || echo "None"
  else
    for d in "$HOOKS_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local ev=$(basename "$d")
      echo "=== $ev ==="
      ls -1 "$d" 2>/dev/null | sed 's/^[0-9]*_//' | sed 's/^/  /'
    done
  fi
}

hook_run() {
  local event="$1"; shift
  local args=("$@")
  local hook_dir="$HOOKS_DIR/$event"
  [[ -d "$hook_dir" ]] || { log "No hooks for event: $event"; return 0; }
  log "Running hooks for: $event (${#args[@]} args)"
  for hook in "$hook_dir"/*; do
    [[ -x "$hook" ]] || continue
    local name=$(basename "$hook")
    local priority=${name%%_*}
    name=${name#*_}
    log "Executing [$priority] $name..."
    if "$hook" "$event" "${args[@]}" >> "$STATE_DIR/hooks.log" 2>&1; then
      ok "Hook [$priority] $name completed"
    else
      local rc=$?
      warn "Hook [$priority] $name failed (rc=$rc)"
      hook_run "hook:fail" "$event" "$name" "$rc"
    fi
  done
}

hook_run_async() {
  local event="$1"; shift
  hook_run "$event" "$@" &
  log "Async hooks started for: $event (PID: $!)"
}

# ========== Built-in Hooks ==========
hook_install_builtin() {
  log "Installing built-in hooks..."

  # Boot hooks
  cat > "$HOOKS_DIR/boot:pre/00_mount_persist" << 'EOF'
#!/bin/bash
# Mount persistence overlay
PERSIST="/mnt/persist"
if [[ -f /persist.img ]]; then
  mkdir -p "$PERSIST"
  mount /persist.img "$PERSIST" 2>/dev/null || true
  mkdir -p "$PERSIST/upper" "$PERSIST/work"
  mount -t overlay overlay -o lowerdir=/,upperdir="$PERSIST/upper",workdir="$PERSIST/work" /mnt/root 2>/dev/null
  mount --bind /mnt/root / 2>/dev/null || true
fi
EOF
  chmod +x "$HOOKS_DIR/boot:pre/00_mount_persist"

  cat > "$HOOKS_DIR/boot:post/10_sysctl" << 'EOF'
#!/bin/bash
# Apply sysctl settings
[[ -f /etc/sysctl.d/99-tajados.conf ]] && sysctl -p /etc/sysctl.d/99-tajados.conf >/dev/null 2>&1
EOF
  chmod +x "$HOOKS_DIR/boot:post/10_sysctl"

  cat > "$HOOKS_DIR/boot:post/20_services" << 'EOF'
#!/bin/bash
# Start enabled TajaOS services
for svc in /usr/local/lib/tajados/services/enabled/*.service; do
  [[ -f "$svc" ]] || continue
  name=$(basename "$svc" .service)
  systemctl start "$name" 2>/dev/null || true
done
EOF
  chmod +x "$HOOKS_DIR/boot:post/20_services"

  # Shutdown hooks
  cat > "$HOOKS_DIR/shutdown:pre/00_save_state" << 'EOF'
#!/bin/bash
# Save runtime state
mkdir -p /var/lib/tajados/runtime
systemctl list-units --type=service --state=active --no-legend | awk '{print $1}' > /var/lib/tajados/runtime/active_services
EOF
  chmod +x "$HOOKS_DIR/shutdown:pre/00_save_state"

  cat > "$HOOKS_DIR/shutdown:post/00_unmount_persist" << 'EOF'
#!/bin/bash
# Sync and unmount persistence
sync
umount /mnt/root 2>/dev/null || true
umount /mnt/persist 2>/dev/null || true
EOF
  chmod +x "$HOOKS_DIR/shutdown:post/00_unmount_persist"

  # Network hooks
  cat > "$HOOKS_DIR/network:up/10_dns" << 'EOF'
#!/bin/bash
# Update DNS from config
DNS=$(tajados config get net.dns 2>/dev/null || echo "")
[[ -n "$DNS" ]] && echo "nameserver $DNS" > /etc/resolv.conf
EOF
  chmod +x "$HOOKS_DIR/network:up/10_dns"

  # Config change hook
  cat > "$HOOKS_DIR/config:change/10_reload" << 'EOF'
#!/bin/bash
# Reload affected services on config change
case "$2" in
  net.*) systemctl reload network-manager 2>/dev/null || true ;;
  sys.*) sysctl -p /etc/sysctl.d/99-tajados.conf 2>/dev/null || true ;;
  sec.*) tajainit restart tajados-firewall 2>/dev/null || true ;;
esac
EOF
  chmod +x "$HOOKS_DIR/config:change/10_reload"

  # Package hooks
  cat > "$HOOKS_DIR/pkg:install/10_rebuild_initramfs" << 'EOF'
#!/bin/bash
# Rebuild initramfs if kernel package installed
if [[ "$2" == linux-image-* ]]; then
  update-initramfs -u -k all
fi
EOF
  chmod +x "$HOOKS_DIR/pkg:install/10_rebuild_initramfs"

  ok "Built-in hooks installed"
}

# ========== Trigger System ==========
trigger_create() {
  local name="$1" condition="$2" event="$3"
  mkdir -p "$TAJADOS_DIR/triggers"
  cat > "$TAJADOS_DIR/triggers/$name.trigger" << TRG
[Trigger]
Name=$name
Condition=$condition
Event=$event
Enabled=true
TRG
  ok "Trigger created: $name"
}

trigger_enable() {
  local name="$1"
  sed -i 's/^Enabled=.*/Enabled=true/' "$TAJADOS_DIR/triggers/$name.trigger"
}

trigger_disable() {
  local name="$1"
  sed -i 's/^Enabled=.*/Enabled=false/' "$TAJADOS_DIR/triggers/$name.trigger"
}

trigger_list() {
  for f in "$TAJADOS_DIR/triggers"/*.trigger; do
    [[ -f "$f" ]] || continue
    echo "=== $(basename "$f" .trigger) ==="
    cat "$f"
  done
}

trigger_eval() {
  local name="$1"
  local f="$TAJADOS_DIR/triggers/$name.trigger"
  [[ -f "$f" ]] || return 1
  local enabled condition event
  enabled=$(grep '^Enabled=' "$f" | cut -d= -f2)
  [[ "$enabled" == "true" ]] || return 0
  condition=$(grep '^Condition=' "$f" | cut -d= -f2-)
  event=$(grep '^Event=' "$f" | cut -d= -f2-)
  eval "$condition" && hook_run "$event" "$name"
}

# ========== Daemon ==========
daemon_start() {
  log "Starting hook daemon..."
  # Monitor systemd events
  journalctl -f -o cat -u "*" | while read -r line; do
    if echo "$line" | grep -q "Started "; then
      local svc=$(echo "$line" | sed -n 's/.*Started \(.*\)\./\1/p')
      hook_run_async "service:start" "$svc"
    elif echo "$line" | grep -q "Stopped "; then
      local svc=$(echo "$line" | sed -n 's/.*Stopped \(.*\)\./\1/p')
      hook_run_async "service:stop" "$svc"
    elif echo "$line" | grep -q "Failed "; then
      local svc=$(echo "$line" | sed -n 's/.*Failed \(.*\)\./\1/p')
      hook_run_async "service:fail" "$svc"
    fi
  done
}

# ========== CLI ==========
usage() {
  cat << USAGE
Usage: tajahook <command> [args]

Hooks:
  tajahook register <event> <script> [priority]  Register hook (priority 0-99)
  tajahook unregister <event> <script>           Unregister hook
  tajahook list [event]                          List hooks
  tajahook run <event> [args...]                 Run hooks for event
  tajahook run-async <event> [args...]           Run hooks async
  tajahook install-builtin                       Install built-in hooks

Triggers:
  tajahook trigger create <name> <condition> <event>  Create trigger
  tajahook trigger enable <name>                     Enable trigger
  tajahook trigger disable <name>                    Disable trigger
  tajahook trigger list                              List triggers
  tajahook trigger eval <name>                       Evaluate trigger

Daemon:
  tajahook daemon                                   Start hook daemon

USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    register) hook_register "$@" ;;
    unregister) hook_unregister "$@" ;;
    list) hook_list "$@" ;;
    run) hook_run "$@" ;;
    run-async) hook_run_async "$@" ;;
    install-builtin) hook_install_builtin ;;
    trigger)
      local sub="$1"; shift
      case "$sub" in
        create) trigger_create "$@" ;;
        enable) trigger_enable "$@" ;;
        disable) trigger_disable "$@" ;;
        list) trigger_list ;;
        eval) trigger_eval "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    daemon) daemon_start ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"