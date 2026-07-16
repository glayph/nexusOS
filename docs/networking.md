# Networking

## Stack

The network stack uses standard Ubuntu packages with no custom configuration.

| Component | Package | Tools |
|---|---|---|
| Kernel networking | `linux-image-virtual` | Netfilter, bridging, VLAN, bonding |
| Network config | `iproute2` | `ip`, `ss`, `bridge`, `tc` |
| Legacy tools | `net-tools` | `ifconfig`, `netstat`, `route`, `arp` |
| DHCP | systemd-networkd | Auto-configured by live-boot |
| DNS | `dnsutils` | `dig`, `nslookup`, `host` |
| Wi-Fi | `wireless-tools`, `wpasupplicant`, `iw` | `iwconfig`, `wpa_supplicant`, `iw` |
| Bluetooth | `bluez`, `bluez-tools` | `bluetoothctl`, `hciconfig` |

## Wi-Fi

Wi-Fi firmware packages (`firmware-iwlwifi`, `firmware-realtek`, `firmware-brcm80211`) are **not** pre-installed to save space (~30 MB). Install via:

```bash
nexus-setup → Drivers → Wi-Fi firmware
```

Or manually:
```bash
apt install firmware-iwlwifi
modprobe iwlwifi
```

## Bluetooth

The BlueZ daemon is pre-installed but not started automatically. Enable it:

```bash
systemctl start bluetooth
bluetoothctl
```

## Network Management

There is no NetworkManager. The live system uses systemd-networkd for automatic DHCP on wired interfaces. For manual configuration:

```bash
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1
```

For Wi-Fi:
```bash
wpa_passphrase "MySSID" "mypassword" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhclient wlan0
```
