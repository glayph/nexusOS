#!/bin/bash
# ============================================================
#  TAJAOS — Build Script v2 (grub-mkrescue fix)
#  Usage: sudo ./makebuild.sh [--clean] [--no-squash] [--output DIR]
# ============================================================
set -e

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[TAJAOS]${N} $*"; }
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
OUTPUT_ISO="$OUTPUT_DIR/tajaos.iso"

log "TajaOS Build v2 — grub-mkrescue edition"
log "Output: $OUTPUT_ISO"

# ── Preflight checks ──────────────────────────────────────
for cmd in debootstrap mksquashfs grub-mkrescue xorriso; do
  command -v "$cmd" &>/dev/null || die "Missing tool: $cmd — run: sudo bash install-deps.sh"
done
ok "Preflight checks passed"

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
mountpoint -q "$ROOTFS/dev/pts" || mount --bind /dev/pts "$ROOTFS/dev/pts" 2>/dev/null || true

tajaos_cleanup() {
  umount "$ROOTFS/dev/pts" 2>/dev/null || true
  umount "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" 2>/dev/null || true
}
trap tajaos_cleanup EXIT ERR

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
      whiptail \
      network-manager \
      rsync \
      jq \
      2>&1

  echo root:tajaos | chpasswd

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

  # Blacklist vmwgfx (VMware GPU driver — noisy on unsupported hypervisors)
  echo "blacklist vmwgfx" > /etc/modprobe.d/blacklist-vmwgfx.conf

  echo '[TAJAOS] Packages installed and cleaned'
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
echo "tajaos" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << 'HOSTS'
127.0.0.1   localhost
127.0.1.1   tajaos
::1         localhost ip6-localhost ip6-loopback
HOSTS

cat > "$ROOTFS/etc/os-release" << OSREL
NAME="TajaOS"
VERSION="2.0"
ID=tajaos
ID_LIKE=ubuntu
PRETTY_NAME="TajaOS 2.0"
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

# MOTD
if [[ -f "$SCRIPT_DIR/customize/motd.txt" ]]; then
  cp "$SCRIPT_DIR/customize/motd.txt" "$ROOTFS/etc/motd.custom"
else
  cat > "$ROOTFS/etc/motd.custom" << 'MOTD'
╭──────────────────────────────────────╮
│  TajaOS v2.0  •  Type 'os' for help │
╰──────────────────────────────────────╯
MOTD
fi
PROFILE

# Install custom startup script
if [[ -f "$SCRIPT_DIR/customize/startup.sh" ]]; then
  cp "$SCRIPT_DIR/customize/startup.sh" "$ROOTFS/tmp/startup.sh"
  chroot "$ROOTFS" /bin/bash -c "
    mkdir -p /usr/local/lib/tajados
    cp /tmp/startup.sh /usr/local/lib/tajados/startup.sh
    chmod +x /usr/local/lib/tajados/startup.sh

    cat > /etc/systemd/system/tajaos-startup.service << 'SVCE'
[Unit]
Description=TajaOS Custom Startup
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/lib/tajados/startup.sh

[Install]
WantedBy=multi-user.target
SVCE
    systemctl enable tajaos-startup.service 2>/dev/null || true
  "
fi

# ── Step 8: Shell environment ────────────────────────────
log "Configuring shell..."
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

cp "$ROOTFS/root/.bashrc" "$ROOTFS/root/.bash_profile"

cat > "$ROOTFS/root/.inputrc" << 'INPUTRC'
set editing-mode emacs
set bell-style none
TAB: menu-complete
INPUTRC

# Copy shell configs to /etc/skel for new users
mkdir -p "$ROOTFS/etc/skel"
cp "$ROOTFS/root/.bashrc" "$ROOTFS/etc/skel/"
cp "$ROOTFS/root/.bash_profile" "$ROOTFS/etc/skel/"
cp "$ROOTFS/root/.inputrc" "$ROOTFS/etc/skel/"

# ── Step 9: Setup script ────────────────────────────────
log "Installing nexus-setup..."
cp "$SCRIPT_DIR/nexus-setup.sh" "$ROOTFS/usr/bin/nexus-setup"
chmod +x "$ROOTFS/usr/bin/nexus-setup"

# ── Step 10: Install TajaOS System Modules ───────────────
log "Installing TajaOS system modules..."
for script in "$SCRIPT_DIR"/customize/taja*.sh; do
  [[ -f "$script" ]] || continue
  scriptname=$(basename "$script" .sh)
  cp "$script" "$ROOTFS/usr/local/lib/tajados/$scriptname"
  chmod +x "$ROOTFS/usr/local/lib/tajados/$scriptname"
  ok "Installed: $scriptname"
