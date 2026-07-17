#!/bin/bash
# ============================================================
#  TajaPersist — Persistence Manager
#  OverlayFS, snapshots, backup/restore, migration
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
CONFIG_DIR="/etc/tajados"
STATE_DIR="/var/lib/tajados"
PERSIST_DIR="/mnt/persist"
PERSIST_IMG="/persist.img"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[TajaPersist]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

# ========== Persistence Image ==========
persist_create() {
  local size="${1:-2048}"  # MB
  [[ -f "$PERSIST_IMG" ]] && die "Persistence image exists: $PERSIST_IMG"
  log "Creating persistence image (${size}MB)..."
  dd if=/dev/zero of="$PERSIST_IMG" bs=1M count="$size" status=progress
  mkfs.ext4 -F -L persistence "$PERSIST_IMG"
  mkdir -p "$PERSIST_DIR"
  mount "$PERSIST_IMG" "$PERSIST_DIR"
  mkdir -p "$PERSIST_DIR/upper" "$PERSIST_DIR/work" "$PERSIST_DIR/snapshots"
  echo "/ union" > "$PERSIST_DIR/persistence.conf"
  ok "Persistence created at $PERSIST_IMG"
}

persist_resize() {
  local new_size="${1:-4096}"
  [[ -f "$PERSIST_IMG" ]] || die "No persistence image found"
  log "Resizing to ${new_size}MB..."
  umount "$PERSIST_DIR" 2>/dev/null || true
  dd if=/dev/zero bs=1M count=$((new_size - $(du -m "$PERSIST_IMG" | cut -f1))) >> "$PERSIST_IMG"
  e2fsck -f "$PERSIST_IMG"
  resize2fs "$PERSIST_IMG"
  mount "$PERSIST_IMG" "$PERSIST_DIR"
  ok "Resized to ${new_size}MB"
}

persist_mount() {
  [[ -f "$PERSIST_IMG" ]] || die "No persistence image: $PERSIST_IMG"
  mkdir -p "$PERSIST_DIR"
  mount "$PERSIST_IMG" "$PERSIST_DIR"
  mkdir -p "$PERSIST_DIR/upper" "$PERSIST_DIR/work" "$PERSIST_DIR/snapshots"
  ok "Mounted at $PERSIST_DIR"
}

persist_umount() {
  umount "$PERSIST_DIR" 2>/dev/null && ok "Unmounted" || warn "Not mounted"
}

persist_status() {
  if mountpoint -q "$PERSIST_DIR"; then
    ok "Active: $PERSIST_DIR"
    df -h "$PERSIST_DIR"
    echo "Upper: $(du -sh "$PERSIST_DIR/upper" 2>/dev/null | cut -f1)"
    echo "Work:  $(du -sh "$PERSIST_DIR/work" 2>/dev/null | cut -f1)"
    echo "Snapshots: $(ls -1 "$PERSIST_DIR/snapshots" 2>/dev/null | wc -l)"
  else
    warn "Not mounted"
    [[ -f "$PERSIST_IMG" ]] && echo "Image exists: $(du -h "$PERSIST_IMG" | cut -f1)"
  fi
}

# ========== Overlay Management ==========
overlay_mount() {
  local lower="${1:-/}"
  local upper="$PERSIST_DIR/upper"
  local work="$PERSIST_DIR/work"
  local mount_point="/mnt/root"
  mkdir -p "$mount_point"
  mount -t overlay overlay -o "lowerdir=$lower,upperdir=$upper,workdir=$work" "$mount_point"
  mount --bind "$mount_point" /
  ok "Overlay mounted at $mount_point"
}

overlay_umount() {
  umount /mnt/root 2>/dev/null || true
  umount / 2>/dev/null || true
  ok "Overlay unmounted"
}

# ========== Snapshots ==========
snapshot_create() {
  local name="${1:-$(date +%Y%m%d-%H%M%S)}"
  local snap_dir="$PERSIST_DIR/snapshots/$name"
  mkdir -p "$snap_dir"
  log "Creating snapshot: $name"
  rsync -a --delete "$PERSIST_DIR/upper/" "$snap_dir/" 2>/dev/null
  echo "$(date -Iseconds)" > "$snap_dir/.timestamp"
  ok "Snapshot created: $snap_dir"
}

