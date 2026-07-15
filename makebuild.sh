#!/bin/bash
# ============================================================
#  NEXUS OS — Master Build Script v4
#  Fix: xorriso + GRUB module copy (fixes echo.mod/chain.mod)
#  Usage: sudo ./makebuild.sh [--clean] [--no-squash]
# ============================================================
set -eo pipefail

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[NEXUS]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

CLEAN=false
NO_SQUASH=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --clean)     CLEAN=true;     shift ;;
    --no-squash) NO_SQUASH=true; shift ;;
    --help)
      echo "Usage: sudo ./makebuild.sh [--clean] [--no-squash]"
      exit 0 ;;
    *) shift ;;
  esac
done

[[ $EUID -ne 0 ]] && die "Run as root: sudo ./makebuild.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="$SCRIPT_DIR/rootfs"
ISO_DIR="$SCRIPT_DIR/iso"
OUTPUT_ISO="$SCRIPT_DIR/nexus.iso"

log "Nexus OS Build v4 — xorriso + GRUB modules"
log "Output : $OUTPUT_ISO"

# ── Step 1: Clean ──────────────────────────────────────────
if $CLEAN; then
  warn "Removing existing rootfs and ISO..."
  rm -rf "$ROOTFS" "$ISO_DIR" \
         "$SCRIPT_DIR"/{core.img,bios.img,efiboot.img,nexus.iso}
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

# ── Step 4: Mount ─────────────────────────────────────────
mountpoint -q "$ROOTFS/proc" || mount --bind /proc "$ROOTFS/proc"
mountpoint -q "$ROOTFS/sys"  || mount --bind /sys  "$ROOTFS/sys"
mountpoint -q "$ROOTFS/dev"  || mount --bind /dev  "$ROOTFS/dev"
trap "umount '$ROOTFS/proc' '$ROOTFS/sys' '$ROOTFS/dev' 2>/dev/null; true" EXIT

