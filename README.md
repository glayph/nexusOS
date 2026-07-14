# NEXUS OS 🚀
> Agentic AI Linux Distribution — Powered by Anthropic Claude

## 📥 Download
Go to [Releases](../../releases) and download `nexus.iso`.

## 🔧 Stack
| Item | Detail |
|---|---|
| Base OS | Ubuntu 24.04 Noble |
| Kernel | Linux 6.8.0-134-generic |
| Boot | BIOS + UEFI |
| AI Agent | Anthropic claude-sonnet-4-6 |
| Auto-launch | Yes (tty1 on boot) |

## 🛠 Usage
```bash
# Flash to USB
dd if=nexus.iso of=/dev/sdX bs=4M status=progress

# Set API key after boot
echo "sk-ant-..." > /etc/nexus/api.key
```

## 🤖 Nexus AI Agent
On boot, the system auto-logins as root and launches the NEXUS AI agent.
With an Anthropic API key → full natural language system control.
Without a key → offline mode with direct shell commands.

---
**Built with Claude AI**
