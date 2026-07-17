#!/bin/bash
# ============================================================
#  TajaRecover — Recovery & System Health
#  Boot repair, rollback, snapshots, system rescue
# ============================================================
set -euo pipefail

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[TajaRecover]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

# Boot repair
recover_boot_repair() {
  log "Repairing boot..."
  if command -v update-grub &>/dev/null; then
    update-grub && ok "GRUB updated"
  fi
  if command -v grub-install &>/dev/null; then
    for disk in /dev/sd[a-z]; do
      [[ -b "$disk" ]] && grub-install "$disk" 2>/dev/null && ok "GRUB installed to $disk"
    done
  fi
  update-initramfs -u -k all && ok "Initramfs rebuilt"
}

recover_fs_check() {
  log "Checking filesystems..."
  local devs=$(lsblk -o NAME,FSTYPE | grep -E 'ext4|btrfs|xfs' | awk '{print "/dev/"$1}')
  for dev in $devs; do
    [[ -b "$dev" ]] || continue
    umount "$dev" 2>/dev/null || true
    fsck -y "$dev" 2>/dev/null && ok "Checked: $dev" || warn "Issues on: $dev"
    mount -a 2>/dev/null || true
  done
}

# Rollback
recover_rollback() {
  log "Starting rollback..."
  [[ -f /persist.img ]] || die "No persistence image"
  local mnt="/mnt/persist"
  mount /persist.img "$mnt" 2>/dev/null || die "Cannot mount persistence"
  local snaps=("$mnt/snapshots"/*/)
  [[ ${#snaps[@]} -eq 0 ]] && { umount "$mnt"; die "No snapshots found"; }
  echo "Available snapshots:"
  for s in "${snaps[@]}"; do echo "  $(basename "$s")"; done
  read -rp "Enter snapshot name to rollback to: " snap
  local snap_dir="$mnt/snapshots/$snap"
  [[ -d "$snap_dir" ]] || { umount "$mnt"; die "Snapshot not found: $snap"; }
  rsync -a --delete "$snap_dir/" "$mnt/upper/"
  ok "Rolled back to: $snap"
  umount "$mnt"
}

# System health check
recover_doctor() {
  echo -e "\033[96m=== TajaOS System Doctor ===\033[0m"
  echo "Date: $(date)"
  echo "Kernel: $(uname -r)"
  echo "Uptime: $(uptime -p)"
  echo ""
  echo -e "--- CPU ---"
  lscpu | grep -E 'Model name|CPU\(s\)|MHz'
  echo ""
  echo -e "--- Memory ---"
  free -h
  echo ""
  echo -e "--- Disk ---"
  df -h /
  echo ""
  echo -e "--- Network ---"
  ip -br addr | head -10
  echo ""
  echo -e "--- Failed Services ---"
  systemctl list-units --failed --no-legend
  echo ""
  echo -e "--- Temperature ---"
  sensors 2>/dev/null | head -10 || echo "n/a"
  echo ""
  echo -e "--- GPU ---"
  lspci | grep -i vga || echo "n/a"
  echo ""
  echo -e "--- Battery ---"
  upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null | grep percentage || echo "n/a"
}

# Integrity check
recover_integrity() {
  local db="/var/lib/tajados/checksums.db"
  [[ -f "$db" ]] || die "Run 'tajasec tamper-init' first"
  local changes=0
  while IFS=' ' read -r sum file; do
    local cur=$(sha256sum "$file" 2>/dev/null)
    [[ -z "$cur" ]] && { warn "Missing: $file"; ((changes++)); continue; }
    [[ "$sum" != "${cur%% *}" ]] && { warn "Modified: $file"; ((changes++)); }
  done < "$db"
  [[ $changes -eq 0 ]] && ok "All files intact"
}

# Log bundle
recover_log_bundle() {
  local dest="${1:-/tmp/tajados-logs-$(date +%Y%m%d-%H%M%S).tar.gz}"
  local tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/logs"
  journalctl --no-pager -n 500 > "$tmpdir/logs/journal.txt"
  systemctl list-units --all --no-legend > "$tmpdir/logs/services.txt"
  uptime > "$tmpdir/logs/uptime.txt"
  dmesg > "$tmpdir/logs/dmesg.txt" 2>/dev/null || true
  cat /var/log/syslog > "$tmpdir/logs/syslog.txt" 2>/dev/null || true
  cp -r /etc/tajados "$tmpdir/logs/config" 2>/dev/null || true
  tar -czf "$dest" -C "$tmpdir" logs
  rm -rf "$tmpdir"
  ok "Log bundle: $dest ($(du -h "$dest" | cut -f1))"
}

# Snapshot system
recover_snapshot_create() {
  local name="${1:-auto-$(date +%Y%m%d-%H%M%S)}"
  local mnt="/mnt/persist"
  [[ -f /persist.img ]] || die "No persistence"
  mount /persist.img "$mnt" 2>/dev/null || die "Mount failed"
  mkdir -p "$mnt/snapshots"
  local target="$mnt/snapshots/$name"
  rsync -a "$mnt/upper/" "$target/"
  echo "$(date -Iseconds)" > "$target/.timestamp"
  ok "Snapshot: $name"
  umount "$mnt"
}

recover_snapshot_list() {
  local mnt="/mnt/persist"
  [[ -f /persist.img ]] || die "No persistence"
  mount /persist.img "$mnt" 2>/dev/null || die "Mount failed"
  for d in "$mnt/snapshots"/*/; do
    [[ -d "$d" ]] || continue
    local name=$(basename "$d")
    local size=$(du -sh "$d" | cut -f1)
    local ts=$(cat "$d/.timestamp" 2>/dev/null || echo "unknown")
    echo "$name ($size) - $ts"
  done
  umount "$mnt"
}

# Recovery USB creator
recover_usb_create() {
  local iso="$1" dev="${2:-}"
  [[ -f "$iso" ]] || die "ISO not found: $iso"
  [[ -z "$dev" ]] && read -rp "Target device (e.g. /dev/sdb): " dev
  [[ -b "$dev" ]] || die "Not a block device: $dev"
  warn "This will erase $dev!"
  read -rp "Continue? [y/N] " confirm
  [[ "$confirm" =~ ^[yY] ]] || exit 1
  dd if="$iso" of="$dev" bs=4M status=progress
  sync
  ok "Recovery USB created on $dev"
}

# Factory reset
recover_factory_reset() {
  warn "This will wipe all data and reset to factory defaults!"
  read -rp "Type 'RESET' to confirm: " confirm
  [[ "$confirm" == "RESET" ]] || exit 1
  rm -f /persist.img
  rm -rf /etc/tajados /var/lib/tajados
  rm -f /etc/hostname /etc/machine-id
  rm -f /root/.bashrc /root/.bash_history
  log "Factory reset complete. Reboot required."
}

usage() {
  cat << USAGE
Usage: tajarecover <command> [args]

  boot-repair            Repair GRUB & initramfs
  fs-check               Check filesystems
  doctor                 System health check
  integrity              Check file integrity
  log-bundle [dest]      Export diagnostic logs
  snapshot-create [name] Create recovery snapshot
  snapshot-list          List snapshots
  rollback               Rollback to snapshot
  usb-create <iso> [dev] Create recovery USB
  factory-reset          Wipe & reset to defaults
USAGE
}

main() {
  [[ $# -eq 0 ]] && { recover_doctor; exit 0; }
  case "$1" in
    boot-repair) recover_boot_repair ;;
    fs-check) recover_fs_check ;;
    doctor) recover_doctor ;;
    integrity) recover_integrity ;;
    log-bundle) recover_log_bundle "${2:-}" ;;
    snapshot-create) recover_snapshot_create "${2:-}" ;;
    snapshot-list) recover_snapshot_list ;;
    rollback) recover_rollback ;;
    usb-create) recover_usb_create "${2:-}" "${3:-}" ;;
    factory-reset) recover_factory_reset ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"