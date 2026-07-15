#!/bin/bash
# ============================================================
#  NEXUS OS — Master Build Script (Fixed)
#  Usage: sudo ./makebuild.sh [--clean] [--no-squash] [--output DIR]
# ============================================================
set -e

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[NEXUS]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

CLEAN=false; NO_SQUASH=false; OUTPUT_DIR="$(pwd)"
for arg in "$@"; do
  case $arg in
    --clean)     CLEAN=true ;;
    --no-squash) NO_SQUASH=true ;;
    --output)    OUTPUT_DIR="$2"; shift ;;
    --help)      echo "Usage: sudo ./makebuild.sh [--clean] [--no-squash] [--output DIR]"; exit 0 ;;
  esac
done

[[ $EUID -ne 0 ]] && die "Run as root: sudo ./makebuild.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="$SCRIPT_DIR/rootfs"
ISO_DIR="$SCRIPT_DIR/iso"
OUTPUT_ISO="$OUTPUT_DIR/nexus.iso"

log "Nexus OS Build System v1.1 (Fixed)"
log "Output: $OUTPUT_ISO"

# ── Step 1: Clean ──────────────────────────────────────────
if $CLEAN; then
  warn "Removing existing rootfs..."
  rm -rf "$ROOTFS" "$ISO_DIR" core.img bios.img efiboot.img
fi

# ── Step 2: Bootstrap ─────────────────────────────────────
if [[ ! -d "$ROOTFS/bin" ]]; then
  log "Bootstrapping Ubuntu 24.04 Noble..."
  debootstrap --arch=amd64 --variant=minbase noble "$ROOTFS" \
    http://archive.ubuntu.com/ubuntu/ 2>&1 | grep -E "^[EW]:" || true
  ok "Bootstrap done"
else
  warn "Rootfs exists — skipping (use --clean to rebuild)"
fi

# ── Step 3: apt sources ───────────────────────────────────
cat > "$ROOTFS/etc/apt/sources.list" << 'SOURCES'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe
SOURCES

# ── Step 4: Mount virtual filesystems ─────────────────────
mountpoint -q "$ROOTFS/proc" || mount --bind /proc "$ROOTFS/proc"
mountpoint -q "$ROOTFS/sys"  || mount --bind /sys  "$ROOTFS/sys"
mountpoint -q "$ROOTFS/dev"  || mount --bind /dev  "$ROOTFS/dev"
trap "umount '$ROOTFS/proc' '$ROOTFS/sys' '$ROOTFS/dev' 2>/dev/null; true" EXIT

# ── Step 5: Install packages + LIVE-BOOT (critical fix) ───
log "Installing packages (including live-boot)..."
chroot "$ROOTFS" /bin/bash -c "
  apt-get update -qq

  # CRITICAL: live-boot makes squashfs mount as root on boot
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    linux-image-generic \
    initramfs-tools \
    live-boot \
    live-boot-initramfs-tools \
    live-config \
    live-config-systemd \
    python3 python3-pip python3-requests \
    bash coreutils systemd systemd-sysv \
    util-linux procps psmisc htop \
    iproute2 iputils-ping net-tools \
    vim nano curl wget \
    ca-certificates locales \
    2>&1 | grep -E '^(Setting up|Removing|E:)' | head -30

  echo root:nexus | chpasswd
  echo '[NEXUS] Base packages installed'
"

# ── Step 6: Custom packages from packages.list ────────────
if [[ -f "$SCRIPT_DIR/customize/packages.list" ]]; then
  PKGS=$(grep -v '^\s*#' "$SCRIPT_DIR/customize/packages.list" | grep -v '^\s*$' | tr '\n' ' ')
  if [[ -n "$PKGS" ]]; then
    log "Installing custom packages: $PKGS"
    chroot "$ROOTFS" /bin/bash -c "
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PKGS \
        2>&1 | grep -E '^(Setting up|E:)' || true
    "
  fi
fi

ok "All packages installed"

# ── Step 7: Install Nexus AI Agent ────────────────────────
log "Installing Nexus AI Agent..."
mkdir -p "$ROOTFS/etc/nexus"
cp "$SCRIPT_DIR/nexus-agent.py" "$ROOTFS/usr/local/bin/nexus-agent.py"
chmod +x "$ROOTFS/usr/local/bin/nexus-agent.py"

cat > "$ROOTFS/usr/local/bin/nexus" << 'LAUNCHER'
#!/bin/bash
export TERM=linux
export PYTHONUNBUFFERED=1
[ -f /etc/nexus/api.key ] && export ANTHROPIC_API_KEY=$(cat /etc/nexus/api.key)
exec /usr/local/bin/nexus-agent.py
LAUNCHER
chmod +x "$ROOTFS/usr/local/bin/nexus"

# ── Step 8: System identity ───────────────────────────────
log "Configuring system identity..."
echo "nexus" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << 'HOSTS'
127.0.0.1   localhost
127.0.1.1   nexus
::1         localhost ip6-localhost ip6-loopback
HOSTS

cat > "$ROOTFS/etc/os-release" << OSREL
NAME="Nexus OS"
VERSION="1.0"
ID=nexus
ID_LIKE=ubuntu
PRETTY_NAME="Nexus OS 1.0 — Agentic AI Linux"
NEXUS_AGENT="claude-sonnet-4-6"
BUILD_DATE=$(date +%Y-%m-%d)
OSREL

