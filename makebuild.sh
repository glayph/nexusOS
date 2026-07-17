#!/bin/bash
# ============================================================
#  NEXUS OS v1.1 — Master Build Script
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

log "Nexus OS v1.1 Build — Target: ~400MB ISO"

# ── Step 1: Clean ──────────────────────────────────────────
if $CLEAN; then
  warn "Removing existing rootfs..."
  rm -rf "$ROOTFS" "$ISO_DIR" core.img bios.img efiboot.img
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
log "Installing packages (v1.1 feature set)..."
chroot "$ROOTFS" /bin/bash -c "
  apt-get update -qq

  # Kernel: linux-image-virtual (small, no extra HW modules)
  # live-boot: squashfs as root on boot (critical)
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    linux-image-virtual initramfs-tools \
    live-boot live-boot-initramfs-tools \
    \
    python3 python3-requests \
    \
    bash bash-completion \
    coreutils util-linux procps psmisc \
    systemd systemd-sysv \
    \
    iproute2 iputils-ping net-tools \
    curl wget ca-certificates \
    dnsutils nmap \
    ufw \
    \
    tmux mc ncdu \
    nano vim-tiny \
    htop \
    git rsync \
    lm-sensors \
    \
    dialog whiptail \
    \
    2>&1 | grep -E '^(Setting up|E:)' | head -40
  echo root:nexus | chpasswd
  echo 'Packages installed.'
"
ok "Base packages done"

