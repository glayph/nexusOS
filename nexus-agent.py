#!/usr/bin/env python3
"""
NEXUS — Agentic AI Linux Distribution Brain
Core AI Agent powered by Anthropic Claude
"""

import os, sys, re, json, time, subprocess, socket, platform
from datetime import datetime

# ── ANSI colours ──────────────────────────────────────────────────────────────
CYAN  = "\033[96m"; GREEN  = "\033[92m"; YELLOW = "\033[93m"
RED   = "\033[91m"; BLUE   = "\033[94m"; BOLD   = "\033[1m"
DIM   = "\033[2m";  RESET  = "\033[0m"

BANNER = f"""
{CYAN}{BOLD}
███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝ ██╔═══██╗██╔════╝
██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║ ██║   ██║╚════██║
██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║
╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝  ╚═════╝ ╚══════╝
{RESET}{GREEN}  Agentic AI Linux — Brain v1.0   |   Powered by Anthropic Claude{RESET}
"""

# ── System prompt ──────────────────────────────────────────────────────────────
DEFAULT_PROMPT = """You are NEXUS — the intelligent brain of a custom Agentic AI Linux distribution.

Your capabilities:
- Full root-level system control and monitoring
- Process, file system, network, and hardware management
- Package management and software orchestration
- AI/ML environment provisioning
- Security scanning and intrusion detection
- Natural language command interpretation → shell execution

Personality: Analytical, proactive, concise, precise. You are JARVIS for Linux.

When the user asks you to run a command or perform a system action, output it wrapped as:
<exec>COMMAND_HERE</exec>

Rules:
- Keep responses concise and actionable
- For system info queries, gather and present data clearly
- You have full root access on Ubuntu 24.04 (Nexus OS 1.0)
- Support both English and Bengali input"""

def load_custom_prompt():
    """Load custom agent prompt if it exists"""
    for path in ["/etc/nexus/agent-prompt.txt",
                 os.path.expanduser("~/.nexus/agent-prompt.txt")]:
        try:
            with open(path) as f:
                return f.read().strip()
        except FileNotFoundError:
            pass
    return DEFAULT_PROMPT

# ── API key resolution ─────────────────────────────────────────────────────────
def get_api_key():
    sources = [
        os.environ.get("ANTHROPIC_API_KEY"),
        os.environ.get("NEXUS_API_KEY"),
    ]
    for path in ["/etc/nexus/api.key", os.path.expanduser("~/.nexus/api.key")]:
        try:
            with open(path) as f:
                sources.append(f.read().strip())
        except FileNotFoundError:
            pass
    return next((k for k in sources if k and k.startswith("sk-")), None)

# ── System telemetry ───────────────────────────────────────────────────────────
def get_sysinfo():
    info = {}
    try:
        # Uptime
        with open("/proc/uptime") as f:
            s = float(f.read().split()[0])
            info["uptime"] = f"{int(s//3600)}h {int((s%3600)//60)}m"
        # Load
        with open("/proc/loadavg") as f:
            info["load"] = " ".join(f.read().split()[:3])
        # Memory
        mem = subprocess.run(["free", "-h"], capture_output=True, text=True)
        info["memory"] = mem.stdout.split("\n")[1] if mem.stdout else "?"
        # Disk
        disk = subprocess.run(["df", "-h", "/"], capture_output=True, text=True)
        info["disk"] = disk.stdout.split("\n")[1] if disk.stdout else "?"
        # Hostname / kernel
        info["hostname"] = socket.gethostname()
        info["kernel"]   = platform.release()
        # IP
        ip = subprocess.run(["hostname", "-I"], capture_output=True, text=True)
        info["ip"] = ip.stdout.strip().split()[0] if ip.stdout.strip() else "no IP"
    except Exception as e:
        info["error"] = str(e)
    return info

def print_sysinfo():
    i = get_sysinfo()
    print(f"\n{DIM}  Host  : {i.get('hostname','?')}   |   Kernel : {i.get('kernel','?')}")
    print(f"  IP    : {i.get('ip','?')}   |   Uptime : {i.get('uptime','?')}")
    print(f"  Load  : {i.get('load','?')}")
    print(f"  Mem   : {i.get('memory','?')}")
    print(f"  Disk  : {i.get('disk','?')}{RESET}\n")

# ── Shell execution ─────────────────────────────────────────────────────────────
def run_cmd(cmd: str) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        out = (r.stdout or "") + (r.stderr or "")
        return out.strip()[:3000] or "(no output)"
    except subprocess.TimeoutExpired:
        return "[NEXUS] Command timed out (30s)"
    except Exception as e:
        return f"[NEXUS] Error: {e}"

