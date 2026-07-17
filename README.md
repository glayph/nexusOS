<div align="center">

```
████████╗ █████╗      ██╗ █████╗      ██████╗ ███████╗
╚══██╔══╝██╔══██╗     ██║██╔══██╗    ██╔═══██╗██╔════╝
   ██║   ███████║     ██║███████║    ██║   ██║███████╗
   ██║   ██╔══██║██   ██║██╔══██║    ██║   ██║╚════██║
   ██║   ██║  ██║╚█████╔╝██║  ██║    ╚██████╔╝███████║
   ╚═╝   ╚═╝  ╚═╝ ╚════╝ ╚═╝  ╚═╝     ╚═════╝ ╚══════╝
```

**TajaOS v2.0 — CLI-Based Operating System**

[![Build](https://github.com/glayph/nexusOS/actions/workflows/build.yml/badge.svg)](https://github.com/glayph/nexusOS/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/glayph/nexusOS?color=cyan)](https://github.com/glayph/nexusOS/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

</div>

---

## 📥 Download

**[→ Latest Release: tajaos.iso (280 MB)](https://github.com/glayph/nexusOS/releases/latest)**

```bash
# Flash to USB
sudo dd if=tajaos.iso of=/dev/sdX bs=4M status=progress && sync

# Or test in QEMU
make qemu
```

---

## ⚡ What is TajaOS?

A minimal bootable Linux distribution based on Ubuntu 24.04 Noble. Boots directly into a clean CLI shell with the complete **TajaOS** system management toolkit.

```
os doctor          # System health check
os net wifi        # Wi-Fi scan & connect
os svc list        # List services
os pkg install     # Install packages
os monitor         # Live system dashboard
os ai chat         # Local LLM chat
os sec vault       # Encrypted vault
```

---

## 🏗 System Architecture

```
os                            # Unified command interface
├── tajados-core              # Config system & profiles
├── tajanet                   # Network manager (Wi-Fi, eth, VPN, DNS, proxy, firewall)
├── tajainit                  # Service manager & boot optimization
├── tajahook                  # Event hook system & triggers
├── tajapkg                   # Package manager with offline cache
├── tajadev                   # Developer tools (containers, VMs, templates)
├── tajaai                    # Local LLM & AI toolkit
├── tajasec                   # Security (vault, hardening, audit, tamper detect)
├── tajados-persist           # Persistence manager & snapshots
├── tajamon                   # System monitoring dashboard
├── tajashell                 # TUI shell with keyboard navigation
├── tajarecover               # Recovery tools & boot repair
├── tajamedia                 # Media tools (OCR, QR, screen record, benchmarks)
├── tajabuild                 # ISO build & release pipeline
└── taja-setup                # Interactive setup TUI
```

---

## 🔧 Quick Start

After boot:

```bash
os doctor                      # Check system health
os net wifi connect MyWiFi     # Connect to Wi-Fi
os setup                       # Run setup wizard
os persist create              # Enable persistence (save changes)
os config set core.hostname mybox  # Set hostname
os shell                       # Launch TUI shell menu
```

---

## 🎨 Features

| Category | Commands |
|---|---|
| **System** | `os doctor`, `os config`, `os profile`, `os init` |
| **Shell** | `os shell`, `os history`, `os session-save/load` |
| **Network** | `os net`, `os wifi`, `os speed`, `os diag`, `os fw` |
| **Services** | `os svc`, `os health`, `os boot-analyze` |
| **Storage** | `os persist`, `os snapshot`, `os vault`, `os trash` |
| **Packages** | `os pkg install/remove/search/update`, `os update` |
| **Dev** | `os dev`, `os container`, `os vm`, `os monitor` |
| **Security** | `os sec`, `os harden`, `os audit` |
| **AI** | `os ai`, `os chat`, `os codegen` |
| **Recovery** | `os recover`, `os boot-repair`, `os rollback` |
| **Media** | `os media`, `os record`, `os qr` |
| **Build** | `os build`, `os release`, `os ota` |

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

---

## 🎨 Customize

Edit files inside `customize/` before building:

| File | Purpose |
|---|---|
| `customize/packages.list` | Add extra apt packages |
| `customize/startup.sh` | Run commands on every boot |
| `customize/motd.txt` | Change the welcome message |
| `customize/taja*.sh` | TajaOS system modules |

```bash
echo "git" >> customize/packages.list
make build FAST=1
```

---

## 📁 Project Structure

```
tajaOS/
├── taja-setup.sh               ← Interactive setup TUI
├── makebuild.sh                ← Master build script
├── install-deps.sh             ← Linux dependency installer
├── install-deps.bat            ← Windows WSL installer
├── Makefile                    ← Build system
├── boot/grub/grub.cfg          ← GRUB bootloader config
├── customize/
│   ├── tajaos.sh               ← Main TajaOS command
│   ├── tajados-core.sh         ← Config & profile system
│   ├── tajanet.sh              ← Network manager
│   ├── tajainit.sh             ← Service manager
│   ├── tajahook.sh             ← Hook system
│   ├── tajapkg.sh              ← Package manager
│   ├── tajadev.sh              ← Developer toolkit
│   ├── tajaai.sh               ← AI toolkit
│   ├── tajasec.sh              ← Security toolkit
│   ├── tajados-persist.sh      ← Persistence manager
│   ├── tajamon.sh              ← System monitor
│   ├── tajashell.sh            ← TUI shell
│   ├── tajarecover.sh          ← Recovery tools
│   ├── tajamedia.sh            ← Media tools
│   ├── tajabuild.sh            ← Build pipeline
│   ├── packages.list           ← Extra apt packages
│   ├── startup.sh              ← Boot-time script
│   ├── motd.txt                ← Welcome message
│   └── README.md               ← Customization guide
└── .github/workflows/build.yml ← Auto-build & release
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
| TajaOS Shell | 'os' unified CLI with TUI |
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
sudo dd if=tajaos.iso of=/dev/sdX bs=4M status=progress && sync
```

**Build fails on squashfs step**
→ Run with `--clean` to start fresh:
```bash
make build CLEAN=1
```

**TajaOS command not found**
→ Modules are installed during build in `/usr/local/lib/tajados/`

---

[Releases](../../releases) · [Issues](../../issues)