# ── Step 9: Auto-login & auto-launch ──────────────────────
log "Configuring auto-login..."
mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
GETTY

# Auto-launch nexus on tty1 login
cat > "$ROOTFS/root/.bash_profile" << 'PROFILE'
if [ "$(tty)" = "/dev/tty1" ]; then
  exec /usr/local/bin/nexus
fi
PROFILE

# ── Step 10: Custom startup script ────────────────────────
if [[ -f "$SCRIPT_DIR/customize/startup.sh" ]]; then
  cp "$SCRIPT_DIR/customize/startup.sh" "$ROOTFS/etc/nexus/startup.sh"
  chmod +x "$ROOTFS/etc/nexus/startup.sh"
fi

# MOTD
if [[ -f "$SCRIPT_DIR/customize/motd.txt" ]]; then
  cp "$SCRIPT_DIR/customize/motd.txt" "$ROOTFS/etc/motd"
else
  cat > "$ROOTFS/etc/motd" << 'MOTD'

  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝ ██╔═══██╗██╔════╝
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║ ██║   ██║╚════██║
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║
  ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝  ╚═════╝ ╚══════╝

  Nexus OS 1.0 — Agentic AI Linux  |  Type 'nexus' to launch AI agent

MOTD
fi

# ── Step 11: CRITICAL — Rebuild initramfs with live-boot ──
log "Rebuilding initramfs with live-boot support..."
chroot "$ROOTFS" /bin/bash -c "
  update-initramfs -u -k all 2>&1 | tail -5
  echo 'Initramfs rebuilt.'
"
ok "Initramfs rebuilt"

# ── Step 12: Unmount ──────────────────────────────────────
umount "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" 2>/dev/null || true
trap - EXIT

# ── Step 13: ISO directory structure ─────────────────────
log "Building ISO structure..."
mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/EFI/boot"
mkdir -p "$ISO_DIR/live"       # live-boot looks here for filesystem.squashfs

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 | sed 's/.*vmlinuz-//')
[[ -z "$KVER" ]] && die "No kernel found in $ROOTFS/boot/"
log "Kernel: $KVER"

cp "$ROOTFS/boot/vmlinuz-${KVER}"    "$ISO_DIR/boot/vmlinuz"
cp "$ROOTFS/boot/initrd.img-${KVER}" "$ISO_DIR/boot/initrd.img"
cp "$SCRIPT_DIR/boot/grub/grub.cfg"  "$ISO_DIR/boot/grub/grub.cfg"

# ── Step 14: Squashfs ─────────────────────────────────────
if ! $NO_SQUASH; then
  log "Creating squashfs (this takes ~20 minutes)..."
  mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level 3 \
    -e boot \
    -noappend \
    2>&1 | tail -3
  ok "Squashfs: $(du -sh $ISO_DIR/live/filesystem.squashfs | cut -f1)"
else
  warn "Skipping squashfs (--no-squash)"
fi

# ── Step 15: GRUB bootloaders ────────────────────────────
log "Building GRUB bootloaders..."

# EFI bootloader
grub-mkstandalone \
  --format=x86_64-efi \
  --output="$ISO_DIR/EFI/boot/bootx64.efi" \
  --locales="" --fonts="" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

# BIOS bootloader
grub-mkstandalone \
  --format=i386-pc \
  --output="$SCRIPT_DIR/core.img" \
  --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
  --modules="linux normal iso9660 biosdisk search" \
  --locales="" --fonts="" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img "$SCRIPT_DIR/core.img" > "$SCRIPT_DIR/bios.img"

# EFI FAT image
dd if=/dev/zero of="$SCRIPT_DIR/efiboot.img" bs=1M count=4 status=none
mkfs.fat -F12 "$SCRIPT_DIR/efiboot.img"
mmd   -i "$SCRIPT_DIR/efiboot.img" ::/EFI ::/EFI/boot
mcopy -i "$SCRIPT_DIR/efiboot.img" "$ISO_DIR/EFI/boot/bootx64.efi" ::/EFI/boot/

# Copy into ISO dir
cp "$SCRIPT_DIR/bios.img"    "$ISO_DIR/bios.img"
cp "$SCRIPT_DIR/efiboot.img" "$ISO_DIR/efiboot.img"
ok "Bootloaders ready"

# ── Step 16: Build ISO ───────────────────────────────────
log "Building nexus.iso..."
xorriso -as mkisofs \
  -iso-level 3 \
  -volid "NEXUS_OS_1_0" \
  -appid "Nexus OS 1.0 Agentic AI Linux" \
  -publisher "Nexus AI Project" \
  -b bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
  -eltorito-alt-boot \
  -e efiboot.img \
    -no-emul-boot \
  --protective-msdos-label \
  -append_partition 2 0xef "$SCRIPT_DIR/efiboot.img" \
  -o "$OUTPUT_ISO" \
  "$ISO_DIR"

# ── Done ─────────────────────────────────────────────────
echo ""
ok "BUILD COMPLETE!"
echo ""
echo "  ISO    : $OUTPUT_ISO"
echo "  Size   : $(du -sh $OUTPUT_ISO | cut -f1)"
echo "  SHA256 : $(sha256sum $OUTPUT_ISO | cut -d' ' -f1)"
echo ""
echo "  Flash  : dd if=nexus.iso of=/dev/sdX bs=4M status=progress"
echo "  VM     : make qemu"
