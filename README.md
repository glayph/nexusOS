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

*Boot directly into an AI agent powered by Anthropic Claude*

[![Build](https://github.com/glayph/nexusOS/actions/workflows/build.yml/badge.svg)](https://github.com/glayph/nexusOS/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/glayph/nexusOS)](https://github.com/glayph/nexusOS/releases)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

</div>

---

## 📥 Download

Go to **[Releases](../../releases)** and download `nexus.iso`.

Or **build from source** (see below ↓)

---

## ⚡ Quick Start

```bash
# Flash to USB
sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress

# Test in QEMU
make qemu

# After boot — add your Anthropic API key
echo "sk-ant-..." | sudo tee /etc/nexus/api.key
```

---

## 🔨 Build From Source

### Linux / WSL (Ubuntu 22.04+)

```bash
# 1. Clone
git clone https://github.com/glayph/nexusOS.git
cd nexusOS

# 2. Install dependencies (once)
sudo bash install-deps.sh

# 3. Build
make build
# → nexus.iso তৈরি হবে (~1.9 GB, ~45 min)
```

### Windows

```batch
:: install-deps.bat ডাবল-ক্লিক করো
:: WSL automatically ব্যবহার করবে
install-deps.bat
```

তারপর:
```
wsl make build
```

### Build Options

```bash
make build          # Normal build
make build CLEAN=1  # Fresh build (rootfs মুছে নতুন করে)
make build FAST=1   # Skip squashfs (rootfs unchanged থাকলে)
make clean          # সব artifacts মুছে ফেলো
make flash DEV=/dev/sdX  # USB-তে flash করো
make qemu           # QEMU-তে test করো
```

---

## 🎨 Customize

`customize/` ফোল্ডারে গিয়ে নিজের মতো বানাও:

| ফাইল | কী করে |
|---|---|
| `customize/packages.list` | Extra packages যোগ করো |
| `customize/startup.sh` | Boot-এ custom script চালাও |
| `customize/agent-prompt.txt` | AI agent-এর behavior পরিবর্তন করো |
| `customize/motd.txt` | Welcome message পরিবর্তন করো |

```bash
# Customize করার পর rebuild
make build FAST=1
```

---

## 📁 Project Structure

```
nexusOS/
├── nexus-agent.py          ← AI Agent (Anthropic Claude)
├── makebuild.sh            ← Master build script
├── install-deps.sh         ← Linux dependency installer
├── install-deps.bat        ← Windows (WSL) installer
├── Makefile                ← Build system
├── boot/grub/grub.cfg      ← GRUB bootloader config
├── customize/
│   ├── packages.list       ← Add your packages
│   ├── startup.sh          ← Custom boot script
│   ├── agent-prompt.txt    ← AI personality
│   └── motd.txt            ← Welcome message
└── .github/workflows/
    └── build.yml           ← Auto-build on push
```

---

## 🔧 System Specs

| Item | Detail |
|---|---|
| Base OS | Ubuntu 24.04 Noble (minbase) |
| Kernel | Linux 6.8.x |
| Boot | BIOS (MBR) + UEFI (GPT) |
| Root FS | squashfs (zstd) |
| AI Agent | Anthropic claude-sonnet-4-6 |
| Auto-login | root → nexus agent (tty1) |

---

## 🤖 Nexus AI Agent

Boot হওয়ার পরে automatically `nexus` agent চালু হয়।

- **Online mode** (API key সহ): Full natural language system control
- **Offline mode** (API key ছাড়া): Direct shell commands

```
nexus> system status দেখাও
nexus> সব running process list করো
nexus> disk usage চেক করো
nexus> network configuration দেখাও
```

---

## 📋 Requirements

- Ubuntu 22.04+ (বা WSL2 on Windows)
- 20 GB+ free disk space
- 4 GB+ RAM
- Internet connection (debootstrap এর জন্য)

---

*Built with [Claude AI](https://anthropic.com)*
