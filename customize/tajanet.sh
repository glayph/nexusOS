#!/bin/bash
# ============================================================
#  TajaNet — Network Manager (CLI/TUI)
#  Wi-Fi, Ethernet, VPN, DNS, Proxy, Diagnostics
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
CONFIG_DIR="/etc/tajados"
STATE_DIR="/var/lib/tajados"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[TajaNet]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

# ========== Wi-Fi ==========
wifi_scan() {
  log "Scanning for Wi-Fi networks..."
  nmcli -t -f SSID,SIGNAL,SECURITY,CHAN dev wifi list 2>/dev/null | sort -t: -k2 -nr | column -t -s:
}

wifi_connect() {
  local ssid="$1" password="$2"
  [[ -z "$ssid" ]] && { read -rp "SSID: " ssid; }
  [[ -z "$password" ]] && { read -rsp "Password: " password; echo; }
  nmcli dev wifi connect "$ssid" password "$password" && ok "Connected to $ssid" || die "Connection failed"
}

wifi_disconnect() {
  local iface="${1:-$(nmcli -t -f DEVICE,TYPE dev | grep wifi | cut -d: -f1 | head -1)}"
  nmcli dev disconnect "$iface" && ok "Disconnected $iface"
}

wifi_forget() {
  local ssid="$1"
  nmcli conn delete "$ssid" 2>/dev/null && ok "Forgotten: $ssid"
}

wifi_list_saved() {
  nmcli -t -f NAME,TYPE conn show | grep 802-11-wireless | cut -d: -f1
}

# ========== Ethernet ==========
eth_status() {
  nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev | grep ethernet
}

eth_dhcp() {
  local iface="$1"
  nmcli dev set "$iface" managed yes
  nmcli conn up "$iface" 2>/dev/null || nmcli dev connect "$iface"
  ok "DHCP started on $iface"
}

eth_static() {
  local iface="$1" ip="$2" gw="$3" dns="$4"
  nmcli conn add type ethernet con-name "static-$iface" ifname "$iface" ip4 "$ip" gw4 "$gw" ipv4.dns "$dns" ipv4.method manual
  nmcli conn up "static-$iface"
  ok "Static IP configured on $iface"
}

# ========== DNS ==========
dns_set() {
  local dns="$1"
  [[ -z "$dns" ]] && { read -rp "DNS servers (space-separated): " dns; }
  nmcli conn mod "$(nmcli -t -f NAME,DEVICE conn show --active | head -1 | cut -d: -f1)" ipv4.dns "$dns"
  nmcli conn up "$(nmcli -t -f NAME,DEVICE conn show --active | head -1 | cut -d: -f1)"
  echo "nameserver $dns" > /etc/resolv.conf
  ok "DNS set to: $dns"
}

dns_flush() {
  systemctl restart systemd-resolved 2>/dev/null || true
  ok "DNS cache flushed"
}

dns_test() {
  local host="${1:-1.1.1.1}"
  dig +short "$host" @1.1.1.1 | head -5
}

# ========== VPN ==========
vpn_add() {
  local type="$1" config="$2"
  case "$type" in
    openvpn) nmcli conn import type openvpn file "$config" ;;
    wireguard) nmcli conn import type wireguard file "$config" ;;
    *) die "Unsupported VPN type: $type" ;;
  esac
  ok "VPN config imported"
}

vpn_connect() {
  local name="$1"
  nmcli conn up "$name" && ok "VPN connected: $name"
}

vpn_disconnect() {
  local name="$1"
  nmcli conn down "$name" && ok "VPN disconnected: $name"
}

vpn_list() {
  nmcli -t -f NAME,TYPE,DEVICE conn show | grep -E 'vpn|wireguard'
}

# ========== Proxy ==========
proxy_set() {
  local mode="$1" host="$2" port="$3"
  export http_proxy="$mode://$host:$port"
  export https_proxy="$mode://$host:$port"
  export no_proxy="localhost,127.0.0.1,::1"
  echo "export http_proxy=$mode://$host:$port" > /etc/profile.d/proxy.sh
  echo "export https_proxy=$mode://$host:$port" >> /etc/profile.d/proxy.sh
  ok "Proxy set: $mode://$host:$port"
}