done

# Create symlinks for all TajaOS commands
chroot "$ROOTFS" /bin/bash -c "
  for f in /usr/local/lib/tajados/taja*.sh; do
    name=\$(basename \"\$f\" .sh)
    ln -sf \"\$f\" \"/usr/local/bin/\$name\" 2>/dev/null || true
  done
  # Main os command
  ln -sf /usr/local/lib/tajados/tajaos.sh /usr/local/bin/os 2>/dev/null || true
  # Core tajados command
  ln -sf /usr/local/lib/tajados/tajados-core.sh /usr/local/bin/tajados 2>/dev/null || true

  # Create TajaOS directory structure
  mkdir -p /usr/local/lib/tajados/{core,net,shell,dev,productivity,system,recovery,network,container,ai,security,media,build,hooks,triggers,services,enabled}
  mkdir -p /etc/tajados /var/lib/tajados /var/cache/tajados
  mkdir -p /opt/tajados/templates

  # Install motd (from customize or default)
  if [[ -f /etc/motd.custom ]]; then
    cp /etc/motd.custom /etc/motd 2>/dev/null || true
  fi

  # Enable bash completion for os command
  cat > /etc/bash_completion.d/os << 'COMP'
_os_completion() {
  local cur=\${COMP_WORDS[COMP_CWORD]}
  local cmds=\"doctor config profile init shell history session-save session-load net wifi speed diag svc health boot-analyze boot-optimize persist snapshot vault trash disk fm pkg update dev container vm logs monitor sec harden audit fw ai chat codegen recover boot-repair rollback factory-reset media record qr edit git clone build release ota tui setup shortcuts help-screen help version\"
  COMPREPLY=(\$(compgen -W \"\$cmds\" -- \"\$cur\"))
}
complete -F _os_completion os
COMP
" 2>&1
ok "TajaOS modules installed"

# ── Step 11: Rebuild initramfs with live-boot ──────────────
log "Rebuilding initramfs..."
chroot "$ROOTFS" /bin/bash -c "update-initramfs -u -k all" || {
  warn "update-initramfs failed — checking /boot contents"
  ls -la "$ROOTFS/boot/" 2>/dev/null || true
  die "Initramfs rebuild failed"
}
ok "Initramfs rebuilt"

# ── Step 12: ISO directory structure ─────────────────────
log "Creating ISO structure..."
mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/live"

# ── Step 12: ISO structure ────────────────────────────────
log "Building ISO structure..."
mkdir -p "$ISO_DIR/boot/grub" "$ISO_DIR/EFI/boot" "$ISO_DIR/live"

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 | sed 's/.*vmlinuz-//')
[[ -z "$KVER" ]] && die "No kernel found in $ROOTFS/boot/"
log "Kernel: $KVER"

cp "$ROOTFS/boot/vmlinuz-${KVER}"    "$ISO_DIR/boot/vmlinuz"
cp "$ROOTFS/boot/initrd.img-${KVER}" "$ISO_DIR/boot/initrd.img"
cp "$SCRIPT_DIR/boot/grub/grub.cfg"  "$ISO_DIR/boot/grub/grub.cfg"

# ── Step 13: Squashfs root filesystem ─────────────────────
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

# ── Step 14: Build ISO with grub-mkrescue ─────────────────
# grub-mkrescue automatically:
#   - embeds GRUB modules (fixes echo.mod / chain.mod not found)
#   - creates BIOS El Torito boot record
#   - creates UEFI boot partition
#   - no manual bios.img / efiboot.img needed
command -v grub-mkrescue >/dev/null 2>&1 || die "grub-mkrescue not found! Run: sudo apt-get install grub-common"
log "Building tajaos.iso with grub-mkrescue..."
grub-mkrescue \
  --output="$OUTPUT_ISO" \
  "$ISO_DIR" \
  -- \
  -volid  "TAJAOS_2_0" \
  -application_id "TajaOS 2.0" \
  -publisher "TajaOS Project" \
  || die "grub-mkrescue failed"

echo ""
ok "BUILD COMPLETE — Nexus OS v1.1"
echo ""
echo "  ISO    : $OUTPUT_ISO"
echo "  Size   : $(du -sh $OUTPUT_ISO | cut -f1)"
echo "  SHA256 : $(sha256sum $OUTPUT_ISO | cut -d' ' -f1)"
echo ""
echo "  Flash  : sudo dd if=tajaos.iso of=/dev/sdX bs=4M status=progress"
echo "  QEMU   : make qemu"
