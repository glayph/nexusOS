#!/bin/bash
# ============================================================
#  TajaShell — Modern TUI Shell
#  Keyboard navigation, completion, history, split panes
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
CONFIG_DIR="/etc/tajados"
STATE_DIR="/var/lib/tajados"

mkdir -p "$STATE_DIR/shell" "$STATE_DIR/shell/history" "$STATE_DIR/shell/sessions"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[TajaShell]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

# ========== Configuration ==========
SHELL_THEME="${SHELL_THEME:-default}"
SHELL_HISTORY_SIZE="${SHELL_HISTORY_SIZE:-10000}"
SHELL_COMPLETION="${SHELL_COMPLETION:-true}"
SHELL_SYNTAX_HIGHLIGHT="${SHELL_SYNTAX_HIGHLIGHT:-true}"
SHELL_SPLIT_PANES="${SHELL_SPLIT_PANES:-false}"

# ========== TUI Framework ==========
tui_init() {
  stty -echo -icanon time 0 min 0 2>/dev/null
  tput smcup 2>/dev/null
  tput civis 2>/dev/null
  clear
}

tui_cleanup() {
  stty echo icanon 2>/dev/null
  tput rmcup 2>/dev/null
  tput cnorm 2>/dev/null
}
trap tui_cleanup EXIT

tui_clear() { clear; }
tui_home() { tput cup 0 0 2>/dev/null; }
tui_goto() { tput cup "$1" "$2" 2>/dev/null; }
tui_lines() { tput lines 2>/dev/null || echo 24; }
tui_cols() { tput cols 2>/dev/null || echo 80; }

tui_draw_box() {
  local x="$1" y="$2" w="$3" h="$4" title="$5"
  tui_goto "$y" "$x"
  printf "┌%*s┐" $((w-2)) | tr ' ' '─'
  for ((i=1; i<h-1; i++)); do
    tui_goto $((y+i)) "$x"
    printf "│%*s│" $((w-2))
  done
  tui_goto $((y+h-1)) "$x"
  printf "└%*s┘" $((w-2)) | tr ' ' '─'
  [[ -n "$title" ]] && { tui_goto "$y" $((x+2)); printf " %s " "$title"; }
}

