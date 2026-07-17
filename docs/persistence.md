# Persistence

## Problem

A live ISO boots from a read-only squashfs filesystem. Any changes made during a session — installed packages, modified configs, created files — are lost on reboot.

## Solution: Overlay Persistence

`taja-setup` offers option 5 to create a persistent overlay. It works by:

1. Creating a **512 MB ext4 loopback file** (`/persist.img`) on the boot drive
2. Mounting it at `/mnt/persist`
3. Using an **overlay filesystem** to merge the read-only squashfs with a writable upper layer

## How It Works

```
Filesystem layout:
/                   ← read-only squashfs (lower)
/mnt/persist/upper  ← writable (persistent changes)
/mnt/persist/work   ← overlay workdir
```

The `overlay` mount combines these into a single view at `/mnt/overlay`.

## Systemd Service

A `persist-overlay.service` runs at boot:

```bash
# Start: creates a snapshot directory and mounts overlay
/usr/bin/persist-overlay

# Stop: saves current state
/usr/bin/persist-overlay stop
```

## Limitations

- **Single overlay file**: `/persist.img` on the root of the boot device
- **Fixed size**: 512 MB (cannot grow without manual resizing)
- **No snapshots** by default: the service is WIP and may need manual setup
- **No encryption**: data is stored in plain ext4

## Manual Persistence (Alternative)

For full control, create a persistent partition manually:

```bash
# On the USB: create a second partition labelled "persistence"
# Add to casper boot: persistence persistence-label=persistence
```

This requires rebuilding the ISO with the `persistence` kernel parameter and is not currently supported in `taja-setup`.