# ── Anthropic API call ──────────────────────────────────────────────────────────
def call_api(messages: list, api_key: str, system: str) -> str:
    import urllib.request
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    payload = json.dumps({
        "model": "claude-sonnet-4-6",
        "max_tokens": 1024,
        "system": system,
        "messages": messages,
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=payload, headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)["content"][0]["text"]
    except Exception as e:
        return f"[NEXUS] API error: {e}"

# ── Offline built-in commands ───────────────────────────────────────────────────
OFFLINE_CMDS = {
    "status":  "uptime && free -h && df -h /",
    "ps":      "ps aux --sort=-%cpu | head -20",
    "net":     "ip addr show && echo '---' && ss -tuln",
    "top":     "top -bn1 | head -25",
    "log":     "journalctl -n 30 --no-pager",
    "disk":    "df -h && echo '---' && lsblk",
    "mem":     "free -h && cat /proc/meminfo | head -10",
    "help":    "echo 'Offline commands: status ps net top log disk mem help'",
}

def handle_offline(user_input: str) -> str:
    lower = user_input.lower().strip()
    for key, cmd in OFFLINE_CMDS.items():
        if key in lower:
            return run_cmd(cmd)
    return run_cmd(user_input)  # try as direct shell command

# ── Status bar ─────────────────────────────────────────────────────────────────
def status_bar():
    i = get_sysinfo()
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"{DIM}[{ts}] {i.get('hostname','nexus')} | "
          f"load:{i.get('load','?').split()[0]} | "
          f"up:{i.get('uptime','?')}{RESET}")

# ── Main REPL ───────────────────────────────────────────────────────────────────
def main():
    # Run custom startup script if present
    startup = "/etc/nexus/startup.sh"
    if os.path.exists(startup):
        subprocess.run(["bash", startup], check=False)

    print(BANNER)
    print_sysinfo()

    api_key = get_api_key()
    system_prompt = load_custom_prompt()

    if api_key:
        print(f"{GREEN}[NEXUS] AI mode active — Anthropic Claude connected{RESET}")
        online = True
    else:
        print(f"{YELLOW}[NEXUS] Offline mode — no API key found{RESET}")
        print(f"{DIM}  Add key: echo 'sk-ant-...' > /etc/nexus/api.key{RESET}")
        online = False

    print(f"\n{CYAN}Type your command or question."
          f"  Commands: 'status' 'clear' 'sysinfo' 'exit'{RESET}\n")

    conversation = []

    while True:
        try:
            status_bar()
            user_input = input(f"{BOLD}{CYAN}nexus ❯{RESET} ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n{YELLOW}[NEXUS] Shutdown. Goodbye.{RESET}")
            sys.exit(0)

        if not user_input:
            continue

        # Built-in commands
        if user_input.lower() in ("exit", "quit", "shutdown", "poweroff"):
            print(f"{YELLOW}[NEXUS] Powering down. Stay vigilant.{RESET}")
            sys.exit(0)

        if user_input.lower() == "clear":
            os.system("clear")
            print(BANNER)
            continue

        if user_input.lower() in ("sysinfo", "status"):
            print_sysinfo()
            continue

        if user_input.lower() == "help":
            print(f"\n{CYAN}Built-in commands:{RESET}")
            print("  status / sysinfo — system info")
            print("  clear            — clear screen")
            print("  exit             — shutdown agent")
            print("  help             — this help")
            print(f"\n{CYAN}AI commands:{RESET} anything else → sent to Nexus AI\n")
            continue

        # AI or offline
        if online:
            conversation.append({"role": "user", "content": user_input})
            print(f"{DIM}[NEXUS] Thinking...{RESET}")

            response = call_api(conversation, api_key, system_prompt)

            # Extract and execute <exec> blocks
            exec_blocks = re.findall(r"<exec>(.*?)</exec>", response, re.DOTALL)
            clean = re.sub(r"<exec>.*?</exec>", "", response, flags=re.DOTALL).strip()

            if clean:
                print(f"\n{CYAN}[NEXUS]{RESET} {clean}\n")

            for cmd in exec_blocks:
                cmd = cmd.strip()
                print(f"{YELLOW}[NEXUS] Running: {DIM}{cmd}{RESET}")
                output = run_cmd(cmd)
                print(f"{DIM}{output}{RESET}\n")

                # Feed output back for follow-up
                conversation.append({"role": "assistant", "content": response})
                conversation.append({"role": "user",
                                     "content": f"Command output:\n{output}"})
                followup = call_api(conversation, api_key, system_prompt)
                followup_clean = re.sub(r"<exec>.*?</exec>", "", followup,
                                        flags=re.DOTALL).strip()
                if followup_clean:
                    print(f"{CYAN}[NEXUS]{RESET} {followup_clean}\n")
                conversation.append({"role": "assistant", "content": followup})
                break
            else:
                conversation.append({"role": "assistant", "content": response})

            # Keep context to last 40 messages
            if len(conversation) > 40:
                conversation = conversation[-40:]
        else:
            out = handle_offline(user_input)
            print(f"\n{DIM}{out}{RESET}\n")

if __name__ == "__main__":
    main()
