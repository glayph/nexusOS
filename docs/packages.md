# Packages

## Rationale

Every package is chosen to minimize ISO size while providing a usable CLI experience with optional GUI support. All packages are installed with `--no-install-recommends` to avoid pulling in unnecessary dependencies.

## Core System

| Package | Purpose |
|---|---|
| `linux-image-virtual` | Minimal kernel, fewer modules, optimized for VMs |
| `initramfs-tools` | Initramfs generation |
| `live-boot` | Live ISO boot scripts |
| `live-boot-initramfs-tools` | live-boot integration with initramfs |
| `live-config` | Live session auto-configuration |
| `live-config-systemd` | systemd integration for live sessions |
| `bash`, `coreutils` | Shell and basic Unix tools |
| `systemd`, `systemd-sysv` | Init system |
| `util-linux` | fdisk, mount, blkid, etc. |
| `procps` | ps, top, kill, uptime, free |
| `apt` | Package manager |

## Networking

| Package | Purpose |
|---|---|
| `iproute2` | `ip`, `ss`, `bridge` (modern net tools) |
| `iputils-ping` | `ping` |
| `net-tools` | `ifconfig`, `netstat`, `route` (legacy) |
| `dnsutils` | `dig`, `nslookup` |
| `curl` | HTTP transfers |
| `wget` | HTTP/FTP downloads |
| `openssh-client` | `ssh`, `scp` |
| `traceroute` | Network path tracing |
| `wireless-tools` | `iwconfig`, `iwlist` |
| `wpasupplicant` | Wi-Fi authentication (WPA/WPA2) |
| `iw` | Modern Wi-Fi configuration (`nl80211`) |

## Bluetooth

| Package | Purpose |
|---|---|
| `bluez` | Bluetooth daemon and utilities |
| `bluez-tools` | Bluetooth CLI tools |

## Audio

| Package | Purpose |
|---|---|
| `alsa-utils` | ALSA sound system utilities |
| `pulseaudio` | PulseAudio sound server |

## X Server (Minimal)

Replaces the full `xorg` metapackage with only what's needed:

| Package | Purpose |
|---|---|
| `xserver-xorg-core` | The X.org display server |
| `xserver-xorg-input-all` | All input drivers (keyboard, mouse, touchpad) |
| `xserver-xorg-video-fbdev` | Framebuffer video driver |
| `xserver-xorg-video-vesa` | VESA driver (works in all VMs) |
| `xserver-xorg-video-modesetting` | Modern kernel modesetting driver |
| `xinit` | `startx` command to launch X |
| `openbox` | Minimal window manager |
| `xterm` | Terminal emulator for X |

## Utilities

| Package | Purpose |
|---|---|
| `nano` | Text editor |
| `less` | Pager |
| `file` | File type detection |
| `tree` | Directory tree viewer |
| `unzip`, `zip`, `bzip2`, `xz-utils` | Archive tools |
| `psmisc` | `killall`, `pstree`, `fuser` |
| `pciutils` | `lspci` |
| `usbutils` | `lsusb` |
| `lsb-release` | `lsb_release` |
| `sudo` | Privilege escalation |
| `man-db` | Man pages |
| `tmux` | Terminal multiplexer |
| `whiptail` | TUI menus for `nexus-setup` |
| `bash-completion` | Tab completion |
| `command-not-found` | Package suggestions for unknown commands |
| `ca-certificates` | SSL/TLS certificates |

## Not Included (available via `nexus-setup`)

- **Desktop environments**: XFCE, MATE, GNOME, KDE
- **Display managers**: LightDM, GDM, SDDM
- **GPU firmware**: `firmware-misc-nonfree` (~50 MB)
- **Wi-Fi firmware**: `firmware-iwlwifi`, `firmware-realtek`, `firmware-brcm80211`
