<div align="center">

```
███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝ ██╔═══██╗██╔════╝
██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║ ██║   ██║╚════██║
██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║
╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝  ╚═════╝ ╚══════╝
```

**Nexus OS — Agentic AI Linux Distribution**

*Boot directly into an AI-powered shell, driven by Anthropic Claude*

[![Build](https://github.com/glayph/nexusOS/actions/workflows/build.yml/badge.svg)](https://github.com/glayph/nexusOS/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/glayph/nexusOS?color=cyan)](https://github.com/glayph/nexusOS/releases/latest)
[![ISO Size](https://img.shields.io/badge/ISO%20size-135%20MB-brightgreen)](https://github.com/glayph/nexusOS/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

</div>

---

## 📥 Download

**[→ Latest Release: nexus.iso (135 MB)](https://github.com/glayph/nexusOS/releases/latest)**

```bash
# Flash to USB
sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress && sync

# Or test in QEMU
make qemu
```

After boot, set your Anthropic API key:
```bash
echo "sk-ant-..." | sudo tee /etc/nexus/api.key
```

---

## ⚡ What is Nexus OS?

Nexus OS is a minimal bootable Linux distribution that boots directly into an AI agent shell powered by **Anthropic Claude**. Instead of a traditional desktop, you get a natural language interface with full root-level control over the system.

```
nexus> system status দেখাও
nexus> list all running processes
nexus> check disk usage
nexus> scan network interfaces
nexus> install python3-numpy
```

- **Online mode** (with API key) → Full natural language AI control
- **Offline mode** (no API key) → Direct shell with built-in commands

---

## 🔨 Build From Source

### Requirements
- Ubuntu 22.04+ or Debian 12+ (or WSL2 on Windows)
- 10 GB free disk space
- 2 GB RAM minimum
- Internet connection

### Linux / WSL

```bash
# 1. Clone the repo
git clone https://github.com/glayph/nexusOS.git
cd nexusOS

# 2. Install dependencies (run once)
sudo bash install-deps.sh

# 3. Build
make build
```

### Windows

```batch
:: Step 1 — Double-click install-deps.bat
:: Step 2 — Open a WSL terminal:
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
| `customize/agent-prompt.txt` | Change AI agent personality |
| `customize/motd.txt` | Change the welcome message |

```bash
# Example: add git and docker
echo "git" >> customize/packages.list
echo "docker.io" >> customize/packages.list

# Rebuild (keeps rootfs, only repackages)
make build FAST=1
```

---

## 📁 Project Structure

```
nexusOS/
├── nexus-agent.py              ← AI Agent source (Anthropic Claude)
├── makebuild.sh                ← Master build script
├── install-deps.sh             ← Linux dependency installer (one-click)
├── install-deps.bat            ← Windows WSL installer (double-click)
├── Makefile                    ← Build system (make build / clean / flash)
├── boot/
│   └── grub/
│       └── grub.cfg            ← GRUB bootloader config
├── customize/
│   ├── packages.list           ← Extra packages to install
│   ├── startup.sh              ← Custom boot-time script
│   ├── agent-prompt.txt        ← AI personality config
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
| AI Agent | Anthropic `claude-sonnet-4-6` |
| Auto-login | root → nexus agent (tty1) |
| ISO Size | ~135 MB |

---

## 🤖 Nexus AI Agent

On boot, the system auto-logs in as root and launches the NEXUS AI agent on `tty1`.

The agent can:
- Monitor and manage system resources (CPU, RAM, disk, network)
- Execute shell commands from natural language
- Install and configure software
- Manage files, processes, and services
- Respond to security events

**API Key Setup:**
```bash
# Option 1: Environment variable (session only)
export ANTHROPIC_API_KEY="sk-ant-..."

# Option 2: Persistent (survives reboot)
echo "sk-ant-..." > /etc/nexus/api.key
```

---

## 📋 System Requirements

| Item | Minimum |
|---|---|
| RAM | 512 MB (1 GB recommended) |
| Storage | USB 256 MB+ or VM disk |
| CPU | x86_64 (64-bit) |
| Boot | BIOS or UEFI |

---

## 🛠 Troubleshooting

**GRUB says `file /boot/vmlinuz not found`**
→ Re-flash the ISO. The USB may not have been written correctly.
```bash
sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress && sync
```

**Nexus agent says `Offline mode`**
→ API key not set. Add it after boot:
```bash
echo "sk-ant-..." > /etc/nexus/api.key
```

**Build fails on squashfs step**
→ Run with `--clean` to start fresh:
```bash
make build CLEAN=1
```

---

*Built with [Claude AI](https://anthropic.com) · [Releases](../../releases) · [Issues](../../issues)*
