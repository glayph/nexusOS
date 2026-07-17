#!/bin/bash
# ============================================================
#  TajaOS — Main Entry Point
#  Unified command for all TajaOS system tools
# ============================================================
set -euo pipefail

VERSION="2.0.0"
TAJADOS_DIR="/usr/local/lib/tajados"
CONFIG_DIR="/etc/tajados"
STATE_DIR="/var/lib/tajados"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'

usage() {
  cat << USAGE
╭──────────────────────────────────────────────╮
│  TajaOS v$VERSION — System Management CLI     │
╰──────────────────────────────────────────────╯

System:
  os doctor              System health check
  os config              System configuration
  os profile             Configuration profiles
  os init                Initialize system

Shell:
  os shell               TUI shell menu
  os history             Interactive history search
  os session-save        Save shell session
  os session-load        Load shell session

Network:
  os net                 Network manager (tajanet)
  os wifi                Wi-Fi scan & connect
  os speed               Network speed test
  os diag                Network diagnostics

Services:
  os svc                 Service manager (tajainit)
  os health              Service health report
  os boot-analyze        Boot performance analysis

Storage:
  os persist             Persistence manager
  os snapshot            Snapshot management
  os vault               Encrypted vault
  os trash               Recycle bin
  os disk                Disk management (list/mount/format)
  os fm                  File manager TUI

Packages:
  os pkg                 Package manager (tajapkg)
  os update              System update

Development:
  os dev                 Developer toolkit (tajadev)
  os container           Container management
  os vm                  VM management
  os logs                Log viewer
  os monitor             Process monitor

Security:
  os sec                 Security toolkit (tajasec)
  os harden              Apply hardening
  os audit               Security audit
  os fw                  Firewall management

AI:
  os ai                  AI toolkit (tajaai)
  os chat                Chat with AI
  os codegen             Code generation

Recovery:
  os recover             Recovery tools (tajarecover)
  os boot-repair         Repair GRUB
  os rollback            Rollback snapshot
  os factory-reset       Reset to defaults

Media:
  os media               Media tools (tajamedia)
  os record              Screen recording
  os qr                  QR code tools
  os edit <file>         Open file in editor (nano/vi)

Dev:
  os git                 Git status shortcut
  os clone <url>         Git clone

Build:
  os build               Build pipeline (tajabuild)
  os release             Prepare release
  os ota                 OTA update

Info:
  os version             Show version
  os help                Show this help
  os commands            List all commands
USAGE
}

list_commands() {
  echo "Available os commands:"
  grep -E '^\s+os [a-z]' "$0" 2>/dev/null | sed 's/^\s*//' || echo "  os help"
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 0; }

  case "$1" in
    help|--help|-h) usage ;;
    version|--version|-v) echo "TajaOS v$VERSION" ;;
    commands) list_commands ;;

    # Doctor
    doctor|health-check)
      tajarecover doctor ;;

    # Config
    config) shift; tajados "$@" ;;
    profile) shift; tajados profile "$@" ;;
    init) tajados init ;;

    # Shell
    shell) tajashell menu ;;
    history) tajashell history ;;
    session-save) shift; tajashell session-save "$@" ;;
    session-load) shift; tajashell session-load "$@" ;;

    # Network
    net) shift; tajanet "$@" ;;
    wifi) shift; tajanet wifi "$@" ;;
    speed) tajanet speed ;;
    diag) tajanet diag ;;

    # Services
    svc) shift; tajainit "$@" ;;
    health) tajainit health-report ;;
    boot-analyze) tajainit boot-analyze ;;
    boot-optimize) tajainit boot-optimize ;;

    # Storage
    persist) shift; tajados-persist "$@" ;;
    snapshot)
      if [[ $# -lt 2 ]]; then
        tajados-persist snapshot-list
      else
        local _s="$2"; shift 2; tajados-persist "snapshot-$_s" "$@"
      fi
      ;;
    vault)
      if [[ $# -lt 2 ]]; then
        tajasec vault-list
      else
        local _v="$2"; shift 2; tajasec "vault-$_v" "$@"
      fi
      ;;
    trash) shift; tajasec trash "$@" ;;
    disk)
      if [[ $# -lt 2 ]]; then
        tajasec disk-list
      else
        local _d="$2"; shift 2; tajasec "disk-$_d" "$@"
      fi
      ;;
    fm) shift; tajasec fm "$@" ;;

    # Packages
    pkg) shift; tajapkg "$@" ;;
    update) tajapkg update ;;

    # Development
    dev) shift; tajadev "$@" ;;
    container)
      if [[ $# -lt 2 ]]; then
        echo "Usage: os container create|run|shell|list|stop"
        exit 1
      else
        local _c="$2"; shift 2; tajadev "container-$_c" "$@"
      fi
      ;;
    vm)
      if [[ $# -lt 2 ]]; then
        echo "Usage: os vm create|start|list"
        exit 1
      else
        local _v="$2"; shift 2; tajadev "vm-$_v" "$@"
      fi
      ;;
    logs) shift; tajadev logs "$@" ;;
    monitor) tajadev monitor ;;

    # Security
    sec) shift; tajasec "$@" ;;
    harden) tajasec harden-apply ;;
    audit) tajasec audit-view ;;
    fw) shift; tajanet fw "$@" ;;

    # AI
    ai) shift; tajaai "$@" ;;
    chat) tajaai chat ;;
    codegen) shift; tajaai codegen "$@" ;;

    # Recovery
    recover) shift; tajarecover "$@" ;;
    boot-repair) tajarecover boot-repair ;;
    rollback) tajarecover rollback ;;
    factory-reset) tajarecover factory-reset ;;

    # Media
    media) shift; tajamedia "$@" ;;
    record) shift; tajamedia record "$@" ;;
    qr)
      if [[ $# -lt 2 ]]; then
        echo "Usage: os qr encode|decode"
        exit 1
      else
        local _q="$2"; shift 2; tajamedia "qr-$_q" "$@"
      fi
      ;;

    # Editor
    edit)
      shift
      local editor="${EDITOR:-nano}"
      "$editor" "$@" ;;

    # Git
    git) git status 2>/dev/null || echo "Not a git repository" ;;
    clone) shift; git clone "$@" ;;

    # Build
    build) shift; tajabuild "$@" ;;
    release) shift; tajabuild release "$@" ;;
    ota)
      if [[ $# -lt 2 ]]; then
        echo "Usage: os ota prepare|apply"
        exit 1
      else
        local _o="$2"; shift 2; tajabuild "ota-$_o" "$@"
      fi
      ;;

    # TUI
    tui) tajashell menu ;;
    setup) nexus-setup ;;
    shortcuts|help-screen)
      cat << 'SHORTCUTS'
╭───────────────────────────────────╮
│  TajaOS Keyboard Shortcuts       │
├───────────────────────────────────┤
│  Ctrl+R     History search (TUI) │
│  Ctrl+P     Split pane vertical  │
│  Ctrl+V     Split pane horizontal│
│  Tab        Auto-completion      │
│  ↑↓        Navigate menus       │
│  Enter     Select menu item      │
│  Esc/q     Back / Exit           │
│  Ctrl+C    Cancel / Interrupt    │
│  Ctrl+L    Clear screen          │
│  Ctrl+D    Logout / EOF          │
│  os help   Show all commands     │
│  os tui    Launch TUI menu       │
╰───────────────────────────────────╯
SHORTCUTS
      ;;

    *)
      echo -e "${R}Unknown command: $1${N}"
      echo "Try: os help"
      exit 1
      ;;
  esac
}

main "$@"