"""Nexus OS — Developer Tools Skills"""
import subprocess, os

def run(cmd,t=30): return subprocess.run(cmd,shell=True,capture_output=True,text=True,timeout=t).stdout.strip()

SKILLS = {
    "git status":       ("Git repo status",        lambda: run("git status -sb 2>/dev/null || echo 'Not a git repo'")),
    "git log":          ("Recent git commits",     lambda: run("git log --oneline -10 2>/dev/null || echo 'Not a git repo'")),
    "git pull":         ("Git pull latest",        lambda: run("git pull 2>/dev/null || echo 'Not a git repo'")),
    "git clone":        ("Clone a repo",           lambda u: run(f"git clone {u}")),
    "python run":       ("Run a Python script",    lambda f: run(f"python3 {f}")),
    "python shell":     ("Python info",            lambda: run("python3 --version && pip3 --version 2>/dev/null || pip --version")),
    "pip install":      ("Install Python package", lambda p: run(f"pip3 install {p}")),
    "pip list":         ("List Python packages",   lambda: run("pip3 list 2>/dev/null | head -30")),
    "port listen":      ("Check if port is open",  lambda p: run(f"ss -tuln | grep :{p} || echo 'Port {p} not listening'")),
    "process kill":     ("Kill process by name",   lambda n: run(f"pkill -f {n} && echo 'Killed: {n}' || echo 'Not found: {n}'")),
    "log tail":         ("Tail a log file",        lambda f: run(f"tail -30 {f}")),
    "log search":       ("Search logs",            lambda q: run(f"journalctl --no-pager -n 200 | grep -i '{q}' | tail -20")),
    "env list":         ("Show environment vars",  lambda: run("env | sort")),
    "path show":        ("Show PATH",              lambda: run("echo $PATH | tr ':' '\n'")),
    "disk io":          ("Disk I/O stats",         lambda: run("iostat 2>/dev/null || cat /proc/diskstats | head -10")),
    "cpu info":         ("CPU details",            lambda: run("lscpu 2>/dev/null | head -20")),
    "kernel modules":   ("Loaded kernel modules",  lambda: run("lsmod | head -20")),
    "build run":        ("Run make/build",         lambda: run("make 2>&1 | tail -20") if os.path.exists("Makefile") else "No Makefile found"),
}
