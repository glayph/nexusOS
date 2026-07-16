# Chapter 7: Live System Configuration

A live system runs entirely from the ISO — nothing is installed to a hard drive. The `live-boot` and `live-config` packages handle this.

## How Live Boot Works

1. The kernel boots with `boot=live` parameter
2. Initramfs detects the ISO media (CD, USB, or loopback)
3. It mounts the ISO and finds `live/filesystem.squashfs`
4. The squashfs is mounted read-only
5. An overlay (tmpfs) is created on top for writable access
6. systemd starts, using the merged root

```
                ┌──────────────────────┐
                │  / (overlay mount)    │
                │  ├─ tmpfs (writable)  │
                │  └─ squashfs (ro)     │
                └──────────────────────┘
```

## Required Packages

| Package | Purpose |
|---|---|
| `live-boot` | Scripts to detect and mount the live media |
| `live-boot-initramfs-tools` | Integration with initramfs-tools |
| `live-config` | Auto-configures the live session (hostname, network, locale) |
| `live-config-systemd` | systemd integration for live-config |

## Rebuilding Initramfs

After installing live-boot packages, rebuild the initramfs so it includes the live-boot scripts:

```bash
update-initramfs -u -k all
```

This generates `/boot/initrd.img-$(uname -r)` with live-boot integration.

## Problem: Initramfs Missing After Build

**Issue**: The initramfs step completes but no `initrd.img-*` file is created in `/boot`.

**Fixes**:
1. Remove pipe masking: avoid `| tail -3` after `update-initramfs`:
   ```bash
   # Bad: failure is hidden
   chroot "$ROOTFS" update-initramfs -u -k all 2>&1 | tail -3
   
   # Good: failure is caught
   chroot "$ROOTFS" /bin/bash -c "update-initramfs -u -k all" 2>&1 || die "Initramfs rebuild failed"
   ```
2. Make sure `/dev/pts` is mounted inside the chroot (see Chapter 3).
3. Check that `initramfs-tools` is installed in the rootfs.

## Problem: Live Boot Fails with "Unable to find live filesystem"

**Issue**: The ISO boots but fails to detect the live system.

**Fixes**:
1. Verify the ISO structure has `live/filesystem.squashfs`
2. Check the kernel command line includes `boot=live components`
3. Ensure the ISO label matches the GRUB search:
   ```bash
   search --no-floppy --label --set=root "NEXUS_OS_1_0"
   ```
   The label is set during ISO creation:
   ```bash
   grub-mkrescue ... -- -volid "NEXUS_OS_1_0"
   ```

## Kernel Parameters for Live Boot

| Parameter | Purpose |
|---|---|
| `boot=live` | Required — tells initramfs to use live-boot |
| `components` | Enables multi-component rootfs support |
| `quiet` | Reduces boot messages |
| `hostname=nexus` | Sets the system hostname |
| `username=root` | Sets the default user (live-config) |
| `noswap` | Prevents swap from being activated |
| `toram` | Copies the ISO to RAM at boot (faster, uses more RAM) |

## Customizing Boot Parameters

Edit `boot/grub/grub.cfg` to change kernel parameters:

```bash
linux /boot/vmlinuz boot=live components quiet hostname=nexus
initrd /boot/initrd.img
```

Different menu entries can have different parameters:

```bash
menuentry "Nexus OS" {
  linux /boot/vmlinuz boot=live components quiet hostname=nexus
  initrd /boot/initrd.img
}

menuentry "Nexus OS (RAM mode)" {
  linux /boot/vmlinuz boot=live components toram hostname=nexus
  initrd /boot/initrd.img
}
```