snapshot_list() {
  echo "=== Snapshots ==="
  for d in "$PERSIST_DIR/snapshots"/*/; do
    [[ -d "$d" ]] || continue
    local name=$(basename "$d")
    local size=$(du -sh "$d" | cut -f1)
    local time=$(cat "$d/.timestamp" 2>/dev/null || echo "unknown")
    echo "  $name  ($size)  $time"
  done
}

snapshot_restore() {
  local name="$1"
  local snap_dir="$PERSIST_DIR/snapshots/$name"
  [[ -d "$snap_dir" ]] || die "Snapshot not found: $name"
  log "Restoring snapshot: $name"
  rsync -a --delete "$snap_dir/" "$PERSIST_DIR/upper/" 2>/dev/null
  ok "Restored: $name"
}

snapshot_delete() {
  local name="$1"
  local snap_dir="$PERSIST_DIR/snapshots/$name"
  [[ -d "$snap_dir" ]] || die "Snapshot not found: $name"
  rm -rf "$snap_dir"
  ok "Deleted: $name"
}

snapshot_diff() {
  local name1="$1" name2="$2"
  local d1="$PERSIST_DIR/snapshots/$name1"
  local d2="$PERSIST_DIR/snapshots/$name2"
  [[ -d "$d1" && -d "$d2" ]] || die "One or both snapshots not found"
  diff -ru "$d1" "$d2" 2>/dev/null | head -100
}

# ========== Backup & Restore ==========
backup_create() {
  local dest="${1:-/backup/tajados-$(date +%Y%m%d-%H%M%S).tar.gz}"
  mkdir -p "$(dirname "$dest")"
  log "Creating backup: $dest"
  tar -czf "$dest" \
    --exclude="$PERSIST_DIR/snapshots" \
    --exclude="$PERSIST_DIR/work" \
    -C "$PERSIST_DIR" upper persistence.conf 2>/dev/null
  ok "Backup: $dest ($(du -h "$dest" | cut -f1))"
}

backup_restore() {
  local src="$1"
  [[ -f "$src" ]] || die "Backup not found: $src"
  log "Restoring from: $src"
  tar -xzf "$src" -C "$PERSIST_DIR" 2>/dev/null
  ok "Restored from $src"
}

backup_list() {
  ls -lh /backup/tajados-*.tar.gz 2>/dev/null || echo "No backups found"
}

# ========== Migration ==========
persist_migrate() {
  local new_img="$1" new_size="${2:-4096}"
  [[ -f "$PERSIST_IMG" ]] || die "No current persistence"
  log "Migrating to $new_img (${new_size}MB)..."
  dd if=/dev/zero of="$new_img" bs=1M count="$new_size" status=progress
  mkfs.ext4 -F -L persistence "$new_img"
  local new_mnt="/mnt/persist_new"
  mkdir -p "$new_mnt"
  mount "$new_img" "$new_mnt"
  mkdir -p "$new_mnt/upper" "$new_mnt/work" "$new_mnt/snapshots"
  rsync -a "$PERSIST_DIR/upper/" "$new_mnt/upper/" 2>/dev/null
  rsync -a "$PERSIST_DIR/snapshots/" "$new_mnt/snapshots/" 2>/dev/null
  cp "$PERSIST_DIR/persistence.conf" "$new_mnt/"
  umount "$new_mnt"
  umount "$PERSIST_DIR"
  mv "$new_img" "$PERSIST_IMG"
  mount "$PERSIST_IMG" "$PERSIST_DIR"
  ok "Migrated to $new_img"
}

# ========== Config Persistence ==========
config_persist() {
  local files=(
    "/etc/tajados"
    "/etc/hostname"
    "/etc/hosts"
    "/etc/resolv.conf"
    "/etc/ssh"
    "/etc/network"
    "/etc/netplan"
    "/root/.bashrc"
    "/root/.ssh"
    "/home/*/.bashrc"
    "/home/*/.ssh"
  )
  local upper="$PERSIST_DIR/upper"
  for f in "${files[@]}"; do
    for src in $f; do
      [[ -e "$src" ]] || continue
      local rel="${src#/}"
      local dst="$upper/$rel"
      mkdir -p "$(dirname "$dst")"
      cp -a "$src" "$dst" 2>/dev/null || true
    done
  done
  ok "Config persisted"
}

