# Chapter 4: Package Selection and Management

After bootstrapping, you have a minimal system with just `apt`, `bash`, and `coreutils`. Now you need to decide what additional packages to install.

## The Critical Rule

> Use `--no-install-recommends`. Always.

Without this flag, `apt` installs "recommended" packages, which pull in recommended packages of their own, and so on. A simple `apt install xorg` balloons to 1 GB. With `--no-install-recommends`, you get only what you asked for.

## Choosing Packages

### The Minimal CLI Set

```bash
apt-get install -y --no-install-recommends \
  linux-image-virtual \    # Kernel
  systemd systemd-sysv \   # Init system
  util-linux \             # Basic tools
  procps \                 # Process management
  nano \                   # Editor
  apt                      # Package manager
```

This gives you a bootable system with a shell prompt. That's it.

### Adding Networking

```bash
  iproute2 \               # ip, ss (modern net tools)
  iputils-ping \           # ping
  curl \                   # HTTP transfers
  ca-certificates          # SSL certificates
```

### Adding Usability

```bash
  less \                   # File pager
  file \                   # File type detection
  tree \                   # Directory tree
  unzip zip bzip2 xz-utils \ # Archive tools
  psmisc \                 # killall, pstree
  sudo \                   # Sudo (even as root)
  bash-completion          # Tab completion
  command-not-found        # Package suggestions
  man-db                   # Manual pages
  tmux                     # Terminal multiplexer
```

### Adding Audio (ALSA + PulseAudio)

```bash
  alsa-utils \             # alsamixer, aplay
  pulseaudio               # Sound server
```

### Adding Wi-Fi and Bluetooth

```bash
  wireless-tools \         # iwconfig
  wpasupplicant \          # WPA authentication
  iw \                     # Modern Wi-Fi CLI
  bluez bluez-tools        # Bluetooth stack
```

### Adding X Server (Minimal)

```bash
  xserver-xorg-core \      # X server
  xserver-xorg-input-all \ # Input drivers
  xserver-xorg-video-fbdev \  # Framebuffer video
  xserver-xorg-video-vesa \   # VESA video
  xserver-xorg-video-modesetting \  # Modesetting video
  xinit \                  # startx command
  openbox \                # Minimal window manager
  xterm                    # Terminal for X
```

## Problem: Package Not Found

**Issue**:
```
E: Unable to locate package wpa_supplicant
```

**Fix**: Check the correct package name on your base distribution:

| Wrong name | Correct name |
|---|---|
| `wpa_supplicant` | `wpasupplicant` |
| `alsa` | `alsa-utils` |
| `bluetooth` | `bluez` |

Always check: `apt search <keyword>` before adding a package to your list.

## Problem: Package Names Differ Between Distributions

**Issue**: A package name on Ubuntu may differ on Debian.

**Examples**:
- `linux-image-virtual` (Ubuntu) → `linux-image-cloud-amd64` (Debian)
- `systemd-sysv` (Ubuntu) → not needed separately on Debian
- `live-config-systemd` (Ubuntu) → `live-config` (Debian)

**Fix**: Build on the same distribution as your target. If your ISO targets Ubuntu, build on Ubuntu.

## Problem: Pipe Masking Apt Failures

**Issue**: Commands like this silently swallow errors:
```bash
apt-get install ... 2>&1 | grep -E '^(Setting up|E:)' | head -30
```

If `apt-get install` fails, the pipe returns the exit code of `head` (success), not `apt-get` (failure). The build continues with a broken rootfs.

**Fix**: Either remove the pipe entirely or add proper error handling:

```bash
apt-get install ... 2>&1 || die "Package installation failed"
```

Or use `set -e` inside the chroot block so any failure stops execution.

## Problem: Dependency Hell

**Issue**: Some packages pull in enormous dependency chains even with `--no-install-recommends`.

**Examples**:
- `ubuntu-gnome-desktop` → ~800 MB
- `firmware-misc-nonfree` → ~50 MB
- `kde-plasma-desktop` → ~600 MB

**Fix**: Keep heavy packages optional. Install them at runtime via a setup script (like `nexus-setup`), not in the base ISO.

## Aggressive Post-Install Cleanup

After installing all packages, remove unnecessary files to minimize ISO size:

```bash
apt-get clean
apt-get autoremove -y --purge
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/locale/*
rm -rf /var/log/*.log

# Aggressive: remove UI assets not needed in CLI
rm -rf /usr/share/icons/*
rm -rf /usr/share/themes/*
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/applications/*
rm -rf /usr/share/pixmaps/*
rm -rf /usr/share/help/*

# Remove static libraries (not needed at runtime)
find /usr/lib -name '*.a' -o -name '*.la' | xargs rm -f

# Disable unnecessary timers
systemctl disable fstrim.timer apt-daily.timer apt-daily-upgrade.timer
```

This can save **80-100 MB** from the final ISO.
