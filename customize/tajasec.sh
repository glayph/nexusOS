#!/bin/bash
# ============================================================
#  TajaSec — Security & Hardening Toolkit
#  Encrypted vault, firewall, audit, kernel hardening, SSH
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
CONFIG_DIR="/etc/tajados"
STATE_DIR="/var/lib/tajados"
VAULT_DIR="$STATE_DIR/vault"
AUDIT_LOG="$STATE_DIR/audit.log"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[TajaSec]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

mkdir -p "$VAULT_DIR" "$(dirname "$AUDIT_LOG")"

# ========== Audit ==========
audit_log() {
  local action="$1" detail="${2:-}"
  echo "$(date -Iseconds) | $USER | $action | $detail" >> "$AUDIT_LOG"
}

audit_view() {
  local lines="${1:-50}"
  tail -n "$lines" "$AUDIT_LOG"
}

audit_search() {
  grep -i "$1" "$AUDIT_LOG" | tail -50
}

audit_stats() {
  echo "Total entries: $(wc -l < "$AUDIT_LOG")"
  echo "Actions:"
  cut -d'|' -f3 "$AUDIT_LOG" | sort | uniq -c | sort -rn
}

# ========== Encrypted Vault ==========
vault_create() {
  local name="$1" size="${2:-100}"
  local img="$VAULT_DIR/$name.img"
  [[ -f "$img" ]] && die "Vault exists: $name"
  dd if=/dev/zero of="$img" bs=1M count="$size" status=progress
  local mnt="$VAULT_DIR/$name"
  mkdir -p "$mnt"
  if command -v cryptsetup &>/dev/null; then
    cryptsetup luksFormat "$img"
    cryptsetup open "$img" "vault-$name"
    mkfs.ext4 "/dev/mapper/vault-$name"
    mount "/dev/mapper/vault-$name" "$mnt"
  else
    mkfs.ext4 -F "$img"
    mount -o loop "$img" "$mnt"
  fi
  ok "Vault '$name' created ($size MB) at $mnt"
}

vault_open() {
  local name="$1" pass="${2:-}"
  local img="$VAULT_DIR/$name.img"
  local mnt="$VAULT_DIR/$name"
  [[ -f "$img" ]] || die "Vault not found: $name"
  mkdir -p "$mnt"
  if command -v cryptsetup &>/dev/null; then
    [[ -z "$pass" ]] && read -rsp "Password: " pass && echo
    echo "$pass" | cryptsetup open --key-file=- "$img" "vault-$name" 2>/dev/null
    mount "/dev/mapper/vault-$name" "$mnt"
  else
    mount -o loop "$img" "$mnt"
  fi
  ok "Vault '$name' opened at $mnt"
}

vault_close() {
  local name="$1"
  local mnt="$VAULT_DIR/$name"
  umount "$mnt" 2>/dev/null
  cryptsetup close "vault-$name" 2>/dev/null || true
  ok "Vault '$name' closed"
}

