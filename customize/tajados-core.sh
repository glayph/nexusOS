#!/bin/bash
# ============================================================
#  TajaOS Core — Configuration & State Management
#  Persistent config store, schema validation, profiles
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
CONFIG_DIR="/etc/tajados"
STATE_DIR="/var/lib/tajados"
CACHE_DIR="/var/cache/tajados"

mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR" "$TAJADOS_DIR"/{core,net,shell,dev,productivity,system,recovery,network,container,ai,security,media,build}

# Colors
C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[TajaOS]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

# ========== Config Schema ==========
declare -A CONFIG_SCHEMA=(
  # Core
  ["core.hostname"]="string"
  ["core.timezone"]="string"
  ["core.locale"]="string"
  ["core.boot_mode"]="enum:cli|gui|auto"
  ["core.auto_login"]="bool"
  # Network
  ["net.wifi_ssid"]="string"
  ["net.wifi_password"]="secret"
  ["net.ethernet_dhcp"]="bool"
  ["net.dns_servers"]="list"
  ["net.vpn_config"]="file"
  ["net.proxy"]="string"
  # Shell
  ["shell.theme"]="enum:default|green|amber|mono"
  ["shell.prompt_style"]="enum:minimal|full|git"
  ["shell.history_size"]="int"
  ["shell.completion"]="bool"
  # System
  ["sys.swappiness"]="int"
  ["sys.cpu_governor"]="enum:performance|powersave|ondemand"
  ["sys.kernel_params"]="string"
  ["sys.services_enabled"]="list"
  ["sys.services_disabled"]="list"
  # Security
  ["sec.firewall_enabled"]="bool"
  ["sec.ssh_port"]="int"
  ["sec.ssh_key_only"]="bool"
  ["sec.audit_enabled"]="bool"
  ["sec.vault_path"]="string"
  # AI
  ["ai.model_path"]="string"
  ["ai.offline_mode"]="bool"
  ["ai.context_window"]="int"
)

# ========== Config Functions ==========
config_get() {
  local key="$1"
  local file="$CONFIG_DIR/${key%%.*}.conf"
  [[ -f "$file" ]] || return 1
  grep -E "^${key#*.}=" "$file" | cut -d'=' -f2- | head -1
}

config_set() {
  local key="$1" value="$2"
  local section="${key%%.*}"
  local name="${key#*.}"
  local file="$CONFIG_DIR/${section}.conf"
  mkdir -p "$CONFIG_DIR"
  touch "$file"
  if grep -q "^${name}=" "$file"; then
    sed -i "s|^${name}=.*|${name}=${value}|" "$file"
  else
    echo "${name}=${value}" >> "$file"
  fi
  ok "Config set: $key=$value"
}

config_del() {
  local key="$1"
  local section="${key%%.*}"
  local name="${key#*.}"
  local file="$CONFIG_DIR/${section}.conf"
  [[ -f "$file" ]] && sed -i "/^${name}=/d" "$file"
}

config_list() {
  local section="${1:-}"
  if [[ -n "$section" ]]; then
    [[ -f "$CONFIG_DIR/${section}.conf" ]] && cat "$CONFIG_DIR/${section}.conf"
  else
    for f in "$CONFIG_DIR"/*.conf; do
      [[ -f "$f" ]] && echo "=== $(basename "$f" .conf) ===" && cat "$f"
    done
  fi
}

config_validate() {
  local key="$1" value="$2"
  local type="${CONFIG_SCHEMA[$key]:-string}"
  case "$type" in
    bool) [[ "$value" =~ ^(true|false|yes|no|1|0)$ ]] || return 1 ;;
    int)  [[ "$value" =~ ^[0-9]+$ ]] || return 1 ;;
    enum:*) local vals="${type#enum:}"; [[ " $vals " == *" $value "* ]] || return 1 ;;
    list) true ;;
    file) [[ -f "$value" ]] || return 1 ;;
    secret) true ;;
    *) true ;;
  esac
}

# ========== Profile Management ==========
profile_save() {
  local name="$1"
  [[ -z "$name" ]] && die "Profile name required"
  local profile_dir="$STATE_DIR/profiles/$name"
  mkdir -p "$profile_dir"
  cp -r "$CONFIG_DIR"/* "$profile_dir/" 2>/dev/null || true
  cat > "$profile_dir/meta.json" << META
{
  "name": "$name",
  "created": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "kernel": "$(uname -r)"
}
META
  ok "Profile '$name' saved to $profile_dir"
}

profile_load() {
  local name="$1"
  [[ -z "$name" ]] && die "Profile name required"
  local profile_dir="$STATE_DIR/profiles/$name"
  [[ -d "$profile_dir" ]] || die "Profile '$name' not found"
  cp -r "$profile_dir"/*.conf "$CONFIG_DIR/" 2>/dev/null || true
  ok "Profile '$name' loaded"
}

profile_list() {
  for d in "$STATE_DIR"/profiles/*/; do
    [[ -d "$d" ]] && basename "$d"
  done
}

profile_delete() {
  local name="$1"
  rm -rf "$STATE_DIR/profiles/$name"
  ok "Profile '$name' deleted"
}

