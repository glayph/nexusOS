# Chapter 1: System Requirements

Building a Linux distribution is not a lightweight task. The build process downloads packages, compiles (if needed), creates filesystem images, and compresses them. Here's what you need.

## Hardware Requirements

| Item | Minimum | Recommended | Notes |
|---|---|---|---|
| CPU | Any x86_64 | 4+ cores | `debootstrap` and `mksquashfs` are CPU-bound |
| RAM | 2 GB | 4+ GB | Squashfs compression uses significant memory |
| Disk space | 10 GB | 20 GB | Rootfs + squashfs + ISO staging |
| OS | Linux (Ubuntu/Debian) | Ubuntu 24.04 | `debootstrap` and `xorriso` are Linux-native |

## Software Requirements

### Essential Tools

| Tool | Package | Purpose |
|---|---|---|
| `debootstrap` | `debootstrap` | Creates a minimal Debian/Ubuntu filesystem |
| `mksquashfs` | `squashfs-tools` | Compresses the rootfs into a read-only image |
| `grub-mkrescue` | `grub-common` + grub-{pc,efi}-bin | Creates a bootable ISO |
| `xorriso` | `xorriso` | ISO manipulation (used by grub-mkrescue) |
| `mkfs.fat` | `dosfstools` | FAT filesystem for UEFI boot |
| `mmd` / `mcopy` | `mtools` | UEFI FAT partition management |

### Optional But Useful

| Tool | Package | Purpose |
|---|---|---|
| `wget`, `curl` | `wget`, `curl` | Downloading additional files |
| `git` | `git` | Version control |
| `make` | `make` | Build automation |
| `python3` | `python3` | For custom scripts and tools |

### Platform Support

| Platform | Support | Notes |
|---|---|---|
| Ubuntu 22.04+ | Full | Native, best support |
| Debian 12+ | Full | Near-identical to Ubuntu |
| WSL2 (Windows) | Full | Install Ubuntu via WSL, build inside it |
| Fedora/RHEL | Partial | Uses `dnf` instead of `apt`, some tools differ |
| macOS | None | `debootstrap` and `grub-mkrescue` are Linux-only |
| Native Windows | None | Use WSL2 |

## Knowledge Requirements

You should be comfortable with:

- **Bash scripting**: variables, functions, conditionals, loops
- **Linux command line**: apt, filesystem navigation, permissions
- **Chroot environments**: what they are and how they work
- **Basic GRUB knowledge**: kernel parameters, boot process
- **Systemd**: basic unit files and service management

## Problem: You're Building on WSL2

**Issue**: WSL2 may not have all required kernel modules or loop device support.

**Fix**: Ensure your WSL2 kernel supports loop devices and squashfs:

```bash
sudo modprobe loop
sudo modprobe squashfs
# If modules aren't available, update WSL2 kernel
wsl --update
```

## Problem: Insufficient Disk Space

**Issue**: The build can consume 5-10 GB during the process.

**Fix**: Check available space before starting:

```bash
df -h /
# Need at least 10 GB free
```

If space is tight, clean as you go:
- Delete the rootfs after building the squashfs
- Use `make clean` to remove build artifacts
- Build on an external drive with more space

## Problem: Missing Tools

**Issue**: Commands like `grub-mkrescue` or `xorriso` are not found.

**Fix**: The Nexus OS `install-deps.sh` script handles this:

```bash
sudo bash install-deps.sh
```

This installs all required tools in one command. See the script for a complete list.
