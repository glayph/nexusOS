#!/usr/bin/env python3
"""
NEXUS OS v1.1 — Agentic AI Brain
Pluggable AI provider: Anthropic | OpenAI | Local | External
"""
import os, sys, re, json, time, subprocess, socket, importlib.util
from datetime import datetime
from pathlib import Path

# ── Colours ───────────────────────────────────────────────────────────────────
C="\033[96m"; G="\033[92m"; Y="\033[93m"; R="\033[91m"; B="\033[1m"; D="\033[2m"; N="\033[0m"

BANNER = f"""{B}{C}
  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝ ██╔═══██╗██╔════╝
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║ ██║   ██║╚════██║
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║
{N}  {D}Nexus OS v1.1 — Agentic AI Linux  |  Modular Agent Core{N}
"""

DEFAULT_PROMPT = """You are NEXUS — the AI brain of a custom Linux distribution (Nexus OS v1.1).

System access: full root control, Ubuntu 24.04 Noble base.
Capabilities: system management, networking, security, developer tools, file management.

When executing shell commands, wrap them: <exec>COMMAND</exec>
Keep responses concise and actionable. Support English and Bengali input."""

# ── Config loader ──────────────────────────────────────────────────────────────
def load_config(path="/etc/nexus/agent.conf"):
    cfg = {}
    if not os.path.exists(path):
        return cfg
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            cfg[k.strip()] = v.strip()
    return cfg

def load_system_prompt():
    for p in ["/etc/nexus/agent-prompt.txt", Path.home()/".nexus/agent-prompt.txt"]:
        if os.path.exists(p):
            return open(p).read().strip()
    return DEFAULT_PROMPT

# ── API key ────────────────────────────────────────────────────────────────────
def get_api_key(cfg):
    key_file = cfg.get("AGENT_API_KEY_FILE", "/etc/nexus/api.key")
    for src in [os.environ.get("ANTHROPIC_API_KEY"),
                os.environ.get("OPENAI_API_KEY"),
                os.environ.get("NEXUS_API_KEY"),
                open(key_file).read().strip() if os.path.exists(key_file) else None]:
        if src and src.startswith("sk-"):
            return src
    return None

# ── Skill loader ───────────────────────────────────────────────────────────────
def load_skills(skills_dir="/opt/nexus/skills"):
    skills = {}
    if not os.path.isdir(skills_dir):
        return skills
    for f in os.listdir(skills_dir):
        if not f.endswith(".py") or f.startswith("_"):
            continue
        try:
            spec = importlib.util.spec_from_file_location(f[:-3], f"{skills_dir}/{f}")
            mod  = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            skills.update(getattr(mod, "SKILLS", {}))
        except Exception as e:
            print(f"{Y}[skill] Failed to load {f}: {e}{N}")
    return skills

# ── Audit log ──────────────────────────────────────────────────────────────────
def audit(msg, cfg):
    log_path = cfg.get("AUDIT_LOG", "/var/log/nexus/audit.log")
    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        with open(log_path, "a") as f:
            f.write(f"[{datetime.now().isoformat()}] {msg}\n")
    except:
        pass

# ── Destructive command guard ──────────────────────────────────────────────────
DESTRUCTIVE = ["rm -rf", "mkfs", "dd if=", "format", "fdisk", "> /dev/", "wipefs", "shred"]

def is_destructive(cmd):
    return any(d in cmd for d in DESTRUCTIVE)

def confirm(prompt):
    try:
        return input(f"{Y}[CONFIRM] {prompt} (yes/no): {N}").strip().lower() == "yes"
    except (EOFError, KeyboardInterrupt):
        return False

# ── Shell executor ─────────────────────────────────────────────────────────────
def run_cmd(cmd, cfg):
    audit(f"EXEC: {cmd}", cfg)
    if cfg.get("CONFIRM_DESTRUCTIVE","true") == "true" and is_destructive(cmd):
        if not confirm(f"Destructive command: {cmd}"):
            return "[NEXUS] Command cancelled."
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return ((r.stdout or "") + (r.stderr or "")).strip()[:3000] or "(no output)"
    except subprocess.TimeoutExpired:
        return "[NEXUS] Timed out (30s)"
    except Exception as e:
        return f"[NEXUS] Error: {e}"

# ── Memory store ───────────────────────────────────────────────────────────────
MEMORY_FILE = Path("/etc/nexus/memory.json")

def load_memory():
    try:
        return json.loads(MEMORY_FILE.read_text()) if MEMORY_FILE.exists() else {}
    except:
        return {}

def save_memory(mem):
    try:
        MEMORY_FILE.parent.mkdir(parents=True, exist_ok=True)
        MEMORY_FILE.write_text(json.dumps(mem, indent=2))
    except:
        pass