tui_draw_menu() {
  local x="$1" y="$2" w="$3" selected="$4" title="$5"; shift 5
  local items=("$@")
  tui_draw_box "$x" "$y" "$w" $((${#items[@]}+3)) "$title"
  for i in "${!items[@]}"; do
    tui_goto $((y+i+1)) $((x+2))
    if [[ $i -eq $selected ]]; then
      printf "\033[7m %-*s \033[0m" $((w-4)) "${items[i]}"
    else
      printf " %-*s " $((w-4)) "${items[i]}"
    fi
  done
}

tui_draw_list() {
  local x="$1" y="$2" w="$3" h="$4" selected="$5" offset="$6" title="$7"; shift 7
  local items=("$@")
  tui_draw_box "$x" "$y" "$w" "$h" "$title"
  local max=$((h-3))
  for ((i=0; i<max && i+offset < ${#items[@]}; i++)); do
    tui_goto $((y+i+1)) $((x+2))
    local idx=$((i+offset))
    if [[ $idx -eq $selected ]]; then
      printf "\033[7m %-*s \033[0m" $((w-4)) "${items[idx]}"
    else
      printf " %-*s " $((w-4)) "${items[idx]}"
    fi
  done
}

tui_input() {
  local x="$1" y="$2" prompt="$3" default="$4"
  tui_goto "$y" "$x"
  printf "%s: " "$prompt"
  local input="$default"
  echo -n "$input"
  local cursor=${#input}
  while true; do
    tui_goto "$y" $((x+${#prompt}+2+cursor))
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r') echo; break ;;
      $'\177'|$'\b') [[ $cursor -gt 0 ]] && { input="${input:0:cursor-1}${input:cursor}"; cursor=$((cursor-1)); tui_goto "$y" $((x+${#prompt}+2)); printf "%-*s" $((cursor+1)) "$input"; } ;;
      $'\t') ;; # handled by completion
      $'\e')
        read -rsn2 -t 0.01 key2
        case "$key2" in
          '[D') [[ $cursor -gt 0 ]] && cursor=$((cursor-1)) ;;
          '[C') [[ $cursor -lt ${#input} ]] && cursor=$((cursor+1)) ;;
          '[H') cursor=0 ;;
          '[F') cursor=${#input} ;;
        esac
        ;;
      *) input="${input:0:cursor}${key}${input:cursor}"; cursor=$((cursor+1)) ;;
    esac
    tui_goto "$y" $((x+${#prompt}+2))
    printf "%-*s" $((cursor+1)) "$input"
  done
  echo "$input"
}

tui_confirm() {
  local x="$1" y="$2" msg="$3"
  tui_goto "$y" "$x"
  printf "%s [y/N]: " "$msg"
  read -rsn1 key
  [[ "$key" =~ [yY] ]]
}

# ========== History ==========
HISTORY_FILE="$STATE_DIR/shell/history/$(date +%Y%m).log"
touch "$HISTORY_FILE"

history_add() {
  echo "$(date -Iseconds) $(pwd) $*" >> "$HISTORY_FILE"
  tail -n "$SHELL_HISTORY_SIZE" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
}

history_search() {
  local query="$1"
  grep -i "$query" "$HISTORY_FILE" | tail -20 | cut -d' ' -f3-
}

history_interactive() {
  local items=()
  mapfile -t items < <(tac "$HISTORY_FILE" | cut -d' ' -f3- | head -50)
  local selected=0 offset=0
  while true; do
    tui_clear
    tui_draw_list 2 2 $(($(tui_cols)-4)) $(($(tui_lines)-4)) "$selected" "$offset" "History (Enter=run, Esc=exit)" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r') echo "${items[selected]}"; return 0 ;;
      $'\e') return 1 ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)); [[ $selected -lt $offset ]] && offset=$((offset-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)); [[ $selected -ge $offset+$(($(tui_lines)-6)) ]] && offset=$((offset+1)) ;;
    esac
  done
}

# ========== Completion ==========
declare -A COMPLETIONS=(
  ["tajados"]="config profile state cache hook init doctor"
  ["tajados config"]="get set del list validate"
  ["tajados profile"]="save load list delete"
  ["tajados state"]="set get del"
  ["tajados cache"]="set get clear"
  ["tajados hook"]="register unregister list run run-async"
  ["tajanet"]="wifi eth dns vpn proxy diag speed ping trace ports fw tui"
  ["tajainit"]="list enable disable start stop restart status logs create boot-analyze boot-optimize health-report health-monitor deps tui"
  ["tajados-persist"]="create resize mount umount status overlay-mount overlay-umount snapshot-create snapshot-list snapshot-restore snapshot-delete backup-create backup-restore backup-list migrate config-persist config-restore autosnap-enable autosnap-disable"
  ["tajahook"]="register unregister list run run-async wait emit emit-async trigger-create trigger-list"
  ["tajapkg"]="install remove search update list info build clean"
  ["tajadev"]="container-run container-build container-list vm-create vm-start vm-stop vm-list image-build image-list"
  ["tajaai"]="model-run model-list prompt chat embed codegen"
  ["tajasec"]="vault-create vault-open vault-close vault-list audit-harden audit-check kernel-lock secureboot"
  ["tajamon"]="cpu mem disk net gpu temp battery processes services logs"
)

complete_cmd() {
  local cmd="$1" cur="$2"
  local comps="${COMPLETIONS[$cmd]:-}"
  for c in $comps; do
    [[ "$c" == "$cur"* ]] && echo "$c"
  done
}

# ========== Syntax Highlighting ==========
highlight_cmd() {
  local cmd="$1"
  if [[ "$SHELL_SYNTAX_HIGHLIGHT" == "true" ]]; then
    echo "$cmd" | sed -E \
      -e 's/\b(sudo|apt|systemctl|docker|kubectl|git|make|gcc|python3|node|npm)\b/\x1b[94m&\x1b[0m/g' \
      -e 's/\b(if|then|else|fi|for|while|do|done|case|esac|function)\b/\x1b[93m&\x1b[0m/g' \
      -e 's/("[^"]*"|'"'"'[^'"'"']*'"'"')/\x1b[92m&\x1b[0m/g' \
      -e 's/(#[^ ]*)/\x1b[90m&\x1b[0m/g' \
      -e 's/(\$\w+|\$\{[^}]+\})/\x1b[96m&\x1b[0m/g'
  else
    echo "$cmd"
  fi
}

# ========== Session Management ==========
session_save() {
  local name="${1:-$(date +%Y%m%d-%H%M%S)}"
  local session_dir="$STATE_DIR/shell/sessions/$name"
  mkdir -p "$session_dir"
  cp "$HISTORY_FILE" "$session_dir/history.log" 2>/dev/null || true
  cat > "$session_dir/meta.json" << META
{
  "name": "$name",
  "created": "$(date -Iseconds)",
  "pwd": "$(pwd)",
  "shell": "$SHELL",
  "theme": "$SHELL_THEME"
}
META
  ok "Session saved: $name"
}

session_load() {
  local name="$1"
  local session_dir="$STATE_DIR/shell/sessions/$name"
  [[ -d "$session_dir" ]] || die "Session not found: $name"
  cp "$session_dir/history.log" "$HISTORY_FILE" 2>/dev/null || true
  ok "Session loaded: $name"
}

session_list() {
  for d in "$STATE_DIR/shell/sessions"/*/; do
    [[ -d "$d" ]] || continue
    local name=$(basename "$d")
    local created=$(jq -r .created "$d/meta.json" 2>/dev/null || echo "unknown")
    echo "  $name  ($created)"
  done
}

session_delete() {
  rm -rf "$STATE_DIR/shell/sessions/$1"
  ok "Session deleted: $1"
}

# ========== Split Pane (using tmux) ==========
pane_split_h() { tmux split-window -h -c "$(pwd)" 2>/dev/null || warn "tmux not available"; }
pane_split_v() { tmux split-window -v -c "$(pwd)" 2>/dev/null || warn "tmux not available"; }
pane_resize() { tmux resize-pane -"$1" "$2" 2>/dev/null || true; }
pane_select() { tmux select-pane -"$1" 2>/dev/null || true; }

# ========== Prompt ==========
prompt_render() {
  local exit_code="${1:-0}"
  local git_branch=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git_branch=" $(git branch --show-current 2>/dev/null)"
  fi
  local prompt_char="$"
  [[ $EUID -eq 0 ]] && prompt_char="#"
  local color="96"
  case "$SHELL_THEME" in
    green) color="92" ;;
    amber) color="93" ;;
    mono) color="97" ;;
  esac
  PS1="\[\033[${color}m\]\u@\h\[\033[0m\]:\[\033[97m\]\w\[\033[0m\]\[\033[${color}m\]${git_branch}\[\033[0m\]${prompt_char} "
}

# ========== Key Bindings ==========
bind_keys() {
  bind -x '"\C-r": history_interactive' 2>/dev/null || true
  bind -x '"\C-t": tui_confirm "Run tajados?" && tajados' 2>/dev/null || true
  bind -x '"\C-p": pane_split_h' 2>/dev/null || true
  bind -x '"\C-v": pane_split_v' 2>/dev/null || true
}

# ========== Main TUI Menu ==========
tui_main_menu() {
  local items=(
    "1. Tajados Config"
    "2. Tajados Profiles"
    "3. Tajados Network (TajaNet)"
    "4. Tajados Init (Services)"
    "5. Tajados Persistence"
    "6. Tajados Hooks"
    "7. TajaPkg (Packages)"
    "8. TajaDev (Containers/VMs)"
    "9. TajaAI (Local LLM)"
    "10. TajaSec (Security)"
    "11. Tajamon (Monitoring)"
    "12. Session Manager"
    "13. Settings"
    "14. Exit"
  )
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 50 "$selected" "TajaShell" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) tajados_config_tui ;;
          1) tajados_profile_tui ;;
          2) tajanet_tui ;;
          3) tajanet ;;
          4) tajados_persist_tui ;;
          5) tajahook_tui ;;
          6) tajapkg_tui ;;
          7) tajadev_tui ;;
          8) tajaai_tui ;;
          9) tajasec_tui ;;
          10) tajamon_tui ;;
          11) session_tui ;;
          12) settings_tui ;;
          13) break ;;
        esac
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') break ;;
    esac
  done
}

# ========== Sub-menus ==========
tajados_config_tui() {
  local sections=("core" "net" "shell" "sys" "sec" "ai")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 50 "$selected" "Config Sections" "${sections[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r') tajados_config_section_tui "${sections[selected]}" ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#sections[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

tajados_config_section_tui() {
  local section="$1"
  local items=()
  while IFS='=' read -r k v; do
    [[ -n "$k" ]] && items+=("$k=$v")
  done < <(tajados config list "$section" 2>/dev/null)
  items+=("[Add new]")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 60 "$selected" "Config: $section" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        if [[ $selected -eq $((${#items[@]}-1)) ]]; then
          local key=$(tui_input 10 10 "Key" "")
          local val=$(tui_input 10 12 "Value" "")
          tajados config set "$section.$key" "$val"
          tajados_config_section_tui "$section"
          return
        else
          local k=$(echo "${items[selected]}" | cut -d= -f1)
          local v=$(echo "${items[selected]}" | cut -d= -f2-)
          local new=$(tui_input 10 10 "New value for $k" "$v")
          tajados config set "$section.$k" "$new"
          tajados_config_section_tui "$section"
          return
        fi
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

tajados_profile_tui() {
  local items=("Save Profile" "Load Profile" "List Profiles" "Delete Profile")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 40 "$selected" "Profiles" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) local name=$(tui_input 10 10 "Profile name" ""); tajados profile save "$name" ;;
          1) local name=$(tui_input 10 10 "Profile name" ""); tajados profile load "$name" ;;
          2) tajados profile list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          3) local name=$(tui_input 10 10 "Profile name" ""); tajados profile delete "$name" ;;
        esac
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

tajanet_tui() {
  local items=("WiFi Scan" "WiFi Connect" "WiFi Disconnect" "Saved Networks" "Ethernet Status" "DNS Settings" "VPN Manager" "Proxy Settings" "Speed Test" "Diagnostics")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 40 "$selected" "TajaNet" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) tajanet wifi scan | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          1) local ssid=$(tui_input 10 10 "SSID" ""); local pw=$(tui_input 10 12 "Password" ""); tajanet wifi connect "$ssid" "$pw" ;;
          2) tajanet wifi disconnect ;;
          3) tajanet wifi list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          4) tajanet eth status | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          5) local dns=$(tui_input 10 10 "DNS servers" "1.1.1.1 8.8.8.8"); tajanet dns set "$dns" ;;
          6) echo "VPN Manager"; read -rp "Press Enter..." ;;
          7) local host=$(tui_input 10 10 "Proxy host" ""); local port=$(tui_input 10 12 "Port" ""); tajanet proxy set http "$host" "$port" ;;
          8) tajanet speed | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          9) tajanet diag | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
        esac
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

tajanet() {
  local items=("List Services" "Start Service" "Stop Service" "Restart Service" "Enable Service" "Disable Service" "Service Status" "Failed Services")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 40 "$selected" "TajaInit" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) tajainit list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          1) local s=$(tui_input 10 10 "Service name" ""); tajainit start "$s" ;;
          2) local s=$(tui_input 10 10 "Service name" ""); tajainit stop "$s" ;;
          3) local s=$(tui_input 10 10 "Service name" ""); tajainit restart "$s" ;;
          4) local s=$(tui_input 10 10 "Service name" ""); tajainit enable "$s" ;;
          5) local s=$(tui_input 10 10 "Service name" ""); tajainit disable "$s" ;;
          6) local s=$(tui_input 10 10 "Service name" ""); tajainit status "$s" | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          7) systemctl list-units --failed --no-legend | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
        esac
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

tajados_persist_tui() {
  local items=("Create Persistence" "Mount/Unmount" "Status" "Create Snapshot" "List Snapshots" "Restore Snapshot" "Backup Create" "Backup Restore" "Config Persist/Restore" "Auto-snapshot")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 40 "$selected" "Persistence" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) local sz=$(tui_input 10 10 "Size (MB)" "2048"); tajados-persist create "$sz" ;;
          1) tajados-persist status; read -rp "Press Enter..." ;;
          2) tajados-persist status | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          3) local name=$(tui_input 10 10 "Name (optional)" ""); tajados-persist snapshot-create "$name" ;;
          4) tajados-persist snapshot-list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          5) local name=$(tui_input 10 10 "Snapshot name" ""); tajados-persist snapshot-restore "$name" ;;
          6) tajados-persist backup-create ;;
          7) local src=$(tui_input 10 10 "Backup file" ""); tajados-persist backup-restore "$src" ;;
          8) echo "1) Persist  2) Restore"; read -rp "Choice: " c; [[ $c == 1 ]] && tajados-persist config-persist || tajados-persist config-restore ;;
          9) tajados-persist autosnap-enable ;;
        esac
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

tajahook_tui() {
  local items=("List Hooks" "Register Hook" "Run Hook" "Triggers")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 40 "$selected" "Hooks" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) tajados-hook list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          1) local ev=$(tui_input 10 10 "Event" ""); local scr=$(tui_input 10 12 "Script" ""); tajados-hook register "$ev" "$scr" ;;
          2) local ev=$(tui_input 10 10 "Event" ""); tajados-hook run "$ev" ;;
          3) tajados-hook trigger-list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
        esac
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

tajapkg_tui() {
  echo "TajaPkg TUI - coming soon"
  read -rp "Press Enter..."
}

tajadev_tui() {
  echo "TajaDev TUI - coming soon"
  read -rp "Press Enter..."
}

tajaai_tui() {
  echo "TajaAI TUI - coming soon"
  read -rp "Press Enter..."
}

tajasec_tui() {
  echo "TajaSec TUI - coming soon"
  read -rp "Press Enter..."
}

tajamon_tui() {
  echo "Tajamon TUI - coming soon"
  read -rp "Press Enter..."
}

session_tui() {
  local items=("Save Session" "Load Session" "List Sessions" "Delete Session")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 40 "$selected" "Sessions" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) local name=$(tui_input 10 10 "Name" ""); session_save "$name" ;;
          1) local name=$(tui_input 10 10 "Name" ""); session_load "$name" ;;
          2) session_list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          3) local name=$(tui_input 10 10 "Name" ""); session_delete "$name" ;;
        esac
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

settings_tui() {
  local items=("Theme: $SHELL_THEME" "History Size: $SHELL_HISTORY_SIZE" "Completion: $SHELL_COMPLETION" "Syntax Highlight: $SHELL_SYNTAX_HIGHLIGHT" "Split Panes: $SHELL_SPLIT_PANES")
  local selected=0
  while true; do
    tui_clear
    tui_draw_menu 5 5 50 "$selected" "Settings" "${items[@]}"
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) SHELL_THEME=$(tui_input 10 10 "Theme (default/green/amber/mono)" "$SHELL_THEME") ;;
          1) SHELL_HISTORY_SIZE=$(tui_input 10 10 "History size" "$SHELL_HISTORY_SIZE") ;;
          2) SHELL_COMPLETION=$(tui_input 10 10 "Completion (true/false)" "$SHELL_COMPLETION") ;;
          3) SHELL_SYNTAX_HIGHLIGHT=$(tui_input 10 10 "Syntax highlight (true/false)" "$SHELL_SYNTAX_HIGHLIGHT") ;;
          4) SHELL_SPLIT_PANES=$(tui_input 10 10 "Split panes (true/false)" "$SHELL_SPLIT_PANES") ;;
        esac
        items=("Theme: $SHELL_THEME" "History Size: $SHELL_HISTORY_SIZE" "Completion: $SHELL_COMPLETION" "Syntax Highlight: $SHELL_SYNTAX_HIGHLIGHT" "Split Panes: $SHELL_SPLIT_PANES")
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

# ========== Entry Point ==========
main() {
  case "${1:-}" in
    menu) tui_main_menu ;;
    history) history_interactive ;;
    session-save) session_save "${2:-}" ;;
    session-load) session_load "${2:-}" ;;
    session-list) session_list ;;
    session-del) session_delete "${2:-}" ;;
    prompt) prompt_render "${2:-0}" ;;
    bind) bind_keys ;;
    complete) complete_cmd "${2:-}" "${3:-}" ;;
    highlight) highlight_cmd "${2:-}" ;;
    *) echo "Usage: tajshell {menu|history|session-save|session-load|session-list|session-del|prompt|bind|complete|highlight}" ;;
  esac
}

main "$@"