proxy_clear() {
  unset http_proxy https_proxy no_proxy
  rm -f /etc/profile.d/proxy.sh
  ok "Proxy cleared"
}

# ========== Diagnostics ==========
net_speed() {
  log "Testing network speed..."
  curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -
}

net_ping() {
  local host="${1:-8.8.8.8}" count="${2:-4}"
  ping -c "$count" "$host"
}

net_trace() {
  local host="${1:-8.8.8.8}"
  traceroute "$host" 2>/dev/null || tracepath "$host"
}

net_ports() {
  local host="${1:-localhost}"
  nmap -T4 -F "$host" 2>/dev/null || ss -tuln
}

net_diag() {
  log "=== Network Diagnostics ==="
  echo -e "\n${C}Interfaces:${N}"; ip -br addr
  echo -e "\n${C}Routes:${N}"; ip route
  echo -e "\n${C}DNS:${N}"; cat /etc/resolv.conf
  echo -e "\n${C}Active Connections:${N}"; nmcli conn show --active
  echo -e "\n${C}Failed Services:${N}"; systemctl list-units --failed | grep -i net || echo "None"
  echo -e "\n${C}Ping Test:${N}"; ping -c 2 8.8.8.8 2>&1 | tail -3
  echo -e "\n${C}DNS Test:${N}"; dig +short google.com @1.1.1.1
}

# ========== Firewall (nftables) ==========
fw_enable() {
  systemctl enable --now nftables 2>/dev/null || { apt-get update && apt-get install -y nftables; systemctl enable --now nftables; }
  cat > /etc/nftables.conf << 'NFT'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    icmp type echo-request limit rate 5/second accept
    tcp dport { 22, 80, 443 } accept
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output { type filter hook output priority 0; policy accept; }
}
NFT
  nft -f /etc/nftables.conf
  ok "Firewall enabled (default deny inbound, allow SSH/HTTP/HTTPS)"
}

fw_disable() {
  nft flush ruleset
  systemctl stop nftables
  ok "Firewall disabled"
}

fw_status() {
  nft list ruleset
}

fw_allow() {
  local port="$1" proto="${2:-tcp}"
  nft add rule inet filter input "$proto" dport "$port" accept
  ok "Allowed $proto/$port"
}

fw_block() {
  local ip="$1"
  nft add rule inet filter input ip saddr "$ip" drop
  ok "Blocked $ip"
}

# ========== TUI Menu ==========
tui_menu() {
  while true; do
    local sel
    sel=$(whiptail --title "TajaNet" --menu "Network Management" 20 70 12 \
      "1" "Wi-Fi: Scan & Connect" \
      "2" "Wi-Fi: Saved Networks" \
      "3" "Ethernet: Status & Config" \
      "4" "DNS: Set / Flush / Test" \
      "5" "VPN: Manage Connections" \
      "6" "Proxy: Configure / Clear" \
      "7" "Diagnostics: Full Check" \
      "8" "Speed Test" \
      "9" "Firewall: Enable / Status / Rules" \
      "10" "Port Scanner" \
      "11" "Exit" 3>&1 1>&2 2>&3)
    [[ -z "$sel" ]] && break
    case "$sel" in
      1) local ssid pass; ssid=$(whiptail --inputbox "SSID:" 8 40 3>&1 1>&2 2>&3); pass=$(whiptail --passwordbox "Password:" 8 40 3>&1 1>&2 2>&3); wifi_connect "$ssid" "$pass" ;;
      2) wifi_list_saved | while read n; do whiptail --msgbox "Saved: $n" 8 40; done ;;
      3) eth_status | whiptail --textbox /dev/stdin 15 70 ;;
      4) local dns; dns=$(whiptail --inputbox "DNS servers (space-separated):" 8 40 "1.1.1.1 8.8.8.8" 3>&1 1>&2 2>&3); dns_set "$dns" ;;
      5) vpn_list | whiptail --textbox /dev/stdin 15 70 ;;
      6) proxy_clear ;;
      7) net_diag | whiptail --textbox /dev/stdin 30 100 ;;
      8) net_speed | whiptail --textbox /dev/stdin 30 100 ;;
      9) fw_status | whiptail --textbox /dev/stdin 20 80 ;;
      10) local host; host=$(whiptail --inputbox "Host to scan:" 8 40 "localhost" 3>&1 1>&2 2>&3); net_ports "$host" | whiptail --textbox /dev/stdin 20 80 ;;
      11) break ;;
    esac
  done
}

