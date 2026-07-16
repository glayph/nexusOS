# X Server Setup

## Philosophy

The ISO ships with a minimal X server — enough to run `startx` and launch a terminal or lightweight GUI, but without the full metapackage that pulls in dozens of video drivers for hardware that won't be present.

## Installed Components

- **xserver-xorg-core** — The X.org display server binary
- **xserver-xorg-input-all** — Input drivers for keyboard, mouse, touchpad, joystick
- **xserver-xorg-video-fbdev** — Generic framebuffer driver (works everywhere)
- **xserver-xorg-video-vesa** — VESA BIOS driver (works in all BIOS/CSM VMs)
- **xserver-xorg-video-modesetting** — Modern kernel modesetting driver (preferred)
- **openbox** — Minimal stacking window manager
- **xinit** — The `startx` command
- **xterm** — Basic terminal emulator

## How to Launch

```bash
startx
```

This reads `~/.xinitrc` and starts Openbox with xterm.

If you install a desktop via `nexus-setup`, `.xinitrc` is automatically updated:

```bash
# After installing XFCE:
startx            # launches XFCE
```

## Display Manager

A display manager (LightDM, GDM, SDDM) is **not** pre-installed. Install it via `nexus-setup` if you want the GUI to start automatically on boot.

Without a display manager, the system boots to a root shell — exactly like a server. Run `startx` to start the GUI manually.

## Video Driver Selection

The modesetting driver is tried first. If it fails, X falls back to fbdev, then VESA. This covers:
- QEMU/KVM (virtio-gpu + bochs-drm)
- VirtualBox (vboxvideo)
- VMware (vmwgfx)
- Physical hardware with basic UEFI framebuffer

For proprietary NVIDIA/AMD drivers, install via `nexus-setup → Drivers → GPU`.
