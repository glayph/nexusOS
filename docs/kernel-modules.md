# Kernel Modules

The kernel (`linux-image-virtual`) ships with thousands of modules for every possible hardware configuration. Most are unnecessary in a live ISO and can be removed to save ~200 MB.

## What Gets Removed

| Category | Modules Removed | Reason |
|---|---|---|
| Media | `drivers/media/*` | TV tuners, webcams, video capture |
| Staging | `drivers/staging/*` | Unstable/experimental drivers |
| InfiniBand | `drivers/infiniband/*` | High-performance computing fabric |
| ISDN | `drivers/isdn/*` | Obsolete phone networking |
| ATM | `drivers/atm/*` | Obsolete networking |
| NFC | `drivers/nfc/*` | Near-field communication |

## What Is Kept

| Category | Reason |
|---|---|
| `drivers/gpu/drm/*` | Required by X.org for GPU acceleration |
| `sound/*` | Required by ALSA/PulseAudio for audio |
| `drivers/bluetooth/*` | Required by BlueZ for Bluetooth |
| `drivers/net/wireless/*` | Required for Wi-Fi |
| `drivers/usb/*` | USB support (keyboard, mouse, storage) |
| `drivers/ata/*`, `drivers/scsi/*`, `drivers/nvme/*` | Storage controllers |
| `drivers/virtio/*` | VM acceleration (QEMU/KVM) |
| `fs/*` | Filesystem drivers (ext4, vfat, squashfs, overlay) |

## Module Reinstallation

Since modules are physically deleted from the rootfs, they cannot be recovered without reinstalling the kernel package. The `nexus-setup` tool provides this option:

```
Drivers → Re-install kernel (restore modules)
```

This runs:
```bash
apt-get install --reinstall linux-image-virtual
```

And restores all stripped modules to their original state.