vault_list() {
  for f in "$VAULT_DIR"/*.img; do
    [[ -f "$f" ]] || continue
    local name=$(basename "$f" .img)
    local size=$(du -h "$f" | cut -f1)
    local status="closed"
    mountpoint -q "$VAULT_DIR/$name" && status="open"
    echo "$name ($size) - $status"
  done
}

# ========== System Hardening ==========
harden_sysctl() {
  log "Applying sysctl hardening..."
  cat >> /etc/sysctl.d/99-tajados-hardening.conf << 'SYSCTL'
# Kernel hardening
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.printk=3 3 3 3
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_enable=0
kernel.kexec_load_disabled=1
kernel.sysrq=0
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.tcp_rfc1337=1
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.suid_dumpable=0
vm.mmap_min_addr=65536
SYSCTL
  sysctl -p /etc/sysctl.d/99-tajados-hardening.conf
  ok "Sysctl hardening applied"
}

harden_ssh() {
  local sshd_config="/etc/ssh/sshd_config"
  [[ -f "$sshd_config" ]] || { warn "SSH not installed"; return; }
  cp "$sshd_config" "${sshd_config}.bak"
  cat >> "$sshd_config" << 'SSH'
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
Protocol 2
SSH
  systemctl restart sshd
  ok "SSH hardened"
}

harden_users() {
  # Lock unnecessary accounts
  for user in games gnats irc list news uucp; do
    usermod -L "$user" 2>/dev/null || true
  done
  ok "Unused accounts locked"
}

harden_permissions() {
  chmod 700 /root
  chmod 750 /etc/sudoers.d
  chmod 644 /etc/passwd /etc/group
  chmod 640 /etc/shadow /etc/gshadow
  ok "Permissions hardened"
}

harden_apply() {
  harden_sysctl
  harden_ssh
  harden_users
  harden_permissions
  ok "All hardening applied"
  audit_log "HARDEN" "Full system hardening applied"
}

harden_check() {
  local score=0 total=25
  echo "=== Security Audit ==="
  # Check sysctl
  [[ $(sysctl -n kernel.kptr_restrict 2>/dev/null) -ge 2 ]] && { echo "✓ kptr_restrict"; ((score++)); } || { echo "✗ kptr_restrict"; }
  [[ $(sysctl -n kernel.dmesg_restrict 2>/dev/null) -eq 1 ]] && { echo "✓ dmesg_restrict"; ((score++)); } || { echo "✗ dmesg_restrict"; }
  [[ $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null) -eq 1 ]] && { echo "✓ tcp_syncookies"; ((score++)); } || { echo "✗ tcp_syncookies"; }
  [[ $(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null) -eq 1 ]] && { echo "✓ rp_filter"; ((score++)); } || { echo "✗ rp_filter"; }
  [[ $(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null) -eq 0 ]] && { echo "✓ no_redirects"; ((score++)); } || { echo "✗ no_redirects"; }
  [[ $(sysctl -n fs.suid_dumpable 2>/dev/null) -eq 0 ]] && { echo "✓ no_dump"; ((score++)); } || { echo "✗ no_dump"; }
  # Check services
  systemctl is-active --quiet sshd && { echo "✓ sshd"; ((score++)); } || true
  systemctl is-active --quiet nftables && { echo "✓ nftables"; ((score++)); } || { echo "✗ nftables"; }
  # Check permissions
  [[ "$(stat -c "%a" /root 2>/dev/null)" =~ 700 ]] && { echo "✓ /root perms"; ((score++)); } || { echo "✗ /root perms"; }
  [[ "$(stat -c "%a" /etc/shadow 2>/dev/null)" =~ 640|600 ]] && { echo "✓ shadow perms"; ((score++)); } || { echo "✗ shadow perms"; }
  # Check users
  for user in games gnats irc; do
    passwd -S "$user" 2>/dev/null | grep -q L && { echo "✓ $user locked"; ((score++)); } || { echo "✗ $user not locked"; }
  done
  # Check SSH config
  local ssh_conf="/etc/ssh/sshd_config"
  [[ -f "$ssh_conf" ]] && grep -q "PermitRootLogin prohibit-password" "$ssh_conf" && { echo "✓ SSH root login"; ((score++)); } || true
  [[ -f "$ssh_conf" ]] && grep -q "PasswordAuthentication no" "$ssh_conf" && { echo "✓ SSH no password"; ((score++)); } || true
  echo ""
  echo "Score: $score/$total"
  [[ $score -ge 20 ]] && ok "Good security posture" || warn "Needs improvement"
}

# ========== Kernel Lockdown ==========
kernel_lock() {
  if [[ -f /sys/kernel/security/lockdown ]]; then
    echo "confidentiality" > /sys/kernel/security/lockdown
    ok "Kernel locked (confidentiality mode)"
  else
    warn "Kernel lockdown not supported"
  fi
}

kernel_unlock() {
  if [[ -f /sys/kernel/security/lockdown ]]; then
    echo "integrity" > /sys/kernel/security/lockdown
    ok "Kernel set to integrity mode"
  fi
}

kernel_status() {
  cat /sys/kernel/security/lockdown 2>/dev/null || echo "Not supported"
}

# ========== Secure Boot ==========
secureboot_status() {
  if command -v mokutil &>/dev/null; then
    mokutil --sb-state 2>/dev/null || echo "SecureBoot status unknown"
  else
    od -An -t x1 /sys/firmware/efi/efi_secure_boot_variable 2>/dev/null | grep -q 01 && echo "Enabled" || echo "Disabled/Unknown"
  fi
}

# ========== Tamper Detection ==========
tamper_checksums() {
  local db="$STATE_DIR/checksums.db"
  case "$1" in
    init)
      find /bin /sbin /usr/bin /usr/sbin /usr/local/bin -type f -exec sha256sum {} \; > "$db"
      ok "Checksums initialized ($(wc -l < "$db") files)"
      ;;
    check)
      [[ -f "$db" ]] || die "Run init first"
      local changes=0
      while IFS=' ' read -r sum file; do
        [[ ! -f "$file" ]] && { warn "Deleted: $file"; ((changes++)); continue; }
        local cur=$(sha256sum "$file")
        [[ "$sum" != "${cur%% *}" ]] && { warn "Changed: $file"; ((changes++)); }
      done < "$db"
      [[ $changes -eq 0 ]] && ok "No tamper detected" || warn "$changes files changed"
      ;;
  esac
}

# ========== Recycle Bin ==========
trash() { mkdir -p "$HOME/.trash" && mv "$@" "$HOME/.trash/"; }
trash_list() { ls -la "$HOME/.trash" 2>/dev/null; }
trash_restore() {
  local file="$1"
  [[ -f "$HOME/.trash/$file" ]] && mv "$HOME/.trash/$file" . && ok "Restored: $file"
}
trash_empty() { rm -rf "$HOME/.trash"/* && ok "Trash emptied"; }

# ========== Disk Management ==========
disk_list() { lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,MODEL; }
disk_info() { blkid "$1" 2>/dev/null; }
disk_mount() {
  local dev="$1" mnt="${2:-}"
  [[ -z "$mnt" ]] && mnt="/mnt/$(basename "$dev")"
  mkdir -p "$mnt"
  mount "$dev" "$mnt" && ok "Mounted $dev at $mnt"
}
disk_umount() {
  local mnt="$1"
  umount "$mnt" && ok "Unmounted $mnt"
}
disk_format() {
  local dev="$1" fstype="${2:-ext4}" label="${3:-}"
  warn "Format $dev as $fstype?"
  read -rp "Continue? [y/N] " c
  [[ "$c" =~ ^[yY] ]] || return
  mkfs."$fstype" -F "$dev" ${label:+-L "$label"}
  ok "Formatted $dev as $fstype"
}

# ========== File Manager TUI ==========
fm() {
  local dir="${1:-.}"
  while true; do
    clear
    echo -e "\033[96m=== Taja File Manager ===\033[0m"
    echo "Dir: $(realpath "$dir" 2>/dev/null || echo "$dir")"
    echo ""
    local files=()
    files+=("..")
    for f in "$dir"/*; do
      [[ -e "$f" ]] || continue
      local name=$(basename "$f")
      if [[ -d "$f" ]]; then files+=("$name/"); elif [[ -x "$f" ]]; then files+=("$name*"); else files+=("$name"); fi
    done
    local sel=0 off=0
    local max=$(($(tput lines 2>/dev/null || echo 24) - 6))
    while true; do
      clear
      echo -e "\033[96m=== Taja File Manager ===\033[0m"
      echo "Dir: $(realpath "$dir" 2>/dev/null || echo "$dir")"
      echo ""
      local end=$((off + max))
      [[ $end -gt ${#files[@]} ]] && end=${#files[@]}
      for ((i=off; i<end; i++)); do
        if [[ $i -eq $sel ]]; then echo -e "\033[7m ${files[i]}\033[0m"; else echo " ${files[i]}"; fi
      done
      echo ""
      echo "↑↓=Nav Enter=Open ←=Back d=Del c=Copy r=Rename q=Quit"
      IFS= read -rsn1 key
      case "$key" in
        q|Q) return ;;
        $'\n'|$'\r')
          local item="${files[sel]}"
          if [[ "$item" == ".." ]]; then dir="$(realpath "$dir/..")"
          elif [[ "$item" == */ ]]; then dir="$dir/${item%/}"
          elif [[ -f "$dir/$item" ]]; then less "$dir/$item" 2>/dev/null
          fi
          break ;;
        $'\177'|$'\b') dir="$(realpath "$dir/..")"; break ;;
        $'\e')
          read -rsn2 k2
          case "$k2" in
            '[A') [[ $sel -gt 0 ]] && sel=$((sel-1)); [[ $sel -lt $off ]] && off=$sel ;;
            '[B') [[ $sel -lt $((${#files[@]}-1)) ]] && sel=$((sel+1)); [[ $sel -ge $((off+max)) ]] && off=$((sel-max+1)) ;;
          esac
          ;;
        d|D)
          local f="$dir/${files[sel]}"
          if [[ "$f" != "$dir/.." ]]; then
            read -rp "Delete $f? [y/N] " c
            [[ "$c" =~ ^[yY] ]] && rm -rf "$f"
          fi
          break ;;
      esac
    done
  done
}

# ========== Role-Based Permissions ==========
perm_check() {
  local cmd="$1"
  local perms_file="$CONFIG_DIR/permissions.conf"
  [[ -f "$perms_file" ]] || return 0
  local allowed=$(grep "^$USER:" "$perms_file" | cut -d: -f2)
  local blocked=$(grep "^$USER:" "$perms_file" | cut -d: -f3)
  for b in $blocked; do [[ "$cmd" == "$b"* ]] && die "Permission denied: $cmd"; done
  [[ -n "$allowed" ]] && for a in $allowed; do [[ "$cmd" == "$a"* ]] && return 0; done
  [[ -n "$allowed" ]] && die "Permission denied: $cmd (not in whitelist)"
  return 0
}

perm_set() {
  local user="$1" allowed="$2" blocked="$3"
  echo "$user:$allowed:$blocked" >> "$CONFIG_DIR/permissions.conf"
  ok "Permission set for $user"
}

# ========== Confirm Prompt ==========
confirm() {
  local msg="${1:-Are you sure?}"
  read -rp "$msg [y/N] " reply
  [[ "$reply" =~ ^[yY] ]]
}

# ========== Firewall ==========
fw_allow_ssh() { nft add rule inet filter input tcp dport 22 accept 2>/dev/null; }
fw_allow_http() { nft add rule inet filter input tcp dport {80,443} accept 2>/dev/null; }
fw_block_ip() { nft add rule inet filter input ip saddr "$1" drop 2>/dev/null; ok "Blocked: $1"; }

usage() {
  cat << USAGE
Usage: tajasec <command> [args]

Vault:
  vault-create <name> [size_mb]    Create encrypted vault
  vault-open <name> [password]     Open vault
  vault-close <name>               Close vault
  vault-list                       List vaults

Hardening:
  harden-apply                     Apply all hardening
  harden-check                     Audit security score
  harden-sysctl                    Apply sysctl hardening
  harden-ssh                       Harden SSH config
  harden-users                     Lock unused accounts

Audit:
  audit-view [lines]               View audit log
  audit-search <query>             Search audit log
  audit-stats                      Audit statistics

Kernel:
  kernel-lock                      Lock kernel
  kernel-unlock                    Unlock kernel
  kernel-status                    Show kernel lockdown status

Secure Boot:
  secureboot-status                Check secure boot status

Tamper:
  tamper-init                      Initialize checksums
  tamper-check                     Check file integrity

Permissions:
  perm-set <user> <allow> <block>  Set permissions
  perm-check <cmd>                 Check command permission

Other:
  trash <file...>                  Move to trash
  trash-list                       List trash
  trash-restore <file>             Restore from trash
  trash-empty                      Empty trash
  confirm                          Ask confirmation
  firewall-ssh                     Allow SSH
  firewall-http                    Allow HTTP/HTTPS
  firewall-block <ip>              Block IP address

Disk:
  disk-list                        List block devices
  disk-info <dev>                  Show device info
  disk-mount <dev> [mnt]           Mount device
  disk-umount <mnt>                Unmount device
  disk-format <dev> [fs] [label]   Format device

File Manager:
  fm [dir]                         TUI file manager
USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    vault-create) vault_create "$@" ;;
    vault-open) vault_open "$@" ;;
    vault-close) vault_close "$@" ;;
    vault-list) vault_list ;;
    harden-apply) harden_apply ;;
    harden-check) harden_check ;;
    harden-sysctl) harden_sysctl ;;
    harden-ssh) harden_ssh ;;
    harden-users) harden_users ;;
    audit-view) audit_view "$@" ;;
    audit-search) audit_search "$@" ;;
    audit-stats) audit_stats ;;
    kernel-lock) kernel_lock ;;
    kernel-unlock) kernel_unlock ;;
    kernel-status) kernel_status ;;
    secureboot-status) secureboot_status ;;
    tamper-init) tamper_checksums init ;;
    tamper-check) tamper_checksums check ;;
    perm-set) perm_set "$@" ;;
    perm-check) perm_check "$@" ;;
    trash) trash "$@" ;;
    trash-list) trash_list ;;
    trash-restore) trash_restore "$@" ;;
    trash-empty) trash_empty ;;
    confirm) confirm "$@" ;;
    firewall-ssh) fw_allow_ssh ;;
    firewall-http) fw_allow_http ;;
    firewall-block) fw_block_ip "$@" ;;
    disk-list) disk_list ;;
    disk-info) disk_info "$@" ;;
    disk-mount) disk_mount "$@" ;;
    disk-umount) disk_umount "$@" ;;
    disk-format) disk_format "$@" ;;
    fm) fm "$@" ;;
    *) usage; exit 1 ;;
  esac
  audit_log "$cmd" "$*"
}

main "$@"