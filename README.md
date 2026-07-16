<div align="center">

```
███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝ ██╔═══██╗██╔════╝
██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║ ██║   ██║╚════██║
██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║
╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝  ╚═════╝ ╚══════╝
```

**Nexus OS — Minimal Live Linux Distribution**

[![Build](https://github.com/glayph/nexusOS/actions/workflows/build.yml/badge.svg)](https://github.com/glayph/nexusOS/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/glayph/nexusOS?color=cyan)](https://github.com/glayph/nexusOS/releases/latest)
[![ISO Size](https://img.shields.io/badge/ISO%20size-280%20MB-brightgreen)](https://github.com/glayph/nexusOS/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

</div>

---

## 📥 Download

**[→ Latest Release: nexus.iso (280 MB)](https://github.com/glayph/nexusOS/releases/latest)**

```bash
# Flash to USB
sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress && sync

# Or test in QEMU
make qemu
```

---

## ⚡ What is Nexus OS?

A minimal bootable Linux distribution based on Ubuntu 24.04 Noble. Boots directly into a clean CLI shell with pre-installed drivers and a setup utility for installing desktops, drivers, and persistence.

```
nexus> apt update && apt upgrade
nexus> top
nexus> ifconfig
nexus> startx
```

---

## 🔧 Setup Tool

After boot, run:

```bash
nexus-setup
```

Navigate with arrow keys to:

| Option | What it does |
|---|---|
| **Drivers** | Install/uninstall audio, GPU, Wi-Fi firmware, kernel modules |
| **Desktop** | Install XFCE, MATE, GNOME, or KDE Plasma |
| **Display Manager** | LightDM, GDM, or SDDM (auto-start GUI on boot) |
| **User Account** | Create a sudo user |
| **Persistence** | Save changes across reboots |
| **Install ALL** | Full desktop setup in one command |
| **Uninstall** | Remove installed drivers cleanly |

---

## 🔨 Build From Source

### Requirements
- Ubuntu 22.04+ or Debian 12+ (or WSL2 on Windows)
- 10 GB free disk space
- 2 GB RAM minimum
- Internet connection

### Linux / WSL

```bash
git clone https://github.com/glayph/nexusOS.git
cd nexusOS
sudo bash install-deps.sh
make build
```

### Windows

```batch
:: Double-click install-deps.bat, then:
wsl make build
```

### Build Options

| Command | What it does |
|---|---|
| `make build` | Normal build |
| `make build CLEAN=1` | Fresh build (delete existing rootfs) |
| `make build FAST=1` | Skip squashfs rebuild (fast re-pack) |
| `make clean` | Remove all build artifacts |
| `make flash DEV=/dev/sdX` | Flash ISO to USB drive |
| `make qemu` | Boot ISO in QEMU (for testing) |
| `make install` | Install build dependencies |

---

## 🎨 Customize

Edit files inside `customize/` before building:

| File | Purpose |
|---|---|
| `customize/packages.list` | Add extra apt packages |
| `customize/startup.sh` | Run commands on every boot |
| `customize/motd.txt` | Change the welcome message |

```bash
echo "git" >> customize/packages.list
make build FAST=1
```

---

## 📁 Project Structure

```
nexusOS/
├── nexus-setup.sh              ← Interactive setup TUI (arrow-key menu)
├── makebuild.sh                ← Master build script
├── install-deps.sh             ← Linux dependency installer
├── install-deps.bat            ← Windows WSL installer
├── Makefile                    ← Build system (make build / clean / flash)
├── boot/
│   └── grub/
│       └── grub.cfg            ← GRUB bootloader config
├── customize/
│   ├── packages.list           ← Extra packages to install
│   ├── startup.sh              ← Custom boot-time script
│   ├── motd.txt                ← Welcome message
│   └── README.md               ← Customization guide
└── .github/
    └── workflows/
        └── build.yml           ← Auto-build & release on push
```

---

## 🔧 Tech Stack

| Component | Detail |
|---|---|
| Base OS | Ubuntu 24.04 Noble (minbase) |
| Kernel | Linux `linux-image-virtual` |
| Boot | BIOS (MBR) + UEFI (GPT) |
| Bootloader | GRUB 2 |
| Root FS | squashfs (XZ compressed) |
| Live system | live-boot + live-config |
| Auto-login | root shell on tty1 |
| Pre-installed | ALSA, PulseAudio, BlueZ, Wi-Fi tools |
| Setup tool | `nexus-setup` — TUI with arrow-key navigation |
| ISO Size | ~280 MB |

---

## 📋 System Requirements

| Item | Minimum |
|---|---|
| RAM | 512 MB (2 GB for desktop) |
| Storage | USB 512 MB+ or VM disk |
| CPU | x86_64 (64-bit) |
| Boot | BIOS or UEFI |

---

## 🛠 Troubleshooting

**GRUB says `file /boot/vmlinuz not found`**
→ Re-flash the ISO. The USB may not have been written correctly.
```bash
sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress && sync
```

**Build fails on squashfs step**
→ Run with `--clean` to start fresh:
```bash
make build CLEAN=1
```

**GUI apps won't start**
→ Xorg may not have initialized. Run:
```bash
startx
```

---

[Releases](../../releases) · [Issues](../../issues)
