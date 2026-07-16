# Chapter 12: Networking, Audio, and Hardware Support

## Network Stack

### Wired Networking

Wired networking is handled automatically by live-boot/systemd-networkd:

```
DHCP client  ──>  systemd-networkd  ──>  kernel  ──>  NIC driver
```

Most wired NICs are supported out of the box by the `linux-image-virtual` kernel. Common drivers include:
- `e1000`, `e1000e` (Intel)
- `r8169` (Realtek)
- `virtio_net` (QEMU/KVM)

### Wi-Fi

Wi-Fi requires three components:

| Component | Package | Purpose |
|---|---|---|
| Kernel driver | `linux-image-virtual` | Hardware interface (iwlwifi, ath9k, etc.) |
| Supplicant | `wpasupplicant` | WPA/WPA2 authentication |
| Configuration | `wireless-tools` / `iw` | Scanning and connection management |

#### Manual Wi-Fi Connection

```bash
# Scan for networks
iw dev wlan0 scan | grep SSID

# Connect to WPA network
wpa_passphrase "MyNetwork" "mypassword" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhclient wlan0
```

## Problem: Wi-Fi Adapter Not Detected

**Issue**: `iw dev` shows no wireless interfaces.

**Fixes**:
1. Check if the module is loaded: `lsmod | grep iwl` (for Intel)
2. Load the module manually: `modprobe iwlwifi`
3. Install firmware: `apt-get install firmware-iwlwifi`
4. Check if kernel modules were stripped (see Chapter 5)

## Problem: Wi-Fi Firmware Missing

**Issue**: `dmesg` shows "firmware: failed to load iwlwifi-*.ucode".

**Fix**: Install the appropriate firmware package:
```bash
# Intel
apt-get install firmware-iwlwifi

# Realtek
apt-get install firmware-realtek

# Broadcom
apt-get install firmware-brcm80211
```

These packages are **not** pre-installed in Nexus OS (too large). Install via `nexus-setup`.

## Problem: NetworkManager Not Available

**Issue**: Users expect `nmcli` or a GUI network manager.

**Fix**: Either install NetworkManager, or provide clear documentation for `wpa_supplicant` + `dhclient`. Nexus OS documents both approaches and lets users choose.

## Audio Stack

### Components

```
Application  ──>  PulseAudio  ──>  ALSA  ──>  Kernel (snd-*)  ──>  Hardware
```

| Component | Packages | Purpose |
|---|---|---|
| Kernel modules | `linux-image-virtual` | Hardware interface (snd-hda-intel, snd-usb-audio) |
| ALSA utilities | `alsa-utils` | alsamixer, aplay, amixer |
| Sound server | `pulseaudio` | Per-app volume, mixing, Bluetooth audio |

### Basic Audio Testing

```bash
# List devices
aplay -l

# Set volume
alsamixer

# Test playback
speaker-test -t sine -f 440 -l 1
```

## Problem: No Sound Devices

**Issue**: `aplay -l` shows no devices.

**Fixes**:
1. Check sound modules: `lsmod | grep snd`
2. Load modules: `modprobe snd-hda-intel`
3. Check if `sound/*` was stripped from kernel modules
4. In QEMU: add `-soundhw hda` or `-device intel-hda -device hda-duplex`

## Problem: PulseAudio Not Working as Root

**Issue**: PulseAudio fails with "pa_context_connect() failed".

**Fix**: PulseAudio normally runs per-user. Start it manually:
```bash
pulseaudio --start --system
```

Or create a regular user and log in as that user for audio.

## Bluetooth

```bash
# Start the Bluetooth daemon
systemctl start bluetooth

# Interactive control
bluetoothctl

# Scan for devices
bluetoothctl scan on

# Pair
bluetoothctl pair XX:XX:XX:XX:XX:XX
```

## Problem: Bluetooth Not Working

**Issue**: `bluetoothctl` shows no adapters.

**Fixes**:
1. Start the service: `systemctl start bluetooth`
2. Check module: `lsmod | grep btusb`
3. Install firmware if needed

## Hardware Detection

```bash
# List PCI devices
lspci

# List USB devices
lsusb

# Kernel messages (check for hardware errors)
dmesg | grep -i error

# Hardware info
lshw -short

# Block devices
lsblk
```
