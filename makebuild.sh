#!/bin/bash
# ============================================================
#  NEXUS OS — Master Build Script v3 (grub-mkrescue fix)
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
    --help)
      echo "Usage: sudo ./makebuild.sh [--clean] [--no-squash] [--output DIR]"
      exit 0 ;;
  esac
done

[[ $EUID -ne 0 ]] && die "Run as root: sudo ./makebuild.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="$SCRIPT_DIR/rootfs"
ISO_DIR="$SCRIPT_DIR/iso"
OUTPUT_ISO="$OUTPUT_DIR/nexus.iso"

log "Nexus OS Build v3 — grub-mkrescue (all modules auto-included)"
log "Output: $OUTPUT_ISO"

# ── Step 1: Clean ──────────────────────────────────────────
if $CLEAN; then
  warn "Removing existing rootfs and ISO..."
  rm -rf "$ROOTFS" "$ISO_DIR"
fi

# ── Step 2: Bootstrap ─────────────────────────────────────
if [[ ! -d "$ROOTFS/bin" ]]; then
  log "Bootstrapping Ubuntu 24.04 Noble (minbase)..."
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

# ── Step 5: Install packages ───────────────────────────────
log "Installing packages..."
chroot "$ROOTFS" /bin/bash -c "
  apt-get update -qq

  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    linux-image-virtual \
    initramfs-tools \
    live-boot \
    live-boot-initramfs-tools \
    live-config \
    live-config-systemd \
    python3 \
    python3-requests \
    bash \
    coreutils \
    systemd \
    systemd-sysv \
    util-linux \
    procps \
    iproute2 \
    iputils-ping \
    nano \
    curl \
    ca-certificates \
    2>&1 | grep -E '^(Setting up|E:)' | head -40

  echo root:nexus | chpasswd

  # ── Cleanup to reduce ISO size ─────────────────────────
  apt-get clean
  apt-get autoremove -y --purge 2>/dev/null || true
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
  rm -rf /usr/share/locale/* /var/log/*.log /var/log/*.gz

  # Remove unused kernel modules
  KVER=\$(ls /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's/.*vmlinuz-//')
  if [[ -n \"\$KVER\" && -d \"/lib/modules/\$KVER/kernel\" ]]; then
    cd /lib/modules/\$KVER/kernel
    rm -rf drivers/media drivers/staging drivers/gpu/drm \
           drivers/bluetooth drivers/infiniband drivers/isdn \
           drivers/nfc sound 2>/dev/null || true
    depmod -a \$KVER 2>/dev/null || true
  fi
  echo '[NEXUS] Cleanup done'
"
ok "Packages installed and cleaned"

# ── Step 6: Custom packages ────────────────────────────────
if [[ -f "$SCRIPT_DIR/customize/packages.list" ]]; then
  PKGS=$(grep -v '^\s*#' "$SCRIPT_DIR/customize/packages.list" \
         | grep -v '^\s*$' | tr '\n' ' ')
  if [[ -n "$PKGS" ]]; then
    log "Installing custom packages: $PKGS"
    chroot "$ROOTFS" /bin/bash -c "
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends $PKGS 2>&1 | grep -E '^(Setting up|E:)' || true
      apt-get clean && rm -rf /var/lib/apt/lists/*
    "
  fi
fi

# ── Step 7: Nexus AI Agent ────────────────────────────────
log "Installing Nexus AI Agent..."
mkdir -p "$ROOTFS/etc/nexus"
cp "$SCRIPT_DIR/nexus-agent.py" "$ROOTFS/usr/local/bin/nexus-agent.py"
chmod +x "$ROOTFS/usr/local/bin/nexus-agent.py"

cat > "$ROOTFS/usr/local/bin/nexus" << 'LAUNCHER'
#!/bin/bash
export TERM=linux
export PYTHONUNBUFFERED=1
[ -f /etc/nexus/api.key ] && \
  export ANTHROPIC_API_KEY=$(cat /etc/nexus/api.key)
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

# Auto-login on tty1
mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
GETTY

# Auto-launch nexus agent
cat > "$ROOTFS/root/.bash_profile" << 'PROFILE'
if [ "$(tty)" = "/dev/tty1" ]; then
  exec /usr/local/bin/nexus
fi
PROFILE

# Custom files
[[ -f "$SCRIPT_DIR/customize/startup.sh" ]] && \
  cp "$SCRIPT_DIR/customize/startup.sh" "$ROOTFS/etc/nexus/startup.sh" && \
  chmod +x "$ROOTFS/etc/nexus/startup.sh"

if [[ -f "$SCRIPT_DIR/customize/motd.txt" ]]; then
  cp "$SCRIPT_DIR/customize/motd.txt" "$ROOTFS/etc/motd"
else
  cat > "$ROOTFS/etc/motd" << 'MOTD'

  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║

  Nexus OS 1.0 — Agentic AI Linux  |  Type 'nexus' to launch AI

MOTD
fi

# ── Step 9: Rebuild initramfs with live-boot ──────────────
log "Rebuilding initramfs with live-boot support..."
chroot "$ROOTFS" update-initramfs -u -k all 2>&1 | tail -5
ok "Initramfs rebuilt"

# ── Unmount ───────────────────────────────────────────────
umount "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" 2>/dev/null || true
trap - EXIT

# ── Step 10: ISO directory structure ─────────────────────
log "Building ISO structure..."
mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/live"

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 \
       | sed 's/.*vmlinuz-//')
[[ -z "$KVER" ]] && die "No kernel found in $ROOTFS/boot/"
log "Kernel: $KVER"

cp "$ROOTFS/boot/vmlinuz-${KVER}"    "$ISO_DIR/boot/vmlinuz"
cp "$ROOTFS/boot/initrd.img-${KVER}" "$ISO_DIR/boot/initrd.img"
cp "$SCRIPT_DIR/boot/grub/grub.cfg"  "$ISO_DIR/boot/grub/grub.cfg"

# ── Step 11: Squashfs ─────────────────────────────────────
if ! $NO_SQUASH; then
  log "Creating squashfs root filesystem (XZ compression)..."
  mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" \
    -comp xz -Xbcj x86 -b 1M \
    -e boot -noappend \
    2>&1 | tail -3
  ok "Squashfs: $(du -sh $ISO_DIR/live/filesystem.squashfs | cut -f1)"
else
  warn "Skipping squashfs (--no-squash)"
fi

# ── Step 12: Build ISO with grub-mkrescue ────────────────
# KEY FIX: grub-mkrescue automatically:
#   1. Embeds correct modules in core.img
#   2. Copies ALL *.mod files into /boot/grub/<arch>/ in the ISO
#   3. Creates proper BIOS + EFI hybrid boot record
# This fixes: echo.mod not found, chain.mod not found, out of memory
log "Building nexus.iso with grub-mkrescue..."
log "(This includes all GRUB modules automatically)"

grub-mkrescue \
  --output="$OUTPUT_ISO" \
  "$ISO_DIR" \
  -- \
  -volid   "NEXUS_OS_1_0" \
  -appid   "Nexus OS 1.0 Agentic AI Linux" \
  -publisher "Nexus AI Project" \
  -iso-level 3 \
  2>&1 | tail -10

# ── Done ─────────────────────────────────────────────────
echo ""
ok "BUILD COMPLETE!"
echo ""
echo "  ISO    : $OUTPUT_ISO"
echo "  Size   : $(du -sh $OUTPUT_ISO | cut -f1)"
echo "  SHA256 : $(sha256sum $OUTPUT_ISO | cut -d' ' -f1)"
echo ""
echo "  Flash  : sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress"
echo "  VM     : make qemu"
