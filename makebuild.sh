#!/bin/bash
# ============================================================
#  NEXUS OS — Build Script v2 (grub-mkrescue fix)
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

log "Nexus OS Build v2 — grub-mkrescue edition"
log "Output: $OUTPUT_ISO"

# ── Preflight checks ──────────────────────────────────────
for cmd in debootstrap mksquashfs grub-mkrescue xorriso; do
  command -v "$cmd" &>/dev/null || die "Missing tool: $cmd — run: sudo bash install-deps.sh"
done
ok "Preflight checks passed"

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
mountpoint -q "$ROOTFS/dev/pts" || mount --bind /dev/pts "$ROOTFS/dev/pts" 2>/dev/null || true
trap "umount '$ROOTFS/proc' '$ROOTFS/sys' '$ROOTFS/dev' 2>/dev/null; umount '$ROOTFS/dev/pts' 2>/dev/null; true" EXIT

# ── Step 5: Install packages ───────────────────────────────
log "Installing packages..."
chroot "$ROOTFS" /bin/bash -c "
  set -e
  apt-get update -qq

  # linux-image-virtual = smaller kernel, fewer unnecessary modules
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    linux-image-virtual \
    initramfs-tools \
    live-boot \
    live-boot-initramfs-tools \
    live-config \
    live-config-systemd \
    bash \
    coreutils \
    systemd \
    systemd-sysv \
    util-linux \
    procps \
    iproute2 \
    iputils-ping \
    nano \
    apt \
    curl \
    ca-certificates \
    bash-completion \
    command-not-found \
    less \
    file \
    tree \
    unzip \
    xz-utils \
    bzip2 \
    zip \
    psmisc \
    net-tools \
    dnsutils \
    wget \
    openssh-client \
    traceroute \
    pciutils \
    usbutils \
    lsb-release \
    sudo \
    man-db \
    tmux \
    xserver-xorg-core \
    xserver-xorg-input-all \
    xserver-xorg-video-fbdev \
    xserver-xorg-video-vesa \
    xserver-xorg-video-modesetting \
    openbox \
    xinit \
    xterm \
    whiptail \
    alsa-utils \
    pulseaudio \
    wireless-tools \
    iw \
    wpasupplicant \
    bluez \
    bluez-tools \
    2>&1

  echo root:nexus | chpasswd

  # Clean to save space
  apt-get clean
  apt-get autoremove -y --purge 2>/dev/null || true
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*
  rm -rf /var/log/*.log /var/log/*.gz

  # Remove unused kernel modules (saves ~200MB)
  KVER=\$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 | sed 's/.*vmlinuz-//')
  if [[ -n \"\$KVER\" ]]; then
    cd /lib/modules/\$KVER/kernel
    rm -rf drivers/media drivers/staging \
           drivers/infiniband \
           drivers/isdn drivers/atm drivers/nfc \
           2>/dev/null || true
    depmod -a \$KVER 2>/dev/null || true
  fi

  # Aggressive cleanup (shrinks ISO by ~80-100MB)
  rm -rf /usr/share/icons/* /usr/share/themes/* /usr/share/backgrounds/* 2>/dev/null
  rm -rf /usr/share/applications/* /usr/share/pixmaps/* /usr/share/help/* 2>/dev/null
  rm -rf /usr/share/info/* /usr/share/groff/* /usr/share/bug/* 2>/dev/null
  rm -rf /usr/share/lintian/* /usr/share/perl/* /usr/share/zoneinfo/* 2>/dev/null
  find /usr/share -name '*.pdf' -o -name '*.html' -o -name '*.pyc' -o -name '*.pyo' | xargs rm -f 2>/dev/null || true
  find /usr/lib -name '*.a' -o -name '*.la' | xargs rm -f 2>/dev/null || true
  rm -rf /etc/apt/apt.conf.d/*dpkg* /var/cache/debconf/* 2>/dev/null || true

  # Disable unnecessary systemd services (faster boot)
  systemctl disable systemd-resolved systemd-timesyncd fstrim.timer \
    apt-daily.timer apt-daily-upgrade.timer \
    man-db.timer systemd-networkd-wait-online 2>/dev/null || true
  systemctl mask systemd-journald-audit.socket dev-hugepages.mount \
    sys-kernel-debug.mount 2>/dev/null || true

  # Compress initramfs with xz (smaller = faster to load)
  echo "COMPRESS=xz" >> /etc/initramfs-tools/initramfs.conf

  # Reduce systemd journal size limit
  echo "SystemMaxUse=10M" >> /etc/systemd/journald.conf 2>/dev/null
  echo "SystemMaxFileSize=5M" >> /etc/systemd/journald.conf 2>/dev/null
  sed -i 's/^#ForwardToSyslog=yes/ForwardToSyslog=no/' /etc/systemd/journald.conf 2>/dev/null || true

  echo '[NEXUS] Packages installed and cleaned'
"
ok "Packages done"

# ── Step 6: Custom packages ────────────────────────────────
if [[ -f "$SCRIPT_DIR/customize/packages.list" ]]; then
  PKGS=$(grep -v '^\s*#' "$SCRIPT_DIR/customize/packages.list" \
       | grep -v '^\s*$' | tr '\n' ' ')
  if [[ -n "$PKGS" ]]; then
    log "Installing custom packages: $PKGS"
    chroot "$ROOTFS" /bin/bash -c "
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PKGS \
        2>&1 | grep -E '^(Setting up|E:)' || true
      apt-get clean && rm -rf /var/lib/apt/lists/*
    "
  fi
fi

# ── Step 7: System identity ───────────────────────────────
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
PRETTY_NAME="Nexus OS 1.0"
BUILD_DATE=$(date +%Y-%m-%d)
OSREL

# Auto-login on tty1
mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
GETTY

# MOTD
if [[ -f "$SCRIPT_DIR/customize/motd.txt" ]]; then
  cp "$SCRIPT_DIR/customize/motd.txt" "$ROOTFS/etc/motd"
else
  cat > "$ROOTFS/etc/motd" << 'MOTD'
╭──────────────────────────────────────╮
│  nexus  •  System Shell             │
╰──────────────────────────────────────╯
MOTD
fi

# ── Step 8: Shell environment ────────────────────────────
log "Configuring shell..."
cat > "$ROOTFS/root/.bashrc" << 'BASHRC'
# ── prompt ──────────────────────────────────────────────
PS1='\[\033[96m\]\u@\h\[\033[0m\]:\[\033[97m\]\w\[\033[0m\]\$ '

# ── ls ──────────────────────────────────────────────────
eval "$(dircolors -b 2>/dev/null)"
alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -A'
alias l='ls -CF'

# ── utils ───────────────────────────────────────────────
alias grep='grep --color=auto'
alias h='history'
alias q='exit'
alias ..='cd ..'
alias cls='clear'
alias ip='ip -c'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias nano='nano -l'

# ── env ─────────────────────────────────────────────────
export EDITOR=nano

# ── completion ──────────────────────────────────────────
[ -f /usr/share/bash-completion/bash_completion ] && \
  . /usr/share/bash-completion/bash_completion
BASHRC

cp "$ROOTFS/root/.bashrc" "$ROOTFS/root/.bash_profile"

cat > "$ROOTFS/root/.inputrc" << 'INPUTRC'
set editing-mode emacs
set bell-style none
TAB: menu-complete
INPUTRC

# ── Step 9: Setup script ────────────────────────────────
log "Installing nexus-setup..."
cp "$SCRIPT_DIR/nexus-setup.sh" "$ROOTFS/usr/bin/nexus-setup"
chmod +x "$ROOTFS/usr/bin/nexus-setup"

# ── Step 10: Rebuild initramfs with live-boot ──────────────
log "Rebuilding initramfs..."
chroot "$ROOTFS" /bin/bash -c "update-initramfs -u -k all" 2>&1 || {
  warn "update-initramfs failed — checking /boot contents"
  ls -la "$ROOTFS/boot/" 2>/dev/null || true
  die "Initramfs rebuild failed"
}
ok "Initramfs rebuilt"

# Unmount
umount "$ROOTFS/dev/pts" 2>/dev/null || true
umount "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" 2>/dev/null || true
trap - EXIT

# ── Step 11: ISO directory structure ─────────────────────
log "Creating ISO structure..."
mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/live"

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 \
       | sed 's/.*vmlinuz-//')
[[ -z "$KVER" ]] && die "No kernel found in $ROOTFS/boot/"
log "Kernel: linux-$KVER"

cp "$ROOTFS/boot/vmlinuz-${KVER}"    "$ISO_DIR/boot/vmlinuz"
cp "$ROOTFS/boot/initrd.img-${KVER}" "$ISO_DIR/boot/initrd.img"
cp "$SCRIPT_DIR/boot/grub/grub.cfg"  "$ISO_DIR/boot/grub/grub.cfg"

# ── Step 12: Squashfs root filesystem ─────────────────────
if ! $NO_SQUASH; then
  log "Creating squashfs (XZ, ~20-40 min)..."
  mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" \
    -comp xz \
    -Xbcj x86 \
    -b 1M \
    -e boot \
    -noappend \
    2>&1 | tail -3
  ok "Squashfs: $(du -sh $ISO_DIR/live/filesystem.squashfs | cut -f1)"
else
  warn "Skipping squashfs rebuild (--no-squash)"
  [[ ! -f "$ISO_DIR/live/filesystem.squashfs" ]] && \
    die "No squashfs found! Run without --no-squash first."
fi

# ── Step 11: Build ISO with grub-mkrescue ─────────────────
# grub-mkrescue automatically:
#   - embeds GRUB modules (fixes echo.mod / chain.mod not found)
#   - creates BIOS El Torito boot record
#   - creates UEFI boot partition
#   - no manual bios.img / efiboot.img needed
command -v grub-mkrescue >/dev/null 2>&1 || die "grub-mkrescue not found! Run: sudo apt-get install grub-common"
log "Building nexus.iso with grub-mkrescue..."
grub-mkrescue \
  --output="$OUTPUT_ISO" \
  "$ISO_DIR" \
  -- \
  -volid  "NEXUS_OS_1_0" \
  -application_id "Nexus OS 1.0" \
  -publisher "Nexus Project" \
  2>&1 || die "grub-mkrescue failed"

# ── Done ─────────────────────────────────────────────────
echo ""
ok "BUILD COMPLETE!"
echo ""
echo "  ISO    : $OUTPUT_ISO"
echo "  Size   : $(du -sh $OUTPUT_ISO | cut -f1)"
echo "  SHA256 : $(sha256sum $OUTPUT_ISO | cut -d' ' -f1)"
echo ""
echo "  Flash  : sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress"
echo "  QEMU   : make qemu"
