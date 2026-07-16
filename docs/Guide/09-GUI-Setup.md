# Chapter 9: Display Server and GUI Setup

This chapter covers adding graphical capabilities to your distribution — from a minimal X server to a full desktop environment.

## Choosing a Display Server

| Server | Pros | Cons |
|---|---|---|
| **X.org** | Standard, compatible with everything | Old architecture, heavy |
| **Wayland** | Modern, secure, simpler | Less compatible, `live-boot` issues |
| **None** | Smallest ISO, best for servers | No GUI at all |

Nexus OS uses **X.org** because of its universal compatibility and support for `startx`.

## Minimal X Server Installation

Instead of the `xorg` metapackage (which pulls in everything), install only what's needed:

```bash
apt-get install -y --no-install-recommends \
  xserver-xorg-core \            # The X server
  xserver-xorg-input-all \       # All input drivers
  xserver-xorg-video-fbdev \     # Framebuffer (fallback)
  xserver-xorg-video-vesa \      # VESA (works in VMs)
  xserver-xorg-video-modesetting \ # Modern (preferred)
  xinit                          # startx command
```

This is about **30 MB** vs **200 MB** for the full `xorg` metapackage.

## Window Manager or Desktop Environment

### Lightweight Options

| WM/DE | Size | RAM | Features |
|---|---|---|---|
| **Openbox** | ~2 MB | ~50 MB | Stacking WM, minimal, fast |
| **Fluxbox** | ~3 MB | ~60 MB | Tabbed windows, configurable |
| **i3** | ~2 MB | ~40 MB | Tiling WM, keyboard-driven |
| **XFCE** | ~50 MB | ~200 MB | Full desktop, lightweight |
| **LXQt** | ~40 MB | ~150 MB | Qt-based, modern |

### Heavy Options

| WM/DE | Size | RAM | Notes |
|---|---|---|---|
| **MATE** | ~150 MB | ~400 MB | GNOME 2 fork |
| **GNOME** | ~400 MB | ~1 GB | Modern, resource-heavy |
| **KDE Plasma** | ~400 MB | ~800 MB | Feature-rich, Qt-based |

### Recommendation

For a live ISO, use **Openbox** in the base (minimal, functional) and offer full DEs via a setup tool.

## Setting Up .xinitrc

The `~/.xinitrc` file is read by `startx` to determine what to launch:

```bash
# Minimal: just a terminal
exec xterm

# With Openbox:
exec openbox-session

# With XFCE:
exec startxfce4

# With MATE:
exec mate-session
```

Nexus OS creates `.xinitrc` automatically when a DE is installed via `nexus-setup`.

## Display Manager

A display manager (DM) starts X automatically at boot and provides a graphical login:

```bash
apt-get install lightdm lightdm-gtk-greeter
systemctl enable lightdm
```

| DM | Size | Best for |
|---|---|---|
| **LightDM** | ~5 MB | Lightweight, any DE |
| **GDM** | ~15 MB | GNOME |
| **SDDM** | ~10 MB | KDE Plasma |

**Without a DM**, the system boots to the shell. Run `startx` to start the GUI.

## Problem: Xorg Fails with "No screens found"

**Issue**: `startx` fails, Xorg log shows no screens.

**Fixes**:
1. Check if kernel modesetting is working:
   ```bash
   dmesg | grep drm
   ls /sys/class/drm/
   ```
2. Try different video drivers:
   ```bash
   # Force modesetting
   startx -- -logverbose 3
   ```
3. Ensure `drivers/gpu/drm` kernel modules weren't stripped.

## Problem: Openbox Starts But No Cursor

**Issue**: Openbox launches but there's no mouse cursor visible.

**Fix**: Install a cursor theme or use the built-in X cursor:
```bash
xsetroot -cursor_name left_ptr
```

Or install a cursor theme:
```bash
apt-get install --no-install-recommends dmz-cursor-theme
```

## Problem: GUI Applications Don't Start as Root

Some applications (Chrome, Brave, Chromium) refuse to run as root:

```bash
# Error: cannot run as root
brave-browser

# Fix: create a user and run as that user
useradd -m user
su - user -c "brave-browser"
```

Or use the `--no-sandbox` flag (not recommended for security):
```bash
brave-browser --no-sandbox
```

## Problem: No Sound in GUI

**Issue**: PulseAudio doesn't work when running GUI apps.

**Fix**: PulseAudio runs per-user. Start the PulseAudio server:
```bash
pulseaudio --start
```

Or create a non-root user — PulseAudio automatically starts for normal user sessions.