# ── AI Providers ───────────────────────────────────────────────────────────────
def call_anthropic(messages, api_key, model, system):
    import urllib.request
    payload = json.dumps({
        "model": model or "claude-sonnet-4-6",
        "max_tokens": 1024,
        "system": system,
        "messages": messages
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=payload,
        headers={"x-api-key": api_key,
                 "anthropic-version": "2023-06-01",
                 "content-type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["content"][0]["text"]

def call_openai(messages, api_key, model, system):
    import urllib.request
    all_msgs = [{"role":"system","content":system}] + messages
    payload = json.dumps({"model": model or "gpt-4o",
                          "messages": all_msgs, "max_tokens":1024}).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=payload,
        headers={"Authorization": f"Bearer {api_key}",
                 "Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["choices"][0]["message"]["content"]

def call_local(messages, model, endpoint, system):
    import urllib.request
    all_msgs = [{"role":"system","content":system}] + messages
    payload = json.dumps({"model": model or "llama3",
                          "messages": all_msgs, "stream": False}).encode()
    req = urllib.request.Request(
        endpoint or "http://localhost:11434/api/chat",
        data=payload, headers={"Content-Type":"application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["message"]["content"]

def call_external(user_input, agent_cmd, agent_args=""):
    """Pass input to external agent (OpenClaw, Hermes, etc.) via subprocess"""
    full_cmd = f"{agent_cmd} {agent_args}"
    r = subprocess.run(full_cmd, shell=True, input=user_input,
                       capture_output=True, text=True, timeout=60)
    return (r.stdout or r.stderr or "[External agent returned no output]").strip()

def call_ai(messages, cfg, api_key, system):
    provider = cfg.get("AGENT_PROVIDER", "anthropic").lower()
    model    = cfg.get("AGENT_MODEL", "")
    try:
        if provider == "anthropic":
            return call_anthropic(messages, api_key, model, system)
        elif provider == "openai":
            return call_openai(messages, api_key, model, system)
        elif provider == "local":
            return call_local(messages, cfg.get("LOCAL_MODEL",""),
                              cfg.get("LOCAL_ENDPOINT",""), system)
        elif provider == "external":
            return call_external(messages[-1]["content"],
                                 cfg.get("EXTERNAL_AGENT_CMD",""),
                                 cfg.get("EXTERNAL_AGENT_ARGS",""))
        else:
            return "[NEXUS] AI provider disabled."
    except ConnectionRefusedError:
        return "[NEXUS] Cannot connect to AI provider. Check connection."
    except Exception as e:
        return f"[NEXUS] AI error: {e}"

# ── System info ────────────────────────────────────────────────────────────────
def sysinfo():
    def q(cmd):
        try: return subprocess.run(cmd,shell=True,capture_output=True,text=True,timeout=3).stdout.strip()
        except: return "?"
    with open("/proc/uptime") as f: s=float(f.read().split()[0])
    print(f"\n{D}  Host   : {q('hostname')} | {q('hostname -I').split()[0] if q('hostname -I') else 'no IP'}")
    print(f"  Kernel : {q('uname -r')}")
    print(f"  Uptime : {int(s//3600)}h {int((s%3600)//60)}m | Load: {q('cut -d\" \" -f1-3 /proc/loadavg')}")
    print(f"  Memory : {q('free -h | grep Mem | awk \"{print $3\\\"/\\\"$2}\"')}")
    print(f"  Disk   : {q('df -h / | tail -1 | awk \"{print $3\\\"/\\\"$2}\"')}{N}\n")

# ── Status bar ─────────────────────────────────────────────────────────────────
def status_bar(cfg):
    try:
        with open("/proc/loadavg") as f: load=f.read().split()[0]
        ts = datetime.now().strftime("%H:%M:%S")
        provider = cfg.get("AGENT_PROVIDER","?")
        print(f"{D}[{ts}] load:{load}  agent:{provider}{N}")
    except: pass

# ── Skill intent matching ──────────────────────────────────────────────────────
def match_skill(user_input, skills):
    lower = user_input.lower()
    for key, val in skills.items():
        if key in lower:
            return key, val
    return None, None

# ── Offline commands ───────────────────────────────────────────────────────────
OFFLINE = {
    "status": "uptime && free -h && df -h /",
    "ps":     "ps aux --sort=-%cpu | head -15",
    "net":    "ip -br addr && ss -tuln",
    "log":    "journalctl -n 30 --no-pager",
    "disk":   "df -h && lsblk",
    "top":    "top -bn1 | head -20",
}

# ── Main REPL ───────────────────────────────────────────────────────────────────
def main():
    # Run startup script
    for s in ["/etc/nexus/startup.sh", "/etc/nexus/startup.py"]:
        if os.path.exists(s): subprocess.run(["bash" if s.endswith(".sh") else "python3", s])

    # First boot wizard
    if not os.path.exists("/etc/nexus/.setup-done"):
        run_cmd("nexus-setup", {})

    print(BANNER)
    sysinfo()

    cfg         = load_config()
    api_key     = get_api_key(cfg)
    system_p    = load_system_prompt()
    skills      = load_skills(cfg.get("SKILLS_DIR", "/opt/nexus/skills"))
    memory      = load_memory()
    provider    = cfg.get("AGENT_PROVIDER","anthropic").lower()
    online      = api_key is not None or provider in ("local","external")

    if online:
        print(f"{G}[NEXUS] AI active — provider: {provider}{N}")
    else:
        print(f"{Y}[NEXUS] Offline mode{N} {D}(set API key in /etc/nexus/api.key){N}")

    if skills:
        print(f"{D}[NEXUS] {len(skills)} skills loaded{N}")
    print(f"\n{C}Commands: 'help' 'sysinfo' 'clear' 'memory' 'exit'{N}\n")

    conversation = []

    while True:
        try:
            status_bar(cfg)
            user_input = input(f"{B}{C}nexus ❯{N} ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n{Y}[NEXUS] Goodbye.{N}"); break

        if not user_input: continue

        audit(f"INPUT: {user_input}", cfg)

        # ── Built-ins ──────────────────────────────────────────────────────
        if user_input.lower() in ("exit","quit","shutdown"):
            print(f"{Y}[NEXUS] Powering down.{N}"); break

        if user_input.lower() == "clear":
            os.system("clear"); print(BANNER); continue

        if user_input.lower() in ("sysinfo","status"):
            sysinfo(); continue

        if user_input.lower() == "help":
            print(f"""
{C}Built-in commands:{N}
  sysinfo / status  — System information
  clear             — Clear screen
  memory            — Show stored preferences
  memory set k=v    — Store a preference
  skills            — List loaded skills
  help              — This help
  exit              — Quit

{C}Utility commands:{N}
  nexus-doctor      — Full health check
  nexus-monitor     — Live dashboard
  nexus-pkg         — Package manager
  nexus-skill       — Plugin manager
"""); continue

        if user_input.lower() == "skills":
            print(f"\n{C}Loaded skills ({len(skills)}):{N}")
            for k in sorted(skills): print(f"  • {k}")
            print(); continue

        if user_input.lower() == "memory":
            print(json.dumps(memory, indent=2) if memory else "  (empty)"); continue

        if user_input.lower().startswith("memory set "):
            kv = user_input[11:].strip()
            if "=" in kv:
                k, _, v = kv.partition("=")
                memory[k.strip()] = v.strip()
                save_memory(memory)
                print(f"{G}[NEXUS] Saved: {k.strip()} = {v.strip()}{N}")
            continue

        # ── Skill matching ─────────────────────────────────────────────────
        skill_key, skill_val = match_skill(user_input, skills)
        if skill_key and skill_val:
            try:
                fn = skill_val[1] if isinstance(skill_val, tuple) else skill_val
                result = fn()
                print(f"\n{D}{result}{N}\n")
                audit(f"SKILL: {skill_key}", cfg)
                continue
            except TypeError:
                pass  # skill needs args — fall through to AI

        # ── AI or offline ──────────────────────────────────────────────────
        if online:
            conversation.append({"role": "user", "content": user_input})
            print(f"{D}[NEXUS] Processing...{N}")
            response = call_ai(conversation, cfg, api_key, system_p)

            exec_blocks = re.findall(r"<exec>(.*?)</exec>", response, re.DOTALL)
            clean = re.sub(r"<exec>.*?</exec>", "", response, flags=re.DOTALL).strip()

            if clean: print(f"\n{C}[NEXUS]{N} {clean}\n")

            for cmd in exec_blocks:
                cmd = cmd.strip()
                print(f"{Y}[NEXUS] Running:{N} {D}{cmd}{N}")
                out = run_cmd(cmd, cfg)
                print(f"{D}{out}{N}\n")
                conversation.append({"role":"assistant","content":response})
                conversation.append({"role":"user","content":f"Command output:\n{out}"})
                followup = call_ai(conversation, cfg, api_key, system_p)
                fc = re.sub(r"<exec>.*?</exec>","",followup,flags=re.DOTALL).strip()
                if fc: print(f"{C}[NEXUS]{N} {fc}\n")
                conversation.append({"role":"assistant","content":followup})
                break
            else:
                conversation.append({"role":"assistant","content":response})

            if len(conversation) > int(cfg.get("MAX_HISTORY","40")):
                conversation = conversation[-40:]
        else:
            lower = user_input.lower()
            cmd = next((v for k,v in OFFLINE.items() if k in lower), user_input)
            print(f"\n{D}{run_cmd(cmd, cfg)}{N}\n")

if __name__ == "__main__":
    main()