# ── Step 6: AGGRESSIVE driver removal ─────────────────────
log "Removing unnecessary kernel modules & files..."
chroot "$ROOTFS" /bin/bash -c "
  KVER=\$(ls /boot/vmlinuz-* | sort -V | tail -1 | sed 's/.*vmlinuz-//')
  echo \"Kernel: \$KVER\"
  cd /lib/modules/\$KVER/kernel

  # Remove unnecessary driver categories
  rm -rf drivers/media          2>/dev/null || true  # Video capture
  rm -rf drivers/staging        2>/dev/null || true  # Staging/experimental
  rm -rf drivers/gpu/drm        2>/dev/null || true  # GPU/DRM (VM has virtio)
  rm -rf drivers/bluetooth      2>/dev/null || true  # Bluetooth
  rm -rf drivers/infiniband     2>/dev/null || true  # InfiniBand
  rm -rf drivers/isdn           2>/dev/null || true  # ISDN
  rm -rf drivers/atm            2>/dev/null || true  # ATM networking
  rm -rf drivers/nfc            2>/dev/null || true  # NFC
  rm -rf drivers/iio            2>/dev/null || true  # Industrial I/O
  rm -rf drivers/w1             2>/dev/null || true  # 1-wire bus
  rm -rf drivers/hid            2>/dev/null || true  # HID (keyboard/mouse handled by VirtIO)
  rm -rf drivers/parport        2>/dev/null || true  # Parallel port
  rm -rf sound                  2>/dev/null || true  # Audio
  rm -rf net/wireless           2>/dev/null || true  # WiFi (add back if needed)
  rm -rf net/bluetooth          2>/dev/null || true  # Bluetooth networking

  depmod -a \$KVER 2>/dev/null || true
  echo 'Modules cleaned.'

  # Remove large unnecessary files
  apt-get clean
  apt-get autoremove -y --purge 2>/dev/null || true
  rm -rf /var/lib/apt/lists/*
  rm -rf /var/cache/apt/archives/*.deb
  rm -rf /usr/share/doc/*
  rm -rf /usr/share/man/*
  rm -rf /usr/share/locale/*
  rm -rf /usr/share/info/*
  rm -rf /var/log/*.log /var/log/*.gz /var/log/*.1
  rm -rf /tmp/*
  echo 'Cleanup done.'
"
ok "Driver removal and cleanup done"

# ── Step 7: Custom packages from packages.list ────────────
if [[ -f "$SCRIPT_DIR/customize/packages.list" ]]; then
  PKGS=$(grep -v '^\s*#' "$SCRIPT_DIR/customize/packages.list" | grep -v '^\s*$' | tr '\n' ' ')
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

# ── Step 8: Install Nexus OS framework ────────────────────
log "Installing Nexus OS v1.1 framework..."

# Directory structure
mkdir -p "$ROOTFS/opt/nexus/skills"
mkdir -p "$ROOTFS/opt/nexus/themes"
mkdir -p "$ROOTFS/etc/nexus"
mkdir -p "$ROOTFS/var/log/nexus"
mkdir -p "$ROOTFS/var/backups"

# Main agent
cp "$SCRIPT_DIR/nexus-agent.py" "$ROOTFS/usr/local/bin/nexus-agent.py"
chmod +x "$ROOTFS/usr/local/bin/nexus-agent.py"

# Skills
for f in "$SCRIPT_DIR/skills/"*.py; do
  [[ -f "$f" ]] && cp "$f" "$ROOTFS/opt/nexus/skills/"
done

# Utility scripts
for f in "$SCRIPT_DIR/bin/"*; do
  [[ -f "$f" ]] && cp "$f" "$ROOTFS/usr/local/bin/" && chmod +x "$ROOTFS/usr/local/bin/$(basename $f)"
done

# Config files
[[ -f "$SCRIPT_DIR/config/agent.conf"  ]] && cp "$SCRIPT_DIR/config/agent.conf"  "$ROOTFS/etc/nexus/"
[[ -f "$SCRIPT_DIR/config/config.conf" ]] && cp "$SCRIPT_DIR/config/config.conf" "$ROOTFS/etc/nexus/"
mkdir -p "$ROOTFS/etc/nexus/themes"
[[ -d "$SCRIPT_DIR/config/themes" ]] && cp -r "$SCRIPT_DIR/config/themes/". "$ROOTFS/etc/nexus/themes/"

# Nexus main launcher
cat > "$ROOTFS/usr/local/bin/nexus" << 'LAUNCHER'
#!/bin/bash
export TERM=linux
export PYTHONUNBUFFERED=1
[ -f /etc/nexus/api.key ] && export ANTHROPIC_API_KEY=$(cat /etc/nexus/api.key)
exec /usr/local/bin/nexus-agent.py "$@"
LAUNCHER
chmod +x "$ROOTFS/usr/local/bin/nexus"

# os doctor shortcut
ln -sf /usr/local/bin/nexus-doctor "$ROOTFS/usr/local/bin/os"
cat >> "$ROOTFS/usr/local/bin/os" << 'OSDOC' 2>/dev/null || true
OSDOC

# Bash completion for nexus commands
cat > "$ROOTFS/etc/bash_completion.d/nexus" << 'COMPLETION'
_nexus_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local cmds="status sysinfo help clear memory skills exit"
  COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
}
_nexuspkg_complete() {
  COMPREPLY=($(compgen -W "install remove search list update upgrade info clean autoremove" -- "${COMP_WORDS[COMP_CWORD]}"))
}
complete -F _nexus_complete nexus
complete -F _nexuspkg_complete nexus-pkg
COMPLETION

# Default tmux config
cat > "$ROOTFS/etc/tmux.conf" << 'TMUX'
set -g default-terminal "screen-256color"
set -g history-limit 5000
set -g mouse on
set -g status-style 'bg=colour234 fg=colour136'
set -g status-left '#[fg=colour69][nexus] '
set -g status-right '#[fg=colour136]%H:%M %d-%b'
bind | split-window -h
bind - split-window -v
bind r source-file /etc/tmux.conf
TMUX

# Customize files
[[ -f "$SCRIPT_DIR/customize/startup.sh"         ]] && cp "$SCRIPT_DIR/customize/startup.sh"       "$ROOTFS/etc/nexus/"
[[ -f "$SCRIPT_DIR/customize/agent-prompt.txt"   ]] && cp "$SCRIPT_DIR/customize/agent-prompt.txt" "$ROOTFS/etc/nexus/agent-prompt.txt"
[[ -f "$SCRIPT_DIR/customize/motd.txt"           ]] && cp "$SCRIPT_DIR/customize/motd.txt"         "$ROOTFS/etc/motd" || true

ok "Nexus OS framework installed"

# ── Step 9: System identity ───────────────────────────────
log "Configuring system identity..."
echo "nexus" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << 'HOSTS'
127.0.0.1   localhost
127.0.1.1   nexus
::1         localhost ip6-localhost ip6-loopback
HOSTS

cat > "$ROOTFS/etc/os-release" << OSREL
NAME="Nexus OS"
VERSION="1.1"
ID=nexus
ID_LIKE=ubuntu
PRETTY_NAME="Nexus OS 1.1 — Agentic AI Linux"
NEXUS_AGENT="claude-sonnet-4-6"
BUILD_DATE=$(date +%Y-%m-%d)
OSREL

# Set default MOTD if no custom one
if [[ ! -f "$SCRIPT_DIR/customize/motd.txt" ]]; then
  cat > "$ROOTFS/etc/motd" << 'MOTD'

  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║

  Nexus OS 1.1  |  'nexus' → AI agent  |  'nexus-doctor' → health check

MOTD
fi

# ── Step 10: Auto-login & auto-launch ─────────────────────
log "Configuring auto-login on tty1..."
mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
GETTY

cat > "$ROOTFS/root/.bash_profile" << 'PROFILE'
# Auto-launch Nexus agent on tty1
if [ "$(tty)" = "/dev/tty1" ]; then
  exec /usr/local/bin/nexus
fi
PROFILE

cat > "$ROOTFS/root/.bashrc" << 'BASHRC'
# Nexus OS .bashrc
source /etc/bash_completion 2>/dev/null || true
source /etc/bash_completion.d/nexus 2>/dev/null || true
export HISTSIZE=5000
export HISTFILESIZE=10000
alias ll='ls -lah'
alias la='ls -la'
alias cls='clear'
alias monitor='nexus-monitor'
alias health='nexus-doctor'
alias pkg='nexus-pkg'
alias skill='nexus-skill'
PS1='\[\033[96m\]nexus \[\033[92m\]\w\[\033[0m\] ❯ '
BASHRC

# ── Step 11: Rebuild initramfs with live-boot ─────────────
log "Rebuilding initramfs with live-boot support..."
chroot "$ROOTFS" update-initramfs -u -k all 2>&1 | tail -3
ok "Initramfs rebuilt"

umount "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" 2>/dev/null || true
trap - EXIT

# ── Step 12: ISO structure ────────────────────────────────
log "Building ISO structure..."
mkdir -p "$ISO_DIR/boot/grub" "$ISO_DIR/EFI/boot" "$ISO_DIR/live"

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 | sed 's/.*vmlinuz-//')
[[ -z "$KVER" ]] && die "No kernel found in $ROOTFS/boot/"
log "Kernel: $KVER"

cp "$ROOTFS/boot/vmlinuz-${KVER}"    "$ISO_DIR/boot/vmlinuz"
cp "$ROOTFS/boot/initrd.img-${KVER}" "$ISO_DIR/boot/initrd.img"
cp "$SCRIPT_DIR/boot/grub/grub.cfg"  "$ISO_DIR/boot/grub/grub.cfg"

# ── Step 13: Squashfs with XZ ─────────────────────────────
if ! $NO_SQUASH; then
  log "Creating squashfs (XZ compression)..."
  mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" \
    -comp xz -Xbcj x86 -b 1M \
    -e boot -noappend \
    2>&1 | tail -3
  ok "Squashfs: $(du -sh $ISO_DIR/live/filesystem.squashfs | cut -f1)"
else
  warn "Skipping squashfs (--no-squash)"
fi

# ── Step 14: GRUB bootloaders ────────────────────────────
log "Building GRUB bootloaders..."
grub-mkstandalone --format=x86_64-efi \
  --output="$ISO_DIR/EFI/boot/bootx64.efi" \
  --locales="" --fonts="" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

grub-mkstandalone --format=i386-pc \
  --output="$SCRIPT_DIR/core.img" \
  --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
  --modules="linux normal iso9660 biosdisk search" \
  --locales="" --fonts="" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img "$SCRIPT_DIR/core.img" > "$SCRIPT_DIR/bios.img"
dd if=/dev/zero of="$SCRIPT_DIR/efiboot.img" bs=1M count=4 status=none
mkfs.fat -F12 "$SCRIPT_DIR/efiboot.img"
mmd   -i "$SCRIPT_DIR/efiboot.img" ::/EFI ::/EFI/boot
mcopy -i "$SCRIPT_DIR/efiboot.img" "$ISO_DIR/EFI/boot/bootx64.efi" ::/EFI/boot/
cp "$SCRIPT_DIR/bios.img" "$SCRIPT_DIR/efiboot.img" "$ISO_DIR/"
ok "Bootloaders ready"

# ── Step 15: Build ISO ───────────────────────────────────
log "Building nexus.iso v1.1..."
xorriso -as mkisofs \
  -iso-level 3 \
  -volid "NEXUS_OS_1_1" \
  -appid "Nexus OS 1.1 Agentic AI Linux" \
  -publisher "Nexus AI Project" \
  -b bios.img -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e efiboot.img -no-emul-boot \
  --protective-msdos-label \
  -append_partition 2 0xef "$SCRIPT_DIR/efiboot.img" \
  -o "$OUTPUT_ISO" \
  "$ISO_DIR"

echo ""
ok "BUILD COMPLETE — Nexus OS v1.1"
echo ""
echo "  ISO    : $OUTPUT_ISO"
echo "  Size   : $(du -sh $OUTPUT_ISO | cut -f1)"
echo "  SHA256 : $(sha256sum $OUTPUT_ISO | cut -d' ' -f1)"
echo ""
echo "  Flash  : dd if=nexus.iso of=/dev/sdX bs=4M status=progress"
echo "  VM     : make qemu"
