# Build System — `makebuild.sh`

The entire ISO is built by a single Bash script: `makebuild.sh`. It runs in 11 sequential steps.

## Requirements

- Ubuntu 22.04+ or Debian 12+ (or WSL2 on Windows)
- Tools: `debootstrap`, `mksquashfs`, `grub-mkrescue`, `xorriso`
- Install via: `sudo bash install-deps.sh`

## Build Steps

### Step 1–3: Bootstrap

Uses `debootstrap --variant=minbase` to create a minimal Ubuntu 24.04 Noble root filesystem. Only essential packages (apt, bash, coreutils) are installed at this stage.

### Step 4: Mount virtual filesystems

Binds `/proc`, `/sys`, `/dev`, and `/dev/pts` into the chroot environment so `apt` and `update-initramfs` work correctly.

### Step 5: Install packages

Installs ~40 packages with `--no-install-recommends` to keep the install minimal. See [packages.md](packages.md) for the full list.

### Step 6: Custom packages

Reads `customize/packages.list` and installs any user-specified packages.

### Step 7: System identity

Sets hostname, hosts file, os-release, and configures `agetty` for auto-login as root on tty1.

### Step 8: Shell environment

Writes `.bashrc`, `.bash_profile`, and `.inputrc` for a clean Ubuntu/Kali-style terminal experience with colored prompt, ls colors, tab completion, and useful aliases.

### Step 9: Install `taja-setup`

Copies `taja-setup.sh` to `/usr/bin/taja-setup` — an interactive TUI for installing drivers, desktops, and persistence after boot.

### Step 10: Install AI Agent + Rebuild initramfs

Runs `update-initramfs -u -k all` to generate the initrd with live-boot support.

### Step 12: ISO structure + squashfs + grub-mkrescue

Creates the ISO directory layout, compresses the rootfs into `filesystem.squashfs` (XZ compression), and runs `grub-mkrescue` to produce a dual BIOS+UEFI bootable ISO.

## Build Options

| Flag | Effect |
|---|---|
| `--clean` | Delete existing rootfs and rebuild from scratch |
| `--no-squash` | Skip squashfs compression (re-packs ISO only) |
| `--output DIR` | Write `tajaos.iso` to a custom directory |

These are also exposed through the `Makefile`:

```bash
make build          # normal build
make build CLEAN=1  # fresh build
make build FAST=1   # skip squashfs
```
