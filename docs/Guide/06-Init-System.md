# Chapter 6: Init System and Services

The init system is the first process started by the kernel (PID 1). It manages services, mounts filesystems, and starts the login prompt.

## Choosing an Init System

| Init System | Pros | Cons |
|---|---|---|
| **systemd** | Standard, well-documented, live-boot requires it | Larger, complex |
| **OpenRC** | Simple, lightweight (Gentoo, Alpine) | Not compatible with live-boot |
| **BusyBox init** | Extremely small | Very limited, no service management |
| **runit** | Simple, fast (Void Linux) | Least common, less documentation |

Nexus OS uses **systemd** because `live-boot` and `live-config` (the standard live ISO tools) are designed for systemd.

## Configuring systemd

### Disabling Unnecessary Services

A minimal system can disable several services that aren't needed:

```bash
systemctl disable systemd-resolved  # DNS resolver (not needed in live session)
systemctl disable systemd-timesyncd # NTP sync (ephemeral)
systemctl disable fstrim.timer      # SSD trim (not needed)
systemctl disable apt-daily.timer   # Auto-updates (not needed in live)
systemctl disable apt-daily-upgrade.timer
systemctl mask systemd-journald-audit.socket  # Audit (not needed)
```

### Auto-Login on tty1

For a live distribution, you want the user to be dropped directly into a shell without a login prompt.

Create a systemd drop-in file:

```bash
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
GETTY
```

This overrides the default `getty@.service` for tty1 to:
- Skip the login prompt (`--autologin root`)
- Not clear the screen on login (`--noclear`)

### Auto-Launching Applications

After auto-login, you can automatically start a program by using `.bash_profile`:

```bash
cat > /root/.bash_profile << 'PROFILE'
if [ "$(tty)" = "/dev/tty1" ]; then
  exec /usr/local/bin/my-program
fi
PROFILE
```

The `if [ "$(tty)" = "/dev/tty1" ]` check ensures the program only launches on the main terminal, not when you SSH in or open a second terminal.

## Problem: Auto-Login Not Working

**Issue**: The system still asks for a username/password at boot.

**Fixes**:
1. Check the drop-in file exists:
   ```bash
   ls /etc/systemd/system/getty@tty1.service.d/autologin.conf
   ```
2. Verify systemd reloaded the configuration:
   ```bash
   systemctl daemon-reload
   ```
3. Check for conflicting services (like `display-manager.service`) that may intercept tty1 before getty.

## Problem: Systemd Service Won't Start at Boot

**Issue**: Your custom service doesn't start automatically.

**Fixes**:
1. Check the unit file syntax:
   ```bash
   systemd-analyze verify my-service.service
   ```
2. Enable the service:
   ```bash
   systemctl enable my-service.service
   ```
3. Check dependencies — does it require something that isn't ready?
   ```bash
   systemctl list-dependencies my-service.service
   ```

## System Identity

Configure hostname and hosts file so the system has a network identity:

```bash
echo "nexus" > /etc/hostname

cat > /etc/hosts << 'HOSTS'
127.0.0.1   localhost
127.0.1.1   nexus
::1         localhost ip6-localhost ip6-loopback
HOSTS
```

## OS Release

Create `/etc/os-release` to identify your distribution:

```bash
cat > /etc/os-release << OSREL
NAME="Nexus OS"
VERSION="1.0"
ID=nexus
ID_LIKE=ubuntu
PRETTY_NAME="Nexus OS 1.0"
BUILD_DATE=$(date +%Y-%m-%d)
OSREL
```

This file is read by many tools (`lsb_release`, `screenfetch`, system info scripts) to display the distribution name.
