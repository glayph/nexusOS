# Chapter 3: Bootstrapping the Root Filesystem

The first step in building a distribution is creating a minimal root filesystem. This is the foundation upon which everything else is built.

## What is Bootstrapping?

Bootstrapping downloads and installs the core packages of a distribution into a directory. The result is a complete but minimal Linux filesystem that can be entered via `chroot`.

## Using debootstrap

`debootstrap` is the standard tool for bootstrapping Debian/Ubuntu. It's been used for decades and is what Docker, LXC, and most Linux build systems use.

### Basic Usage

```bash
debootstrap --arch=amd64 --variant=minbase noble /path/to/rootfs http://archive.ubuntu.com/ubuntu/
```

| Argument | Purpose |
|---|---|
| `--arch=amd64` | 64-bit x86 architecture |
| `--variant=minbase` | Minimal package set (just apt and essentials) |
| `noble` | Ubuntu 24.04 release codename |
| `/path/to/rootfs` | Output directory |
| `http://archive.ubuntu.com/ubuntu/` | Package mirror |

### Variants

| Variant | Includes | Size |
|---|---|---|
| `minbase` | apt, bash, coreutils | ~50 MB |
| `buildd` | minbase + build tools | ~100 MB |
| (default) | minbase + some server packages | ~150 MB |

Always use `minbase` for a custom distribution — you control what gets installed.

## Problem: Bootstrap Fails with "Couldn't download"

**Issue**: `debootstrap` cannot reach the Ubuntu repository.

**Fixes**:
1. Check internet connection: `ping archive.ubuntu.com`
2. Try a different mirror:
   ```bash
   debootstrap --arch=amd64 noble rootfs http://mirrors.kernel.org/ubuntu/
   ```
3. Use the US mirror if you're outside the US:
   ```bash
   debootstrap --arch=amd64 noble rootfs http://us.archive.ubuntu.com/ubuntu/
   ```

## Problem: Bootstrap Runs but Nothing Is Installed

**Issue**: `debootstrap` completes but the rootfs is almost empty.

**Fix**: Check if the variant was specified correctly. Without `--variant=minbase`, `debootstrap` may produce a different set of packages. Also verify the rootfs path is correct.

```bash
ls -la rootfs/bin
# Should show: bash, ls, cat, etc.
```

## Problem: Permission Denied Errors

**Issue**: `debootstrap` fails with permission errors.

**Fix**: `debootstrap` must be run as root.

```bash
sudo bash makebuild.sh
```

Or wrap individual commands with `sudo`.

## Mounting Virtual Filesystems

Once the rootfs exists, you need to mount virtual filesystems before running commands inside it:

```bash
mount --bind /proc rootfs/proc
mount --bind /sys  rootfs/sys
mount --bind /dev  rootfs/dev
mount --bind /dev/pts rootfs/dev/pts
```

### Why This Matters

| Mount | Purpose | Problem if Missing |
|---|---|---|
| `/proc` | Process information, kernel parameters | `apt-get update` fails |
| `/sys` | Hardware information, kernel objects | Module loading fails |
| `/dev` | Device nodes | Can't access hardware |
| `/dev/pts` | Pseudo-terminals | `update-initramfs` fails with "Can not write log" |

## Problem: "Can not write log (Is /dev/pts mounted?)"

**Issue**: When running `chroot` and executing commands, you see:
```
E: Can not write log (Is /dev/pts mounted?) - posix_openpt (19: No such device)
```

**Fix**: Mount `/dev/pts` inside the chroot:
```bash
mount --bind /dev/pts rootfs/dev/pts
```

## Problem: Chroot Command Fails Silently

**Issue**: Commands inside the chroot fail but the build continues.

**Fix**: Always add `set -e` inside chroot commands so failures stop the build immediately:

```bash
chroot "$ROOTFS" /bin/bash -c "
  set -e
  apt-get install -y package-name
  echo 'This only runs if install succeeded'
"
```

Without `set -e`, the inner shell continues executing after a failed command, leading to incomplete rootfs and hard-to-debug problems later.

## Cleanup Trap

Always set up a trap to unmount virtual filesystems when the script exits:

```bash
trap "umount '$ROOTFS/proc' '$ROOTFS/sys' '$ROOTFS/dev' '$ROOTFS/dev/pts' 2>/dev/null; true" EXIT
```

This ensures mounts are cleaned up even if the build fails midway.

## Setting Up APT Sources

After bootstrapping, configure APT sources:

```bash
cat > rootfs/etc/apt/sources.list << 'SOURCES'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe
SOURCES
```

Without this, `apt-get update` inside the chroot will fail.

## Complete Bootstrap Function

Here's how Nexus OS combines all the above into a single step:

```bash
# Step 2: Bootstrap
if [[ ! -d "$ROOTFS/bin" ]]; then
  debootstrap --arch=amd64 --variant=minbase noble "$ROOTFS" \
    http://archive.ubuntu.com/ubuntu/
else
  warn "Rootfs exists — skipping"
fi

# Step 3: APT sources
cat > "$ROOTFS/etc/apt/sources.list" << 'SOURCES'
...
SOURCES

# Step 4: Mount and trap
mountpoint -q "$ROOTFS/proc" || mount --bind /proc "$ROOTFS/proc"
mountpoint -q "$ROOTFS/sys"  || mount --bind /sys  "$ROOTFS/sys"
mountpoint -q "$ROOTFS/dev"  || mount --bind /dev  "$ROOTFS/dev"
mountpoint -q "$ROOTFS/dev/pts" || mount --bind /dev/pts "$ROOTFS/dev/pts"
trap "umount ..." EXIT
```

This is from `makebuild.sh` lines 48-69. The conditional mounts (`mountpoint -q ||`) allow the script to be re-run without double-mounting errors.
