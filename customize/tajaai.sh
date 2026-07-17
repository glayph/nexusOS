#!/bin/bash
# ============================================================
#  TajaAI — Local LLM & AI Toolkit
#  Model runner, prompt vault, code generation, embeddings
# ============================================================
set -euo pipefail

TAJADOS_DIR="/usr/local/lib/tajados"
STATE_DIR="/var/lib/tajados"
CONFIG_DIR="/etc/tajados"
AI_DIR="$STATE_DIR/ai"
MODELS_DIR="$AI_DIR/models"
PROMPTS_DIR="$AI_DIR/prompts"
EMBED_DIR="$AI_DIR/embeddings"

mkdir -p "$MODELS_DIR" "$PROMPTS_DIR" "$EMBED_DIR"

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[TajaAI]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

# Model management
ai_model_list() {
  echo "=== Installed Models ==="
  ls -1 "$MODELS_DIR" 2>/dev/null || echo "None"
  echo ""
  echo "=== Model Runner ==="
  if command -v ollama &>/dev/null; then
    ollama list 2>/dev/null || echo "ollama running but no models"
  else
    echo "No model runner found (install ollama or llamafile)"
  fi
}

ai_model_download() {
  local model="$1"
  if command -v ollama &>/dev/null; then
    ollama pull "$model"
  else
    warn "ollama not installed. Install: curl -fsSL https://ollama.com/install.sh | sh"
  fi
}

ai_model_run() {
  local model="${1:-llama3.2:1b}"
  if command -v ollama &>/dev/null; then
    ollama run "$model"
  else
    warn "ollama not installed"
  fi
}

# Prompt vault
ai_prompt_save() {
  local name="$1"
  read -rp "Prompt: " prompt
  echo "$prompt" > "$PROMPTS_DIR/$name.prompt"
  ok "Prompt saved: $name"
}

ai_prompt_get() {
  local name="$1"
  cat "$PROMPTS_DIR/$name.prompt" 2>/dev/null || die "Prompt not found: $name"
}

ai_prompt_list() {
  for f in "$PROMPTS_DIR"/*.prompt; do
    [[ -f "$f" ]] || continue
    local name=$(basename "$f" .prompt)
    echo "  $name: $(head -c 60 < "$f")..."
  done
}

ai_prompt_delete() {
  rm -f "$PROMPTS_DIR/$1.prompt"
  ok "Prompt deleted: $1"
}

# Chat interface
ai_chat() {
  local model="${1:-llama3.2:1b}"
  if command -v ollama &>/dev/null; then
    ollama run "$model"
  else
    warn "ollama not installed"
  fi
}

ai_ask() {
  local model="${1:-llama3.2:1b}" prompt="$2"
  if command -v ollama &>/dev/null; then
    ollama run "$model" "$prompt"
  else
    warn "ollama not installed"
  fi
}

# Code generation
ai_codegen() {
  local prompt="$1" lang="${2:-bash}"
  local full_prompt="Generate $lang code for: $prompt. Return only the code, no explanation."
  if command -v ollama &>/dev/null; then
    ollama run llama3.2:1b "$full_prompt"
  else
    warn "ollama not installed"
  fi
}

# Embeddings
ai_embed() {
  local text="$1" output="${2:-}"
  echo "Embeddings require ollama or python backend"
}

# TUI
ai_tui() {
  local items=("Chat with LLM" "Ask a Question" "Generate Code" "List Models" "Download Model" "Manage Prompts")
  local selected=0
  while true; do
    clear
    for i in "${!items[@]}"; do
      if [[ $i -eq $selected ]]; then printf "\033[7m %s \033[0m\n" "${items[i]}"; else echo " ${items[i]}"; fi
    done
    IFS= read -rsn1 key
    case "$key" in
      $'\n'|$'\r')
        case $selected in
          0) echo "Entering chat mode..."; ai_chat;;
          1) read -rp "Question: " q; ai_ask "" "$q"; read -rp "Press Enter..." ;;
          2) read -rp "Code for: " p; ai_codegen "$p"; read -rp "Press Enter..." ;;
          3) ai_model_list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
          4) read -rp "Model name: " m; ai_model_download "$m" ;;
          5) ai_prompt_list | while read line; do echo "  $line"; done; read -rp "Press Enter..." ;;
        esac
        ;;
      '[A') [[ $selected -gt 0 ]] && selected=$((selected-1)) ;;
      '[B') [[ $selected -lt $((${#items[@]}-1)) ]] && selected=$((selected+1)) ;;
      $'\e') return ;;
    esac
  done
}

usage() {
  cat << USAGE
Usage: tajaai <command> [args]

  model-list                 List available models
  model-download <name>      Download model
  model-run [name]           Run interactive chat
  chat [model]               Interactive chat
  ask <model> <question>     Ask a question
  codegen <desc> [lang]      Generate code
  prompt-save <name>         Save prompt
  prompt-get <name>          Get prompt
  prompt-list                List prompts
  prompt-del <name>          Delete prompt
  tui                        Interactive TUI
USAGE
}

main() {
  [[ $# -eq 0 ]] && { ai_tui; exit 0; }
  local cmd="$1"; shift
  case "$cmd" in
    model-list) ai_model_list ;;
    model-download) ai_model_download "$@" ;;
    model-run) ai_model_run "$@" ;;
    chat) ai_chat "$@" ;;
    ask) ai_ask "$@" ;;
    codegen) ai_codegen "$@" ;;
    prompt-save) ai_prompt_save "$@" ;;
    prompt-get) ai_prompt_get "$@" ;;
    prompt-list) ai_prompt_list ;;
    prompt-del) ai_prompt_delete "$@" ;;
    tui) ai_tui ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"