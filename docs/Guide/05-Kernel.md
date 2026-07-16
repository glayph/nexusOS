# Chapter 5: Kernel Configuration and Module Management

The Linux kernel is the largest single component of any distribution. The `linux-image-virtual` package for Ubuntu 24.04 ships with over **200 MB** of kernel modules — drivers for every conceivable piece of hardware. Most of them are unnecessary in a live ISO.

## Understanding Kernel Modules

Kernel modules are loadable drivers stored in `/lib/modules/$(uname -r)/kernel/`. They're organized by category:

```
/lib/modules/6.8.0-134-generic/kernel/
├── drivers/
│   ├── ata/          ← Storage (keep)
│   ├── bluetooth/    ← Bluetooth (keep for BT support)
│   ├── gpu/          ← GPUs (keep for Xorg)
│   ├── media/        ← TV tuners, webcams (can remove)
│   ├── net/          ← Networking (keep)
│   ├── sound/        ← Audio (keep)
│   ├── staging/      ← Experimental (can remove)
│   ├── infiniband/   ← HPC fabric (can remove)
│   ├── isdn/         ← Obsolete (can remove)
│   ├── atm/          ← Obsolete (can remove)
│   └── nfc/          ← NFC (can remove)
├── fs/               ← Filesystem drivers (keep)
├── net/              ← Network protocols (keep)
└── crypto/           ← Crypto modules (keep)
```

## What to Strip and What to Keep

### Safe to Remove (Major Space Savings)

| Directory | Size Saved | Reason |
|---|---|---|
| `drivers/media/*` | ~40 MB | TV tuners, webcams, video capture cards |
| `drivers/staging/*` | ~15 MB | Unstable, experimental drivers |
| `drivers/infiniband/*` | ~5 MB | High-performance computing only |
| `drivers/isdn/*` | ~2 MB | Obsolete dial-up networking |
| `drivers/atm/*` | ~1 MB | Obsolete ATM networking |
| `drivers/nfc/*` | ~1 MB | Near-field communication |
| `sound/` | ~10 MB | ⚠️ Remove only if you don't need audio |

**Total savings**: ~60-70 MB from driver removal alone.

### Must Keep

| Directory | Reason |
|---|---|
| `drivers/gpu/drm/*` | Required by X.org for any GPU acceleration |
| `drivers/net/*` | Required for networking (wired + wireless) |
| `drivers/usb/*` | USB keyboard, mouse, storage |
| `drivers/ata/*`, `drivers/scsi/*`, `drivers/nvme/*` | Storage controllers |
| `drivers/virtio/*` | VM acceleration (QEMU/KVM) |
| `fs/*` | Filesystem drivers (ext4, squashfs, overlay) |
| `sound/*` | Required for ALSA/PulseAudio audio |

## Problem: Removing Modules Breaks Hardware Support

**Issue**: After removing drivers/media, users with USB webcams can't use them.

**Solution**: Document what's removed and provide a way to restore:

```bash
# Restore all original modules
apt-get install --reinstall linux-image-virtual
```

Your setup tool (like `nexus-setup`) should offer this as an option.

## Problem: Removing GPU Modules Breaks Xorg

**Issue**: Removing `drivers/gpu/drm` causes Xorg to fail with "No screens found".

**Fix**: Never remove `drivers/gpu/drm` or `drivers/gpu/drm/*`. These are essential for any GPU-accelerated display.

## Problem: Removing Sound Modules Causes "No Sound"

**Issue**: After removing `sound/*`, ALSA reports no devices.

**Fix**: Keep `sound/*` in your cleanup. The size penalty is modest (~10 MB) compared to the value of having audio.

## Implementation

Here's the kernel module stripping code from `makebuild.sh`:

```bash
KVER=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 | sed 's/.*vmlinuz-//')
if [[ -n "$KVER" ]]; then
  cd /lib/modules/$KVER/kernel
  rm -rf drivers/media drivers/staging \
         drivers/infiniband \
         drivers/isdn drivers/atm drivers/nfc \
         2>/dev/null || true
  depmod -a $KVER 2>/dev/null || true
fi
```

After deletion, `depmod -a` is run to rebuild the module dependency database.

## Advanced: Custom Kernel

For maximum size reduction, compile a custom kernel with only the drivers you need. This can produce a kernel + modules under **50 MB** total, but requires:

- A kernel build environment (toolchain, headers)
- Understanding of kernel configuration (menuconfig)
- Ongoing maintenance for security updates

`linux-image-virtual` is a good compromise: it's relatively small, works everywhere, and receives automatic security updates via APT.

## Module Loading at Boot

Modules that are removed won't be auto-loaded. For kept modules, systemd/udev handles auto-loading based on detected hardware. The `depmod -a` command ensures the module dependency tree is consistent.
