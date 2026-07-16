# Chapter 8: Bootloader and ISO Generation

The final step in building a distribution is creating a bootable ISO. This chapter covers GRUB configuration, ISO structure, and the `grub-mkrescue` tool.

## ISO Structure

A minimal live ISO needs:

```
iso/
├── boot/
│   ├── vmlinuz          ← Linux kernel
│   ├── initrd.img       ← Initramfs
│   └── grub/
│       └── grub.cfg     ← GRUB configuration
└── live/
    └── filesystem.squashfs  ← Compressed rootfs
```

## Creating the Structure

```bash
mkdir -p iso/boot/grub
mkdir -p iso/live

# Copy kernel and initramfs
cp rootfs/boot/vmlinuz-*    iso/boot/vmlinuz
cp rootfs/boot/initrd.img-* iso/boot/initrd.img

# Copy GRUB config
cp boot/grub/grub.cfg iso/boot/grub/grub.cfg

# Create squashfs (excluding /boot to avoid duplication)
mksquashfs rootfs iso/live/filesystem.squashfs \
  -comp xz -Xbcj x86 -b 1M -e boot -noappend
```

## GRUB Configuration

Here's a minimal working `grub.cfg`:

```bash
set default=0
set timeout=5
set gfxmode=auto
set gfxpayload=keep

insmod all_video
insmod gfxterm
insmod iso9660
insmod search_label
insmod linux
insmod initrd

search --no-floppy --label --set=root "NEXUS_OS_1_0"

menuentry "My Linux" {
  linux /boot/vmlinuz boot=live components quiet hostname=myos
  initrd /boot/initrd.img
}
```

### Key Directives

| Directive | Purpose |
|---|---|
| `set default=0` | Boots the first menu entry by default |
| `set timeout=5` | Waits 5 seconds before booting |
| `set gfxmode=auto` | Uses native display resolution |
| `set gfxpayload=keep` | Passes the resolution to the kernel |
| `insmod linux` | Loads Linux boot support |
| `insmod iso9660` | Required for ISO filesystem access |
| `search --label` | Finds the ISO by volume label |

## Building the ISO with grub-mkrescue

The recommended tool for creating a bootable ISO is `grub-mkrescue`. It handles both BIOS and UEFI boot automatically.

```bash
grub-mkrescue \
  --output=my-distro.iso \
  iso/ \
  -- \
  -volid "MY_OS_1_0" \
  -application_id "My Linux 1.0" \
  -publisher "My Project"
```

Everything before `--` is for `grub-mkrescue`. Everything after `--` is passed to `xorriso`.

### Why grub-mkrescue?

| Method | BIOS | UEFI | Complexity |
|---|---|---|---|
| Manual `grub-install` + `xorriso` | Yes | Yes | High — requires creating FAT images, embedding core.img |
| **`grub-mkrescue`** | **Yes** | **Yes** | **Low — one command, everything auto-generates** |

`grub-mkrescue` automatically:
- Creates the El Torito boot record for BIOS
- Generates a FAT partition with GRUB EFI files for UEFI
- Embeds all required GRUB modules (fixing "module not found" errors)
- Calls `xorriso` to produce the final ISO

## Problem: "xorriso : FAILURE : Not a known command"

**Issue**: `grub-mkrescue` fails with:
```
xorriso : FAILURE : Not a known command: '-appid'
```

**Fix**: `-appid` is not a valid `xorriso` command. Use `-application_id` instead:

```bash
# Wrong
grub-mkrescue ... -- -appid "My OS"

# Correct
grub-mkrescue ... -- -application_id "My OS"
```

Similarly, use `-volid` (not `-volume`) and `-publisher`.

## Problem: "GRUB module not found" at Boot

**Issue**: When booting, GRUB says `file /boot/grub/<something>.mod not found`.

**Fix**: Use `grub-mkrescue` instead of manual `bios.img`/`efiboot.img` creation. `grub-mkrescue` dynamically includes all required modules based on your `grub.cfg`.

Also add explicit `insmod` directives in your `grub.cfg` for modules you need:

```bash
insmod all_video
insmod gfxterm
insmod echo
insmod chain
insmod part_msdos
insmod part_gpt
```

## Problem: ISO boots in BIOS but not UEFI

**Issue**: The ISO works on legacy BIOS systems but fails on UEFI.

**Fix**: Install `grub-efi-amd64-bin` and ensure `grub-mkrescue` can find the EFI files:

```bash
apt-get install grub-efi-amd64-bin mtools dosfstools
```

`grub-mkrescue` detects these packages and automatically includes UEFI support.

## Squashfs Compression Options

```bash
mksquashfs rootfs iso/live/filesystem.squashfs \
  -comp xz \          # Best compression (slowest)
  -Xbcj x86 \         # x86 branch/jump/call optimization
  -b 1M \             # Block size (1 MB — good balance)
  -e boot \           # Exclude /boot (already in ISO root)
  -noappend           # Create new, don't append to existing
```

| Compression | ISO Size | Build Time | Boot Speed |
|---|---|---|---|
| `gzip` | Largest | Fastest | Fast |
| `lzo` | Medium | Fast | Fastest (decompression) |
| `lz4` | Medium | Fastest | Fastest |
| `xz` | **Smallest** | Slowest | Medium |
| `zstd` | Small | Medium | Fast |

`xz` is the standard for live distributions. The ~20-40 minute build time is a one-time cost.

## Problem: Squashfs Build Takes Too Long

**Issue**: `mksquashfs` with XZ compression takes 20-40 minutes.

**Fixes**:
1. Use `FAST=1` during development to skip squashfs and quickly re-test:
   ```bash
   make build FAST=1
   ```
2. Use faster compression during development:
   ```bash
   mksquashfs rootfs ... -comp gzip
   ```
3. Use multiple threads (if `mksquashfs` supports it):
   ```bash
   mksquashfs rootfs ... -comp xz -Xdict-size 1M
   ```