# ========== CLI ==========
usage() {
  cat << USAGE
Usage: tajanet <command> [args]

Wi-Fi:
  tajanet wifi scan                    Scan networks
  tajanet wifi connect <ssid> [pass]   Connect
  tajanet wifi disconnect [iface]      Disconnect
  tajanet wifi forget <ssid>           Forget network
  tajanet wifi list                    List saved

Ethernet:
  tajanet eth status                   Show status
  tajanet eth dhcp <iface>             Enable DHCP
  tajanet eth static <iface> <ip> <gw> <dns>  Static IP

DNS:
  tajanet dns set <servers>            Set DNS
  tajanet dns flush                    Flush cache
  tajanet dns test [host]              Test DNS

VPN:
  tajanet vpn add <type> <config>      Import VPN (openvpn/wireguard)
  tajanet vpn connect <name>           Connect
  tajanet vpn disconnect <name>        Disconnect
  tajanet vpn list                     List VPNs

Proxy:
  tajanet proxy set <mode> <host> <port>  Set proxy (http/socks5)
  tajanet proxy clear                  Clear proxy

Diagnostics:
  tajanet diag                         Full diagnostics
  tajanet speed                        Speed test
  tajanet ping [host] [count]          Ping
  tajanet trace <host>                 Traceroute
  tajanet ports [host]                 Port scan

Firewall:
  tajanet fw enable                    Enable firewall
  tajanet fw disable                   Disable firewall
  tajanet fw status                    Show rules
  tajanet fw allow <port> [proto]      Allow port
  tajanet fw block <ip>                Block IP

TUI:
  tajanet tui                          Interactive menu

USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    wifi)
      local sub="$1"; shift
      case "$sub" in
        scan) wifi_scan ;;
        connect) wifi_connect "$@" ;;
        disconnect) wifi_disconnect "$@" ;;
        forget) wifi_forget "$@" ;;
        list) wifi_list_saved ;;
        *) usage; exit 1 ;;
      esac
      ;;
    eth)
      local sub="$1"; shift
      case "$sub" in
        status) eth_status ;;
        dhcp) eth_dhcp "$@" ;;
        static) eth_static "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    dns)
      local sub="$1"; shift
      case "$sub" in
        set) dns_set "$@" ;;
        flush) dns_flush ;;
        test) dns_test "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    vpn)
      local sub="$1"; shift
      case "$sub" in
        add) vpn_add "$@" ;;
        connect) vpn_connect "$@" ;;
        disconnect) vpn_disconnect "$@" ;;
        list) vpn_list ;;
        *) usage; exit 1 ;;
      esac
      ;;
    proxy)
      local sub="$1"; shift
      case "$sub" in
        set) proxy_set "$@" ;;
        clear) proxy_clear ;;
        *) usage; exit 1 ;;
      esac
      ;;
    diag) net_diag ;;
    speed) net_speed ;;
    ping) net_ping "$@" ;;
    trace) net_trace "$@" ;;
    ports) net_ports "$@" ;;
    fw)
      local sub="$1"; shift
      case "$sub" in
        enable) fw_enable ;;
        disable) fw_disable ;;
        status) fw_status ;;
        allow) fw_allow "$@" ;;
        block) fw_block "$@" ;;
        *) usage; exit 1 ;;
      esac
      ;;
    tui) tui_menu ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"