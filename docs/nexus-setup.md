# `nexus-setup` — Interactive Setup TUI

## Overview

`nexus-setup` is a terminal user interface written in Bash using `whiptail`. It runs after boot and lets users configure their system with arrow-key navigation.

## Main Menu

```
┌──────────────────────────────────────┐
│  1. Drivers & Hardware               │
│  2. Desktop Environment              │
│  3. Display Manager                  │
│  4. Create User Account              │
│  5. Setup Persistence                │
│  6. Install ALL — Full Desktop       │
│  7. Uninstall Drivers & Rollback     │
│  8. Exit                             │
└──────────────────────────────────────┘
```

## Option Details

### 1. Drivers & Hardware
Checklist to toggle installation/removal:
- **Audio** (alsa-utils, pulseaudio) — ON by default (pre-installed)
- **GPU** (mesa, vulkan, X.org video drivers)
- **Wi-Fi firmware** (iwlwifi, realtek, brcm)
- **Firmware** (firmware-misc-nonfree — ~50 MB)
- **Remove ALL pre-installed drivers** — purges audio, wifi, and bluetooth
- **Re-install kernel** — restores stripped kernel modules

### 2. Desktop Environment
Radio select:
- **XFCE** — Lightweight (recommended for low RAM)
- **MATE** — Traditional desktop
- **GNOME** — Heavy, modern
- **KDE Plasma** — Heavy, feature-rich

### 3. Display Manager
Radio select for automatic GUI startup:
- **LightDM** — Lightweight (recommended)
- **GDM** — GNOME's display manager
- **SDDM** — KDE's display manager

### 4. Create User Account
Prompts for username and password. Creates a sudo-capable user.

### 5. Setup Persistence
Creates a 512 MB overlay file (`/persist.img`) on the boot drive and installs a systemd service to mount it. Changes survive reboots.

### 6. Install ALL
One-command setup: GPU drivers + Wi-Fi firmware + XFCE + LightDM + user 'nexus' + persistence.

### 7. Uninstall Drivers
Checklist to remove any installed driver groups cleanly.

## Implementation

- **Language**: Bash
- **UI Library**: `whiptail` (from the `whiptail` package)
- **Location**: `/usr/bin/nexus-setup`
- **Config**: No config files — all state is ephemeral
