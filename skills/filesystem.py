"""TajaOS — Filesystem & Storage Skills"""
import subprocess, os, shutil, time

def run(cmd,t=30): return subprocess.run(cmd,shell=True,capture_output=True,text=True,timeout=t).stdout.strip()

SKILLS = {
    "disk list":        ("List all disks/partitions",  lambda: run("lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT")),
    "disk usage":       ("Disk usage by directory",    lambda p: run(f"du -sh {p}/* 2>/dev/null | sort -hr | head -20")),
    "mount list":       ("Show mounted filesystems",   lambda: run("mount | column -t")),
    "mount disk":       ("Mount a disk",               lambda d,p: run(f"mkdir -p {p} && mount {d} {p} && echo 'Mounted {d} → {p}'")),
    "unmount":          ("Unmount a filesystem",       lambda p: run(f"umount {p} && echo 'Unmounted {p}'")),
    "find file":        ("Search for a file",          lambda q: run(f"find / -name '*{q}*' 2>/dev/null | head -20")),
    "file info":        ("File details",               lambda f: run(f"ls -lah {f} && file {f} && stat {f}")),
    "trash file":       ("Move file to trash",         lambda f: _trash(f)),
    "trash list":       ("List trash",                 lambda: run("ls -lh ~/.tajados-trash/ 2>/dev/null || echo 'Trash empty'")),
    "trash restore":    ("Restore from trash",         lambda f: _restore(f)),
    "trash empty":      ("Empty trash",                lambda: run("rm -rf ~/.tajados-trash/* && echo 'Trash emptied'")),
    "backup create":    ("Create a backup",            lambda s,d: run(f"rsync -av --progress {s} {d}")),
    "disk check":       ("Check filesystem integrity", lambda d: run(f"fsck -n {d} 2>/dev/null || echo 'Use: umount first, then fsck {d}'")),
    "large files":      ("Find largest files",         lambda p: run(f"find {p} -type f -exec du -sh {{}} + 2>/dev/null | sort -hr | head -20")),
    "permissions fix":  ("Fix common permissions",     lambda p: run(f"chmod -R 755 {p} && chown -R root:root {p}")),
    "symlink create":   ("Create a symlink",           lambda s,d: run(f"ln -sf {s} {d} && echo 'Link: {d} → {s}'")),
}

def _trash(f):
    trash = os.path.expanduser("~/.tajados-trash")
    os.makedirs(trash, exist_ok=True)
    dest = os.path.join(trash, f"{os.path.basename(f)}.{int(time.time())}")
    shutil.move(f, dest)
    return f"Moved to trash: {dest}"

def _restore(name):
    trash = os.path.expanduser("~/.tajados-trash")
    files = [x for x in os.listdir(trash) if x.startswith(name)]
    if not files:
        return f"Not found in trash: {name}"
    src = os.path.join(trash, sorted(files)[-1])
    dest = os.path.join(os.getcwd(), name)
    shutil.move(src, dest)
    return f"Restored: {dest}"
