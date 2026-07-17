# GRUB Bootloader

## Configuration File

Located at `boot/grub/grub.cfg`. It's a minimal configuration with three menu entries.

## Design Choices

- **gfxmode=auto**: Allows GRUB to use the native display resolution
- **gfxpayload=keep**: Keeps the framebuffer resolution set by GRUB for the kernel
- **Timeout: 5 seconds**: Brief but enough to interrupt if needed

## Menu Entries

### 1. TajaOS (default)
```bash
linux /boot/vmlinuz boot=live components quiet hostname=tajaos
initrd /boot/initrd.img
```
Standard boot with quiet mode. Auto-logs in to a root shell.

### 2. TajaOS (verbose mode)
```bash
linux /boot/vmlinuz boot=live components hostname=tajaos
initrd /boot/initrd.img
```
Boots without `quiet` — shows all kernel messages. Useful for debugging boot issues.

### 3. Boot from first disk
```bash
set root=(hd0,msdos1)
chainloader +1
```
Boots the first hard disk's installed OS — for dual-boot scenarios without changing BIOS settings.

## How GRUB Is Embedded

The ISO uses `grub-mkrescue` (not traditional `grub-install`), which:

- Automatically embeds all GRUB modules (`echo.mod`, `chain.mod`, etc.) — solving the "module not found" errors that occur with manual `bios.img`/`efiboot.img` approaches
- Creates a proper **El Torito** boot record for BIOS
- Creates a **FAT partition** with EFI/grub for UEFI boot
- Sets ISO volume label to `TAJAOS_2_0`

## Volume Label

GRUB searches for the ISO by label (TAJAOS_2_0):
```bash
search --no-floppy --label --set=root "TAJAOS_2_0"
```

If the label isn't found (e.g., booting from a non-ISO source), it falls back to `(cd0)`.
