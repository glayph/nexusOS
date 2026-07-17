"""Nexus OS — Network Skills"""
import subprocess

def run(cmd, t=20): return subprocess.run(cmd,shell=True,capture_output=True,text=True,timeout=t).stdout.strip()

SKILLS = {
    "network status":   ("Full network status",       lambda: run("ip addr && echo '---' && ip route && echo '---' && ss -tuln")),
    "wifi list":        ("List WiFi networks",         lambda: run("nmcli dev wifi list 2>/dev/null || iwlist scan 2>/dev/null | grep ESSID || echo 'nmcli not available'")),
    "wifi connect":     ("Connect to WiFi",            lambda s,p: run(f"nmcli dev wifi connect '{s}' password '{p}'")),
    "wifi status":      ("WiFi connection status",     lambda: run("nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null || ip link show")),
    "ping":             ("Ping a host",                lambda h: run(f"ping -c 4 {h}")),
    "dns lookup":       ("DNS lookup",                 lambda h: run(f"nslookup {h} 2>/dev/null || dig {h} +short 2>/dev/null || host {h}")),
    "dns troubleshoot": ("DNS diagnostics",            lambda: _dns_check()),
    "traceroute":       ("Trace route to host",        lambda h: run(f"traceroute -m 15 {h} 2>/dev/null || tracepath {h}")),
    "speed test":       ("Internet speed test",        lambda: run("speedtest-cli --simple 2>/dev/null || curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3")),
    "open ports":       ("Show open ports",            lambda: run("ss -tuln")),
    "connections":      ("Active connections",         lambda: run("ss -tp")),
    "firewall status":  ("Firewall status",            lambda: run("ufw status verbose 2>/dev/null || iptables -L -n --line-numbers 2>/dev/null | head -40")),
    "firewall enable":  ("Enable firewall",            lambda: run("ufw --force enable")),
    "firewall disable": ("Disable firewall",           lambda: run("ufw disable")),
    "firewall allow":   ("Allow a port",               lambda p: run(f"ufw allow {p}")),
    "firewall deny":    ("Deny a port",                lambda p: run(f"ufw deny {p}")),
    "proxy set":        ("Set HTTP proxy",             lambda u: _set_proxy(u)),
    "proxy clear":      ("Clear proxy settings",       lambda: _clear_proxy()),
    "ip info":          ("Show IP addresses",          lambda: run("ip -br addr")),
    "mac address":      ("Show MAC addresses",         lambda: run("ip link show | grep ether")),
    "ethernet diag":    ("Ethernet diagnostics",       lambda: run("ethtool eth0 2>/dev/null || ip link show eth0 2>/dev/null || echo 'eth0 not found'")),
}

def _dns_check():
    results = []
    for ns in ["8.8.8.8", "1.1.1.1", "system"]:
        cmd = f"nslookup google.com {ns}" if ns != "system" else "nslookup google.com"
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        results.append(f"[{ns}] {'✅ OK' if r.returncode == 0 else '❌ FAIL'}")
    return "\n".join(results)

def _set_proxy(url):
    lines = [f'export http_proxy="{url}"', f'export https_proxy="{url}"',
             f'export HTTP_PROXY="{url}"', f'export HTTPS_PROXY="{url}"']
    with open("/etc/environment", "a") as f:
        f.write("\n".join(lines) + "\n")
    return f"Proxy set to {url}. Re-login to apply."

def _clear_proxy():
    lines = open("/etc/environment").readlines() if __import__("os").path.exists("/etc/environment") else []
    with open("/etc/environment", "w") as f:
        f.writelines(l for l in lines if "proxy" not in l.lower())
    return "Proxy settings cleared."
