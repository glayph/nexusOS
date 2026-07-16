# Chapter 10: Creating a Setup Tool

A live distribution needs a way for users to configure their system without editing files manually. This chapter covers building an interactive setup tool using `whiptail`.

## Why a Setup Tool?

- Users don't know what packages to install
- Installing firmware requires knowing the package names
- Setting up persistence requires multiple steps
- Creating a user requires knowing the commands

A TUI (Terminal User Interface) tool solves all these problems.

## Choosing a TUI Library

| Library | Package | Size | Features |
|---|---|---|---|
| **whiptail** | `whiptail` | ~30 KB | Checkboxes, menus, input boxes, yes/no |
| **dialog** | `dialog` | ~200 KB | Richer UI, gauges, forms |
| **curses** (Python) | `python3` | Heavy | Full control, complex |
| **Bash only** | None | 0 KB | Limited, raw ANSI codes |

**whiptail** is the best choice for a minimal distribution — it's small, fast, and included in virtually every Linux distribution.

## Whiptail Basics

### Menu Selection (Arrow Keys + Enter)

```bash
whiptail --title "Title" --menu "Prompt" 20 60 4 \
  "1" "First option" \
  "2" "Second option" \
  "3" "Third option" \
  3>&1 1>&2 2>&3
```

The `3>&1 1>&2 2>&3` swaps stdout and stderr so `whiptail` output can be captured in a variable.

### Checklist (Multiple Selection)

```bash
choices=$(whiptail --title "Title" --checklist "Prompt" 20 60 4 \
  "1" "Option 1" ON \
  "2" "Option 2" OFF \
  3>&1 1>&2 2>&3)
```

Items with `ON` are pre-selected.

### Yes/No

```bash
if whiptail --title "Confirm" --yesno "Are you sure?" 10 60; then
  echo "User said yes"
fi
```

## Core Setup Functions

Wrap `whiptail` in helper functions for cleaner code:

```bash
menu() {
  whiptail --title "My Setup" --menu "$1" 20 60 "$2" "${@:3}" 3>&1 1>&2 2>&3
}

yesno() {
  whiptail --title "$1" --yesno "$2" 10 60
}

msg() {
  whiptail --title "$1" --msgbox "$2" 10 60
}

input() {
  whiptail --title "$1" --inputbox "$2" 10 60 3>&1 1>&2 2>&3
}
```

## The Main Menu Loop

```bash
main_menu() {
  while true; do
    sel=$(menu "Configure your system" 8 \
      "1" "Drivers & Hardware" \
      "2" "Desktop Environment" \
      "3" "Create User Account" \
      "4" "Setup Persistence" \
      "5" "Install ALL" \
      "6" "Exit")

    case "$sel" in
      1) drivers_menu ;;
      2) de_menu ;;
      3) create_user ;;
      4) persistence_setup ;;
      5) install_all ;;
      6) break ;;
    esac
  done
}
```

## Problem: whiptail Not Installed

**Issue**: The script fails with "whiptail: command not found".

**Fix**: Install `whiptail` in the build, or provide a fallback:

```bash
command -v whiptail >/dev/null || {
  echo "whiptail not found. Run: apt-get install whiptail"
  exit 1
}
```

Always include `whiptail` in your base packages.

## Problem: User Selection Conflicts with whiptail

**Issue**: You need to install packages but `whiptail` output conflicts with apt output on the terminal.

**Fix**: Run `whiptail` only for user interaction. Use `apt-get` in the background with output redirected:

```bash
msg "Installing" "This may take a few minutes..."
apt-get install -y --no-install-recommends xfce4 2>&1 | tail -5
msg "Done" "Installation complete."
```

## Example: Drivers Menu

A checklist lets users toggle which drivers to install:

```bash
drivers_menu() {
  choices=$(whiptail --title "Drivers" --checklist "Select:" 16 60 4 \
    "1" "Audio (ALSA + PulseAudio)" ON \
    "2" "GPU (mesa + vulkan)" OFF \
    "3" "Wi-Fi firmware" OFF \
    3>&1 1>&2 2>&3)

  [[ -z "$choices" ]] && return

  local install=""
  [[ "$choices" == *"1"* ]] && install+=" alsa-utils pulseaudio"
  [[ "$choices" == *"2"* ]] && install+=" mesa-utils mesa-vulkan-drivers"
  [[ "$choices" == *"3"* ]] && install+=" firmware-iwlwifi"

  if [[ -n "$install" ]]; then
    msg "Installing" "Installing selected drivers..."
    apt-get install -y --no-install-recommends $install
    msg "Done" "Drivers installed."
  fi
}
```

## Security Considerations

- Run the setup tool as root (`sudo nexus-setup`)
- Validate user input (especially usernames)
- Don't display passwords in clear text (use `--passwordbox` for sensitive input)
- Clean up any cached credentials after setup
