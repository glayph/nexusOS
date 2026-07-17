"""Nexus OS — Security Skills"""
import subprocess, os, time

def run(cmd,t=20): return subprocess.run(cmd,shell=True,capture_output=True,text=True,timeout=t).stdout.strip()

SKILLS = {
    "audit log":        ("Show audit log",              lambda: run("tail -50 /var/log/nexus/audit.log 2>/dev/null || echo 'No audit log'")),
    "failed logins":    ("Show failed logins",          lambda: run("journalctl _SYSTEMD_UNIT=ssh.service | grep Failed | tail -20")),
    "open ports scan":  ("Scan open ports",             lambda: run("ss -tuln")),
    "running services": ("List all services",           lambda: run("systemctl list-units --type=service --state=running")),
    "firewall rules":   ("Show firewall rules",         lambda: run("ufw status numbered 2>/dev/null || iptables -L -n")),
    "file permissions": ("Check sensitive file perms",  lambda: _check_perms()),
    "passwd policy":    ("Check password policy",       lambda: run("cat /etc/login.defs | grep -v '^#' | grep -v '^$'")),
    "suid files":       ("Find SUID files (risky)",     lambda: run("find / -perm -4000 -type f 2>/dev/null | head -20")),
    "cron jobs":        ("Show scheduled tasks",        lambda: run("crontab -l 2>/dev/null; ls /etc/cron* 2>/dev/null")),
    "users list":       ("Show all users",              lambda: run("cat /etc/passwd | grep -v nologin | grep -v false")),
    "sudo rules":       ("Show sudo rules",             lambda: run("cat /etc/sudoers 2>/dev/null || echo 'No sudoers access'")),
    "disk encryption":  ("Check disk encryption",       lambda: run("lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINT | grep -i crypt || echo 'No encrypted devices found'")),
    "secure delete":    ("Securely delete a file",      lambda f: run(f"shred -u -z -n 3 {f} && echo 'Securely deleted: {f}'")),
    "lock user":        ("Lock a user account",         lambda u: run(f"passwd -l {u}")),
    "unlock user":      ("Unlock a user account",       lambda u: run(f"passwd -u {u}")),
}

def _check_perms():
    files = {
        "/etc/passwd": "644",
        "/etc/shadow": "640",
        "/etc/sudoers": "440",
        "/root": "700",
        "/tmp": "1777",
    }
    results = []
    for f, expected in files.items():
        if os.path.exists(f):
            actual = oct(os.stat(f).st_mode)[-3:]
            ok = "✅" if actual == expected else "⚠️ "
            results.append(f"  {ok} {f:<20} expected:{expected}  actual:{actual}")
    return "\n".join(results)