# ── Step 5: Install packages ───────────────────────────────
log "Installing packages..."
chroot "$ROOTFS" /bin/bash -c "
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends \
    linux-image-virtual \
    initramfs-tools \
    live-boot \
    live-boot-initramfs-tools \
    live-config \
    live-config-systemd \
    python3 \
    python3-requests \
    bash coreutils systemd systemd-sysv \
    util-linux procps iproute2 iputils-ping \
    nano curl ca-certificates \
    2>&1 | grep -E '^(Setting up|E:)' | head -30

  echo root:nexus | chpasswd

  # Cleanup to reduce size
  apt-get clean
  apt-get autoremove -y --purge 2>/dev/null || true
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
  rm -rf /usr/share/locale/* /var/log/*.log /var/log/*.gz

  # Remove unused kernel modules
  KVER=\$(ls /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's/.*vmlinuz-//')
  if [[ -n \"\$KVER\" ]]; then
    cd /lib/modules/\$KVER/kernel 2>/dev/null || true
    rm -rf drivers/media drivers/staging drivers/gpu/drm \
           drivers/bluetooth drivers/infiniband drivers/isdn \
           drivers/nfc sound 2>/dev/null || true
    depmod -a \$KVER 2>/dev/null || true
  fi
  echo done
"
ok "Packages installed"

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
log "Configuring system..."
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
PRETTY_NAME="Nexus OS 1.0 — Agentic AI Linux"
BUILD_DATE=$(date +%Y-%m-%d)
OSREL

mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
GETTY

cat > "$ROOTFS/root/.bash_profile" << 'PROFILE'
if [ "$(tty)" = "/dev/tty1" ]; then exec /usr/local/bin/nexus; fi
PROFILE

[[ -f "$SCRIPT_DIR/customize/startup.sh" ]] && \
  cp "$SCRIPT_DIR/customize/startup.sh" "$ROOTFS/etc/nexus/startup.sh" && \
  chmod +x "$ROOTFS/etc/nexus/startup.sh"

if [[ -f "$SCRIPT_DIR/customize/motd.txt" ]]; then
  cp "$SCRIPT_DIR/customize/motd.txt" "$ROOTFS/etc/motd"
else
  cat > "$ROOTFS/etc/motd" << 'MOTD'

  ██╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║
  Nexus OS 1.0 — Agentic AI Linux  |  type 'nexus' to start AI
MOTD
fi

# ── Step 9: Rebuild initramfs ─────────────────────────────
log "Rebuilding initramfs with live-boot..."
chroot "$ROOTFS" update-initramfs -u -k all 2>&1 | tail -3
ok "Initramfs rebuilt"

umount "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" 2>/dev/null || true
trap - EXIT

# ── Step 10: ISO structure ────────────────────────────────
log "Building ISO structure..."
mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/EFI/boot"
mkdir -p "$ISO_DIR/live"

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 \
       | sed 's/.*vmlinuz-//')
[[ -z "$KVER" ]] && die "No kernel found in $ROOTFS/boot/"
log "Kernel: $KVER"

cp "$ROOTFS/boot/vmlinuz-${KVER}"    "$ISO_DIR/boot/vmlinuz"
cp "$ROOTFS/boot/initrd.img-${KVER}" "$ISO_DIR/boot/initrd.img"
cp "$SCRIPT_DIR/boot/grub/grub.cfg"  "$ISO_DIR/boot/grub/grub.cfg"

# ── KEY FIX: Copy GRUB modules into ISO ──────────────────
# Without this, GRUB can't load echo.mod, chain.mod, etc.
log "Copying GRUB modules into ISO (fixes module-not-found errors)..."

if [[ -d /usr/lib/grub/i386-pc ]]; then
  mkdir -p "$ISO_DIR/boot/grub/i386-pc"
  cp /usr/lib/grub/i386-pc/*.mod "$ISO_DIR/boot/grub/i386-pc/" 2>/dev/null || true
  cp /usr/lib/grub/i386-pc/*.lst "$ISO_DIR/boot/grub/i386-pc/" 2>/dev/null || true
  MOD_COUNT=$(ls "$ISO_DIR/boot/grub/i386-pc/"*.mod 2>/dev/null | wc -l)
  ok "i386-pc: $MOD_COUNT module files"
else
  warn "GRUB i386-pc modules not found"
fi

if [[ -d /usr/lib/grub/x86_64-efi ]]; then
  mkdir -p "$ISO_DIR/boot/grub/x86_64-efi"
  cp /usr/lib/grub/x86_64-efi/*.mod "$ISO_DIR/boot/grub/x86_64-efi/" 2>/dev/null || true
  MOD_COUNT=$(ls "$ISO_DIR/boot/grub/x86_64-efi/"*.mod 2>/dev/null | wc -l)
  ok "x86_64-efi: $MOD_COUNT module files"
fi

# ── Step 11: Squashfs ─────────────────────────────────────
if ! $NO_SQUASH; then
  log "Creating squashfs (XZ)..."
  mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" \
    -comp xz -Xbcj x86 -b 1M -e boot -noappend 2>&1 | tail -3
  ok "Squashfs: $(du -sh $ISO_DIR/live/filesystem.squashfs | cut -f1)"
else
  warn "Skipping squashfs (--no-squash)"
fi

# ── Step 12: GRUB bootloaders ────────────────────────────
log "Building GRUB bootloaders..."

grub-mkstandalone \
  --format=x86_64-efi \
  --output="$ISO_DIR/EFI/boot/bootx64.efi" \
  --locales="" --fonts="" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

grub-mkstandalone \
  --format=i386-pc \
  --output="$SCRIPT_DIR/core.img" \
  --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
  --modules="linux normal iso9660 biosdisk search" \
  --locales="" --fonts="" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img "$SCRIPT_DIR/core.img" \
  > "$SCRIPT_DIR/bios.img"

dd if=/dev/zero of="$SCRIPT_DIR/efiboot.img" bs=1M count=4 status=none
mkfs.fat -F12 "$SCRIPT_DIR/efiboot.img"
mmd   -i "$SCRIPT_DIR/efiboot.img" ::/EFI ::/EFI/boot
mcopy -i "$SCRIPT_DIR/efiboot.img" \
  "$ISO_DIR/EFI/boot/bootx64.efi" ::/EFI/boot/

cp "$SCRIPT_DIR/bios.img"    "$ISO_DIR/bios.img"
cp "$SCRIPT_DIR/efiboot.img" "$ISO_DIR/efiboot.img"
ok "Bootloaders ready"

# ── Step 13: Build ISO with xorriso ──────────────────────
log "Building nexus.iso with xorriso..."
xorriso -as mkisofs \
  -iso-level 3 \
  -volid "NEXUS_OS_1_0" \
  -appid "Nexus OS 1.0 Agentic AI Linux" \
  -publisher "Nexus AI Project" \
  -b bios.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e efiboot.img -no-emul-boot \
  --protective-msdos-label \
  -append_partition 2 0xef "$SCRIPT_DIR/efiboot.img" \
  -o "$OUTPUT_ISO" \
  "$ISO_DIR" \
  2>&1

[[ -f "$OUTPUT_ISO" ]] || die "xorriso failed — nexus.iso not created"

ok "BUILD COMPLETE!"
echo ""
echo "  ISO    : $OUTPUT_ISO"
echo "  Size   : $(du -sh $OUTPUT_ISO | cut -f1)"
echo "  SHA256 : $(sha256sum $OUTPUT_ISO | cut -d' ' -f1)"
echo ""
echo "  Flash  : sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress"
