# Chapter 14: Optimization: Reducing ISO Size

A small ISO downloads faster, boots quicker, and uses less storage. This chapter covers techniques to minimize your distribution's footprint.

## The Size Budget

Here's where the space goes in a typical live ISO:

| Component | Size | Notes |
|---|---|---|
| Kernel + modules | ~70 MB | After stripping (was ~200 MB) |
| X.org server + libs | ~35 MB | Minimal drivers only |
| Mesa + Vulkan | ~40 MB | Optional (excluded from base) |
| systemd + udev | ~20 MB | Hard to reduce |
| coreutils + bash | ~10 MB | Essential |
| Network tools | ~15 MB | Essential |
| Audio (ALSA + PulseAudio) | ~12 MB | Essential |
| BlueZ + Bluetooth tools | ~5 MB | Essential |
| Firmware packages | ~50 MB | Made optional |
| **Total** | **~257 MB** | Current Nexus OS ISO |

## Compression Techniques

### Squashfs Compression

The biggest factor in ISO size is squashfs compression:

```bash
# Best compression (slowest build)
mksquashfs rootfs filesystem.squashfs -comp xz -Xbcj x86 -b 1M

# Faster compression
mksquashfs rootfs filesystem.squashfs -comp zstd -b 1M
```

| Compressor | ISO Size | Build Time | Decompression |
|---|---|---|---|
| xz | **Smallest** | Slowest (~30 min) | Medium |
| zstd | -5% | Fast (~5 min) | Fast |
| gzip | -15% | Fastest (~3 min) | Fast |
| lz4 | -20% | Fast | Fastest |

Trade-off: better compression means longer build times but smaller downloads.

### Exclude Unnecessary Files

Exclude directories from squashfs that are already in the ISO root:

```bash
mksquashfs rootfs filesystem.squashfs -e boot
```

The `/boot` directory contains the kernel and initramfs, which are already at `iso/boot/`. Excluding them saves ~60 MB.

## Package Reduction

### Remove with --no-install-recommends

Always use `--no-install-recommends`:

```bash
# Bad: pulls in 500 MB of dependencies
apt-get install xorg

# Good: only what you asked for
apt-get install --no-install-recommends xserver-xorg-core
```

### Audit Every Package

For each package you add, ask:
1. Is it needed at boot time?
2. Can the user install it later?
3. Is there a lighter alternative?

| Heavy Package | Lighter Alternative | Savings |
|---|---|---|
| `xorg` (metapackage) | `xserver-xorg-core` + specific drivers | ~170 MB |
| `firmware-misc-nonfree` | Install at runtime via setup tool | ~50 MB |
| `ubuntu-gnome-desktop` | Offer via setup tool | ~800 MB |
| `firefox` | Install at runtime | ~150 MB |
| `python3` | Omit if no Python scripts | ~30 MB |

## Post-Install Cleanup

Run these commands after all packages are installed:

```bash
# APT cleanup
apt-get clean
apt-get autoremove -y --purge
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb

# Documentation (not needed in live session)
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/lintian/*

# Locales (keep only needed ones)
rm -rf /usr/share/locale/*

# Logs
rm -rf /var/log/*.log

# GUI assets (not needed in CLI)
rm -rf /usr/share/icons/*
rm -rf /usr/share/themes/*
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/applications/*
rm -rf /usr/share/pixmaps/*
rm -rf /usr/share/help/*

# Static libraries (not needed at runtime)
find /usr/lib -name '*.a' -o -name '*.la' | xargs rm -f

# Python bytecode cache
find /usr -name '*.pyc' -o -name '*.pyo' | xargs rm -f
```

## Kernel Module Stripping

See Chapter 5. Removing unnecessary kernel modules saves **~60-70 MB** without affecting functionality for most users.

## Binary Stripping

For advanced size reduction, strip debug symbols from binaries:

```bash
# Find and strip all ELF binaries
find /usr/bin /usr/sbin /usr/lib -type f -executable \
  -exec strip --strip-all {} \; 2>/dev/null || true

find /usr/lib -name '*.so*' -type f \
  -exec strip --strip-unneeded {} \; 2>/dev/null || true
```

This can save **~20-30 MB** but may make debugging harder (no core file symbols).

## Problem: Stripping Breaks Something

**Issue**: After aggressive stripping, some programs fail to run.

**Fix**: Only strip with `--strip-all` for binaries and `--strip-unneeded` for shared libraries. Never use `--strip-all` on `.so` files (it will break them). Test thoroughly after stripping.

## Compare and Track

Compare your ISO size after each optimization:

```bash
# Before optimization: 279 MB
# After minimal X server: 265 MB
# After removing firmware: 258 MB  
# After cleanup: 245 MB
# After kernel stripping: 135 MB (if starting from full)
```

Nexus OS started at **~280 MB** (with the xorg metapackage and firmware) and was optimized to **~258 MB** by:
1. Replacing the xorg metapackage with individual xserver packages (-14 MB)
2. Removing firmware from the base ISO (-50 MB, made optional)
3. Aggressive cleanup of UI assets and static libs (-8 MB)