# ========== State Persistence ==========
state_set() {
  local key="$1" value="$2"
  echo "$value" > "$STATE_DIR/$key"
}

state_get() {
  local key="$1"
  [[ -f "$STATE_DIR/$key" ]] && cat "$STATE_DIR/$key"
}

state_del() {
  rm -f "$STATE_DIR/$1"
}

# ========== Cache ==========
cache_set() {
  local key="$1" value="$2" ttl="${3:-3600}"
  echo "$value" > "$CACHE_DIR/$key"
  echo "$(($(date +%s) + ttl))" > "$CACHE_DIR/$key.ttl"
}

cache_get() {
  local key="$1"
  [[ -f "$CACHE_DIR/$key" ]] || return 1
  local ttl_file="$CACHE_DIR/$key.ttl"
  [[ -f "$ttl_file" ]] && (( $(cat "$ttl_file") < $(date +%s) )) && { rm -f "$CACHE_DIR/$key" "$ttl_file"; return 1; }
  cat "$CACHE_DIR/$key"
}

cache_clear() {
  rm -rf "$CACHE_DIR"/*
}

# ========== Hooks ==========
hook_register() {
  local event="$1" script="$2"
  mkdir -p "$TAJADOS_DIR/hooks/$event"
  ln -sf "$script" "$TAJADOS_DIR/hooks/$event/$(basename "$script")"
}

hook_run() {
  local event="$1"
  for hook in "$TAJADOS_DIR/hooks/$event"/*; do
    [[ -x "$hook" ]] && "$hook" "$@"
  done
}

# ========== Init ==========
init_system() {
  log "Initializing TajaOS Core..."
  # Load kernel params from config
  local params
  params=$(config_get "sys.kernel_params")
  [[ -n "$params" ]] && echo "$params" > /etc/sysctl.d/99-tajados.conf && sysctl -p /etc/sysctl.d/99-tajados.conf >/dev/null 2>&1
  # Set hostname
  local hn
  hn=$(config_get "core.hostname")
  [[ -n "$hn" ]] && hostnamectl set-hostname "$hn"
  # Set timezone
  local tz
  tz=$(config_get "core.timezone")
  [[ -n "$tz" ]] && timedatectl set-timezone "$tz"
  # CPU governor
  local gov
  gov=$(config_get "sys.cpu_governor")
  [[ -n "$gov" ]] && echo "$gov" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
  # Swappiness
  local swap
  swap=$(config_get "sys.swappiness")
  [[ -n "$swap" ]] && echo "$swap" > /proc/sys/vm/swappiness
  hook_run "init" "start"
  ok "TajaOS Core initialized"
}

# ========== CLI ==========
usage() {
  cat << USAGE
Usage: tajados <command> [args]

Config:
  tajados config get <key>              Get config value
  tajados config set <key> <value>      Set config value
  tajados config del <key>              Delete config key
  tajados config list [section]         List all config
  tajados config validate <key> <val>   Validate config value

Profiles:
  tajados profile save <name>           Save current config as profile
  tajados profile load <name>           Load profile
  tajados profile list                  List profiles
  tajados profile delete <name>         Delete profile

State:
  tajados state set <key> <value>       Set persistent state
  tajados state get <key>               Get persistent state
  tajados state del <key>               Delete state

Cache:
  tajados cache set <key> <val> [ttl]   Set cache with TTL
  tajados cache get <key>               Get cache
  tajados cache clear                   Clear all cache

Hooks:
  tajados hook register <event> <script> Register hook
  tajados hook run <event> [args...]    Run hooks for event

System:
  tajados init                          Initialize system from config
  tajados doctor                        System health check

USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    config)
      local sub="$1"; shift
      case "$sub" in
        get) config_get "$@" ;;
        set) config_set "$@" ;;
        del) config_del "$@" ;;
        list) config_list "$@" ;;
        validate) config_validate "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    profile)
      local sub="$1"; shift
      case "$sub" in
        save) profile_save "$@" ;;
        load) profile_load "$@" ;;
        list) profile_list ;;
        delete) profile_delete "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    state)
      local sub="$1"; shift
      case "$sub" in
        set) state_set "$@" ;;
        get) state_get "$@" ;;
        del) state_del "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    cache)
      local sub="$1"; shift
      case "$sub" in
        set) cache_set "$@" ;;
        get) cache_get "$@" ;;
        clear) cache_clear ;;
        *) usage; exit 1 ;;
      esac
      ;;
    hook)
      local sub="$1"; shift
      case "$sub" in
        register) hook_register "$@" ;;
        run) hook_run "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    init) init_system ;;
    doctor)
      log "Running system doctor..."
      echo "=== System Info ==="
      uname -a
      echo "=== Disk ==="; df -h /
      echo "=== Memory ==="; free -h
      echo "=== CPU ==="; lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core'
      echo "=== Network ==="; ip -br addr
      echo "=== Services ==="; systemctl list-units --failed --no-legend
      echo "=== Temps ==="; sensors 2>/dev/null || echo "lm-sensors not installed"
      ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"