config_restore() {
  local upper="$PERSIST_DIR/upper"
  for f in "$upper/etc/tajados"/* "$upper/etc/hostname" "$upper/etc/hosts" "$upper/etc/resolv.conf" "$upper/etc/ssh" "$upper/etc/network" "$upper/root/.bashrc" "$upper/home"/*/.bashrc; do
    [[ -e "$f" ]] || continue
    local rel="${f#$upper/}"
    local dst="/$rel"
    mkdir -p "$(dirname "$dst")"
    cp -a "$f" "$dst" 2>/dev/null || true
  done
  ok "Config restored"
}

# ========== Auto-snapshot Service ==========
autosnap_enable() {
  cat > /etc/systemd/system/tajados-autosnap.service << 'EOF'
[Unit]
Description=TajaOS Auto-Snapshot
DefaultDependencies=no
After=local-fs.target
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tajados-persist snapshot-create auto-%Y%m%d-%H%M%S
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/tajados-autosnap.timer << 'EOF'
[Unit]
Description=Daily auto-snapshot

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now tajados-autosnap.timer
  ok "Auto-snapshot enabled (daily)"
}

autosnap_disable() {
  systemctl disable --now tajados-autosnap.timer 2>/dev/null || true
  ok "Auto-snapshot disabled"
}

# ========== CLI ==========
usage() {
  cat << USAGE
Usage: tajados-persist <command> [args]

Persistence:
  tajados-persist create [size_mb]          Create persistence image (default 2GB)
  tajados-persist resize <size_mb>          Resize persistence image
  tajados-persist mount                     Mount persistence
  tajados-persist umount                    Unmount persistence
  tajados-persist status                    Show status

Overlay:
  tajados-persist overlay-mount [lower]     Mount overlay filesystem
  tajados-persist overlay-umount            Unmount overlay

Snapshots:
  tajados-persist snapshot-create [name]    Create snapshot
  tajados-persist snapshot-list             List snapshots
  tajados-persist snapshot-restore <name>   Restore snapshot
  tajados-persist snapshot-delete <name>    Delete snapshot
  tajados-persist snapshot-diff <a> <b>     Diff two snapshots

Backup:
  tajados-persist backup-create [dest]      Create backup tarball
  tajados-persist backup-restore <src>      Restore from backup
  tajados-persist backup-list               List backups

Migration:
  tajados-persist migrate <new_img> [size]  Migrate to new image

Config:
  tajados-persist config-persist            Persist current config
  tajados-persist config-restore            Restore config from persistence

Auto-snapshot:
  tajados-persist autosnap-enable           Enable daily snapshots
  tajados-persist autosnap-disable          Disable daily snapshots

USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    create) persist_create "$@" ;;
    resize) persist_resize "$@" ;;
    mount) persist_mount ;;
    umount) persist_umount ;;
    status) persist_status ;;
    overlay-mount) overlay_mount "$@" ;;
    overlay-umount) overlay_umount ;;
    snapshot-create) snapshot_create "$@" ;;
    snapshot-list) snapshot_list ;;
    snapshot-restore) snapshot_restore "$@" ;;
    snapshot-delete) snapshot_delete "$@" ;;
    snapshot-diff) snapshot_diff "$@" ;;
    backup-create) backup_create "$@" ;;
    backup-restore) backup_restore "$@" ;;
    backup-list) backup_list ;;
    migrate) persist_migrate "$@" ;;
    config-persist) config_persist ;;
    config-restore) config_restore ;;
    autosnap-enable) autosnap_enable ;;
    autosnap-disable) autosnap_disable ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"