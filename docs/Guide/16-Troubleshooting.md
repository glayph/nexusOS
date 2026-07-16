# Chapter 16: Troubleshooting Common Problems

This chapter documents every problem encountered during the development of Nexus OS and how each was fixed.

## Build Problems

### Problem: `debootstrap` Fails

**Symptoms**:
```
E: Couldn't download packages
E: Failed to bootstrap
```

**Fixes**:
- Check internet connectivity: `ping archive.ubuntu.com`
- Try a different mirror: `http://mirrors.kernel.org/ubuntu/`
- Use `--variant=minbase` to reduce download size

### Problem: Package Installation Fails

**Symptoms**:
```
E: Unable to locate package <name>
E: Package <name> has no installation candidate
```

**Fixes**:
- Check the package name on your distribution: `apt search <keyword>`
- Ensure `apt-get update` ran inside the chroot
- Ensure APT sources are configured (see Chapter 3)

### Problem: Wrong Package Name

**Symptoms**: Build completes but the package isn't installed.

**Fixes**:
- Verify packages post-build: `ls rootfs/usr/bin/<tool>`
- On Ubuntu: `wpasupplicant` (not `wpa_supplicant`)
- On Ubuntu: `alsa-utils` (not `alsa`)
- On Ubuntu: `bluez` (not `bluetooth`)

### Problem: Pipe Masking Failures

**Symptoms**: Build succeeds but the ISO is broken.

**Fixes**:
```bash
# Don't mask errors with pipes
apt-get install ... 2>&1 | grep 'Setting up'    # Bad
apt-get install ... 2>&1                          # Good

# Use set -e in chroot blocks
chroot rootfs bash -c "set -e; apt-get install ..."
```

### Problem: Initramfs Not Generated

**Symptoms**:
```
cp: cannot stat 'rootfs/boot/initrd.img-*'
```

**Fixes**:
- Mount `/dev/pts` inside the chroot
- Don't pipe `update-initramfs` through `tail`
- Check `initramfs-tools` is installed
- Run with explicit error handling:
  ```bash
  chroot rootfs /bin/bash -c "update-initramfs -u -k all" || die "Failed"
  ```

### Problem: xorriso Fails

**Symptoms**:
```
xorriso : FAILURE : Not a known command: '-appid'
grub-mkrescue: error: `xorriso` invocation failed
```

**Fixes**:
- Use `-application_id` instead of `-appid`
- Use `-volid` instead of `-volume`
- Check `grub-common` and `xorriso` are installed

## Boot Problems

### Problem: "file /boot/vmlinuz not found"

**Symptoms**: GRUB menu appears, but boot fails with this message.

**Fixes**:
- Re-flash the ISO: `sudo dd if=nexus.iso of=/dev/sdX bs=4M status=progress && sync`
- Ensure the ISO was written correctly (check SHA256)

### Problem: "No screens found" (Xorg)

**Symptoms**: `startx` fails, black screen.

**Fixes**:
- Ensure `drivers/gpu/drm` kernel modules were not stripped
- Try specific video driver: `startx -- -logverbose 3`
- Check kernel modesetting: `dmesg | grep drm`

### Problem: "Unable to find live filesystem"

**Symptoms**: Boot fails at initramfs with this message.

**Fixes**:
- Ensure ISO has `live/filesystem.squashfs`
- Check kernel params include `boot=live components`
- Ensure ISO volume label matches GRUB `search` directive

### Problem: Auto-login Not Working

**Symptoms**: Boot asks for username/password.

**Fixes**:
- Check the systemd drop-in exists: `ls /etc/systemd/system/getty@tty1.service.d/`
- Run `systemctl daemon-reload` in the build
- Verify no `display-manager.service` is interfering

## Runtime Problems

### Problem: No Audio

**Symptoms**: `aplay -l` shows no devices.

**Fixes**:
- Load sound modules: `modprobe snd-hda-intel`
- Check if `sound/` was stripped from kernel modules
- In QEMU: add `-soundhw hda` flag

### Problem: No Wi-Fi

**Symptoms**: `iw dev` shows no wireless interfaces.

**Fixes**:
- Check module: `lsmod | grep iwlwifi`
- Load module: `modprobe iwlwifi`
- Install firmware: `apt-get install firmware-iwlwifi`
- Check kernel modules weren't stripped

### Problem: No Bluetooth

**Symptoms**: `bluetoothctl` shows no adapter.

**Fixes**:
- Start the service: `systemctl start bluetooth`
- Check module: `lsmod | grep btusb`
- Ensure kernel modules include `drivers/bluetooth/`

### Problem: Chrome/Brave Won't Start

**Symptoms**:
```
Running as root without --no-sandbox is not supported
```

**Fixes**:
- Create a user: `useradd -m user; su - user`
- Or use: `brave-browser --no-sandbox` (not recommended)

### Problem: Changes Lost After Reboot

**Symptoms**: All installed packages and files disappear.

**Fixes**:
- Enable persistence via `nexus-setup → Setup Persistence`
- Without persistence, the ISO is read-only by design

### Problem: Disk Full

**Symptoms**: `df -h` shows 100% usage on overlay.

**Fixes**:
- The tmpfs overlay has limited space (usually 50% of RAM)
- Close unnecessary programs
- Free space: Remove temporary files, apt cache

## CI/CD Problems

### Problem: Build Times Out

**Symptoms**: GitHub Actions stops after 120 minutes.

**Fixes**:
- Increase timeout: `timeout-minutes: 180`
- Optimize build: faster compression, skip unnecessary steps

### Problem: Release Not Created

**Symptoms**: Build succeeds but no release appears.

**Fixes**:
- Add `permissions: contents: write`
- Create the tag first: `git tag v1.0 && git push origin v1.0`

## Optimization Problems

### Problem: ISO Too Large

**Symptoms**: ISO exceeds target size.

**Fixes**:
- Strip kernel modules (Chapter 5)
- Remove unnecessary packages (Chapter 4)
- Clean post-install files (Chapter 14)
- Use better compression (Chapter 14)

### Problem: Stripping Kernel Modules Breaks Hardware

**Symptoms**: Hardware works in normal Ubuntu but not in the custom ISO.

**Fixes**:
- Don't strip modules for hardware you want to support
- Provide restore option: `apt-get install --reinstall linux-image-virtual`
- Document what was removed

## General Debugging Tips

```bash
# Check kernel messages
dmesg | tail -50

# Check systemd journal
journalctl -xe

# Check Xorg log (if GUI fails)
cat /var/log/Xorg.0.log | grep EE

# Check if a process is running
ps aux | grep <name>

# Check filesystem structure
ls -la /boot/
ls -la /live/
```

## The Golden Rule

> If the build succeeds but the ISO doesn't boot, always check for **piped commands masking failures**. Every build failure in Nexus OS's development was ultimately caused by `| tail -3` or `| grep` hiding a failing command.
