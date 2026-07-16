# Chapter 11: User Accounts and Persistence

This chapter covers user management and making changes survive across reboots — two features that transform a live ISO from a demo into a usable system.

## Creating a User Account

### At Build Time

If you want a pre-created user in the ISO:

```bash
useradd -m -G sudo -s /bin/bash myuser
echo "myuser:mypassword" | chpasswd
```

### At Runtime (via Setup Tool)

```bash
create_user() {
  username=$(input "Create User" "Enter username:")
  [[ -z "$username" ]] && return
  
  password=$(input "Create User" "Enter password:")
  [[ -z "$password" ]] && return
  
  useradd -m -G sudo -s /bin/bash "$username"
  echo "$username:$password" | chpasswd
  
  msg "Done" "User $username created."
}
```

## Problem: Root Runs Everything by Default

In a live distribution, the user is root by default (auto-login). This has implications:

- **Browser security**: Chrome/Firefox refuse to run as root
- **File permissions**: All files created are owned by root
- **Accidental damage**: `rm -rf /` is one typo away

**Solution**: Use the setup tool to create a regular user for daily work, and `sudo` for admin tasks.

## Persistence: The Problem

A live ISO boots from read-only squashfs. Every change — installed packages, modified files, created documents — is lost on reboot. Persistence solves this.

## Persistence Methods

### Method 1: Kernel Overlay (casper)

Ubuntu's live system (`casper`) supports a `persistent` partition:

```bash
# Create a partition with label "casper-rw" on the USB
# Boot with: persistent
```

This is the most mature approach but requires rebuilding the ISO with casper (not live-boot).

### Method 2: Loopback Overlay File (Nexus OS approach)

Create an ext4 file and use it as an overlay upper directory:

```bash
# Create 512 MB overlay file
dd if=/dev/zero of=/persist.img bs=1M count=512
mkfs.ext4 -F /persist.img

# Mount it
mkdir -p /mnt/persist
mount /persist.img /mnt/persist

# Create overlay structure
mkdir -p /mnt/persist/{upper,work}

# Mount overlay
mount -t overlay overlay \
  -o lowerdir=/,upperdir=/mnt/persist/upper,workdir=/mnt/persist/work \
  /mnt/overlay
```

### Method 3: Systemd Service (Automated)

Create a systemd service that runs at boot:

```bash
cat > /etc/systemd/system/persist-overlay.service << 'SVC'
[Unit]
Description=Persistence overlay
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/persist-overlay

[Install]
WantedBy=local-fs.target
SVC
```

## Problem: Overlay Mount Fails

**Issue**: `mount -t overlay` returns "mount: /mnt/overlay: wrong fs type, bad option, bad superblock".

**Fixes**:
1. Ensure the kernel supports overlay filesystem:
   ```bash
   modprobe overlay
   ls /sys/module/overlay
   ```
2. Check that the lowerdir exists (the rootfs)
3. Verify upperdir and workdir are on a writable filesystem

## Problem: Persistence Is Incomplete

**Issue**: After enabling persistence and rebooting, changes appear to be lost.

**Fixes**:
1. Check the persistence file exists: `ls -la /persist.img`
2. Verify it mounted: `mount | grep persist`
3. Check the overlay was applied: `mount | grep overlay`
4. The overlay must be mounted **before** systemd starts writing to the root. This is why `Before=sysinit.target` is critical.

## Problem: Limited Overlay Space

**Issue**: The 512 MB overlay file fills up.

**Fixes**:
1. Create a larger overlay file: `dd if=/dev/zero of=/persist.img bs=1M count=4096` (4 GB)
2. Use a partition instead of a file for unlimited space
3. Monitor usage: `df -h /mnt/persist`

## Full Automated Setup

Here's how `nexus-setup` implements persistence:

```bash
persistence_setup() {
  # Create 512 MB ext4 file
  dd if=/dev/zero of=/persist.img bs=1M count=512
  mkfs.ext4 -F /persist.img
  
  # Mount
  mkdir -p /mnt/persist
  echo "/persist.img /mnt/persist ext4 loop,defaults 0 0" >> /etc/fstab
  mount /mnt/persist
  
  # Create overlay directories
  mkdir -p /mnt/persist/{upper,work,session}
  
  # Write overlay script
  cat > /usr/bin/persist-overlay << 'OVL'
#!/bin/bash
PERSIST=/mnt/persist
case "$1" in
  stop) ... ;;
  *)
    snap=$(date +%Y%m%d-%H%M%S)
    mkdir -p $PERSIST/session/$snap
    mount --bind $PERSIST/session/$snap $PERSIST/upper
    mount -t overlay overlay \
      -o lowerdir=/,upperdir=$PERSIST/upper,workdir=$PERSIST/work \
      /mnt/overlay
    ;;
esac
OVL
  chmod +x /usr/bin/persist-overlay
  
  # Enable service
  systemctl enable persist-overlay.service
}
```
