"""
Nexus OS — System Management Skills
Handles: health check, process management, package management, snapshots
"""
import subprocess, os, shutil, time

NAME = "system"
VERSION = "1.1"

def run(cmd, timeout=30):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()

SKILLS = {
    "os doctor":        ("System health check",        lambda: doctor()),
    "health check":     ("System health check",        lambda: doctor()),
    "snapshot":         ("Create system snapshot",     lambda: snapshot()),
    "list snapshots":   ("List system snapshots",      lambda: list_snapshots()),
    "pkg install":      ("Install a package",          lambda p: run(f"apt-get install -y {p}")),
    "pkg remove":       ("Remove a package",           lambda p: run(f"apt-get remove -y {p}")),
    "pkg search":       ("Search packages",            lambda p: run(f"apt-cache search {p} | head -20")),
    "pkg update":       ("Update package lists",       lambda: run("apt-get update -q")),
    "pkg upgrade":      ("Upgrade all packages",       lambda: run("apt-get upgrade -y")),
    "process list":     ("List top processes",         lambda: run("ps aux --sort=-%cpu | head -20")),
    "kill process":     ("Kill a process by PID/name", lambda p: run(f"pkill -f {p} || kill -9 {p}")),
    "service status":   ("Check a service status",     lambda s: run(f"systemctl status {s} --no-pager")),
    "service start":    ("Start a service",            lambda s: run(f"systemctl start {s}")),
    "service stop":     ("Stop a service",             lambda s: run(f"systemctl stop {s}")),
    "boot log":         ("Show boot log",              lambda: run("journalctl -b --no-pager | tail -50")),
    "log view":         ("View system logs",           lambda: run("journalctl -n 50 --no-pager")),
    "disk usage":       ("Show disk usage",            lambda: run("df -h && echo '---' && du -sh /* 2>/dev/null | sort -hr | head -10")),
    "memory":           ("Show memory info",           lambda: run("free -h && echo '---' && cat /proc/meminfo | head -15")),
    "temperature":      ("Show CPU temperature",       lambda: run("cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | awk '{print $1/1000\"°C\"}' || echo 'No sensor data'")),
    "uptime":           ("Show uptime",                lambda: run("uptime && last reboot | head -3")),
}

def doctor():
    """Full system health check"""
    out = ["", "╔══ NEXUS OS HEALTH CHECK ═══════════════════╗"]
    checks = [
        ("Kernel",       "uname -r"),
        ("Uptime",       "uptime -p"),
        ("Load",         "cut -d' ' -f1-3 /proc/loadavg"),
        ("Memory",       "free -h | grep Mem | awk '{print $3\"/\"$2}'"),
        ("Disk /",       "df -h / | tail -1 | awk '{print $3\"/\"$2\" (\"$5\" used)\"}'"),
        ("Processes",    "ps aux | wc -l | awk '{print $1-1\" running\"}'"),
        ("Network",      "ip route | grep default | awk '{print $3}' | head -1 || echo 'No default route'"),
        ("Systemd",      "systemctl is-system-running 2>/dev/null || echo 'unknown'"),
        ("Agent",        "cat /etc/nexus/agent.conf | grep AGENT_PROVIDER | cut -d= -f2"),
    ]
    for label, cmd in checks:
        val = subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
        status = "✅" if val else "❌"
        out.append(f"  {status} {label:<14} {val or 'N/A'}")

    # Check critical dirs
    for d in ["/opt/nexus/skills", "/etc/nexus", "/var/log/nexus"]:
        out.append(f"  {'✅' if os.path.isdir(d) else '❌'} Dir: {d}")

    out.append("╚════════════════════════════════════════════╝")
    return "\n".join(out)

def snapshot():
    ts = time.strftime("%Y%m%d-%H%M%S")
    dest = f"/var/backups/nexus-snapshot-{ts}"
    os.makedirs(dest, exist_ok=True)
    run(f"rsync -a --exclude=/proc --exclude=/sys --exclude=/dev "
        f"--exclude=/run --exclude=/tmp --exclude=/var/backups / {dest}/")
    return f"Snapshot created: {dest}"

def list_snapshots():
    snaps = [d for d in os.listdir("/var/backups") if d.startswith("nexus-snapshot-")]
    if not snaps:
        return "No snapshots found."
    return "\n".join(sorted(snaps, reverse=True))
