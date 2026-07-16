#!/usr/bin/env python3

import os, sys, re, json, time, subprocess, socket, platform
from datetime import datetime

C  = "\033[96m"; G = "\033[92m"; Y = "\033[93m"
R  = "\033[91m"; B = "\033[1m";  D = "\033[2m"
N  = "\033[0m"

BANNER = (
    f"\n  {C}nexus  •  Agentic AI Linux  •  Anthropic Claude{N}\n"
    f"  {D}{'─'*50}{N}\n"
)

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
    for path in ["/etc/nexus/agent-prompt.txt",
                 os.path.expanduser("~/.nexus/agent-prompt.txt")]:
        try:
            with open(path) as f:
                return f.read().strip()
        except FileNotFoundError:
            pass
    return DEFAULT_PROMPT

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

def get_sysinfo():
    info = {}
    try:
        with open("/proc/uptime") as f:
            s = float(f.read().split()[0])
            info["uptime"] = f"{int(s//3600)}h {int((s%3600)//60)}m"
        with open("/proc/loadavg") as f:
            info["load"] = " ".join(f.read().split()[:3])
        mem = subprocess.run(["free", "-h"], capture_output=True, text=True)
        info["memory"] = mem.stdout.split("\n")[1] if mem.stdout else "?"
        disk = subprocess.run(["df", "-h", "/"], capture_output=True, text=True)
        info["disk"] = disk.stdout.split("\n")[1] if disk.stdout else "?"
        info["hostname"] = socket.gethostname()
        info["kernel"]   = platform.release()
        ip = subprocess.run(["hostname", "-I"], capture_output=True, text=True)
        info["ip"] = ip.stdout.strip().split()[0] if ip.stdout.strip() else "no IP"
    except Exception as e:
        info["error"] = str(e)
    return info

def print_sysinfo():
    i = get_sysinfo()
    mem_parts = i.get('memory', '').split()
    mem_str = f"{mem_parts[2]}/{mem_parts[1]}" if len(mem_parts) >= 3 else i.get('memory', '?')
    print(
        f"  {D}host {i.get('hostname','?')}  •  "
        f"kernel {i.get('kernel','?')}  •  "
        f"ip {i.get('ip','?')}  •  "
        f"up {i.get('uptime','?')}{N}"
    )
    print(
        f"  {D}load {i.get('load','?')}  •  "
        f"mem {mem_str}  •  "
        f"disk {i.get('disk','?')}{N}\n"
    )

def run_cmd(cmd: str) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        out = (r.stdout or "") + (r.stderr or "")
        return out.strip()[:3000] or "(no output)"
    except subprocess.TimeoutExpired:
        return "[nexus] Command timed out (30s)"
    except Exception as e:
        return f"[nexus] Error: {e}"

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
        return f"[nexus] API error: {e}"

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
    return run_cmd(user_input)

def status_bar():
    i = get_sysinfo()
    ts = datetime.now().strftime("%H:%M:%S")
    mem_parts = i.get('memory', '').split()
    mem_str = f"{mem_parts[2]}/{mem_parts[1]}" if len(mem_parts) >= 3 else i.get('memory', '?')
    print(
        f"{D}{ts}  "
        f"load {i.get('load','?').split()[0]}  "
        f"mem {mem_str}  "
        f"up {i.get('uptime','?')}{N}"
    )

def main():
    startup = "/etc/nexus/startup.sh"
    if os.path.exists(startup):
        subprocess.run(["bash", startup], check=False)

    print(BANNER)

    api_key = get_api_key()
    system_prompt = load_custom_prompt()

    if api_key:
        print(f"  {C}{B}AI mode  •  Connected{N}")
        online = True
    else:
        print(f"  {Y}Offline mode{N}")
        print(f"  {D}set key: echo 'sk-ant-...' > /etc/nexus/api.key{N}")
        online = False

    print()
    print_sysinfo()

    conversation = []

    while True:
        try:
            status_bar()
            user_input = input(f"  {C}❯{N} ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n  {D}shutdown  •  goodbye{N}")
            sys.exit(0)

        if not user_input:
            continue

        if user_input.lower() in ("exit", "quit", "shutdown", "poweroff"):
            print(f"  {D}shutdown  •  goodbye{N}")
            sys.exit(0)

        if user_input.lower() == "clear":
            os.system("clear")
            print(BANNER)
            continue

        if user_input.lower() in ("sysinfo", "status"):
            print_sysinfo()
            continue

        if user_input.lower() == "help":
            print(f"\n  {C}commands{N}")
            print(f"  {D}status{N}   system information")
            print(f"  {D}clear{N}    clear screen")
            print(f"  {D}exit{N}     shutdown")
            print(f"  {D}help{N}     this message")
            print(f"  {D}<any>{N}     sent to AI agent\n")
            continue

        if online:
            conversation.append({"role": "user", "content": user_input})
            print(f"  {D}…{N}")

            response = call_api(conversation, api_key, system_prompt)

            exec_blocks = re.findall(r"<exec>(.*?)</exec>", response, re.DOTALL)
            clean = re.sub(r"<exec>.*?</exec>", "", response, flags=re.DOTALL).strip()

            if clean:
                print(f"\n  {clean}\n")

            for cmd in exec_blocks:
                cmd = cmd.strip()
                print(f"  {C}▸{N} {cmd}")
                output = run_cmd(cmd)
                if output.strip():
                    print(f"{output}\n")

                conversation.append({"role": "assistant", "content": response})
                conversation.append({"role": "user",
                                     "content": f"Command output:\n{output}"})
                followup = call_api(conversation, api_key, system_prompt)
                followup_clean = re.sub(r"<exec>.*?</exec>", "", followup,
                                        flags=re.DOTALL).strip()
                if followup_clean:
                    print(f"  {followup_clean}\n")
                conversation.append({"role": "assistant", "content": followup})
                break
            else:
                conversation.append({"role": "assistant", "content": response})

            if len(conversation) > 40:
                conversation = conversation[-40:]
        else:
            out = handle_offline(user_input)
            print(f"\n{out}\n")

if __name__ == "__main__":
    main()
