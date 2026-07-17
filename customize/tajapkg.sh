#!/bin/bash
# ============================================================
#  TajaPkg — Package Manager
#  Install, remove, search, update, build from source
# ============================================================
set -euo pipefail

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
log()  { echo -e "${C}[TajaPkg]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

TAJADOS_DIR="/usr/local/lib/tajados"
STATE_DIR="/var/lib/tajados"
CACHE_DIR="$STATE_DIR/package-cache"
mkdir -p "$CACHE_DIR"
PKG_REGISTRY="$TAJADOS_DIR/dev/registry"

pkg_search() { apt-cache search "$1" 2>/dev/null | head -30; }
pkg_info() { apt-cache show "$1" 2>/dev/null; }
pkg_install() { apt-get install -y --no-install-recommends "$@" && ok "Installed: $*"; }
pkg_remove() { apt-get purge -y "$@" && ok "Removed: $*"; }
pkg_update() { apt-get update -qq && apt-get upgrade -y && ok "System updated"; }
pkg_list_installed() { dpkg -l | grep '^ii' | awk '{print $2}'; }
pkg_list_updates() { apt list --upgradable 2>/dev/null; }
pkg_clean() { apt-get clean && apt-get autoremove -y --purge && ok "Cleaned"; }

# Offline cache
pkg_cache_download() {
  local pkg="$1"
  cd "$CACHE_DIR"
  apt-get download "$pkg"
  ok "Cached: $pkg"
}

pkg_cache_list() { ls -1 "$CACHE_DIR" 2>/dev/null; }
pkg_cache_install() { dpkg -i "$CACHE_DIR"/*.deb 2>/dev/null && apt-get install -f -y && ok "Installed from cache"; }

# Build from source
pkg_build() {
  local src="$1" tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  cd "$tmpdir"
  git clone --depth=1 "$src" src
  cd src
  [[ -f Makefile ]] && make && make install
  [[ -f meson.build ]] && meson setup build && meson compile -C build && meson install -C build
  [[ -f CMakeLists.txt ]] && cmake -B build && cmake --build build && cmake --install build
  ok "Built from source: $src"
}

# Plugin registry
pkg_register_plugin() {
  local name="$1" url="$2" desc="$3"
  mkdir -p "$PKG_REGISTRY"
  echo "$url|$desc" > "$PKG_REGISTRY/$name.plugin"
  ok "Plugin registered: $name"
}

pkg_install_plugin() {
  local name="$1"
  local file="$PKG_REGISTRY/$name.plugin"
  [[ -f "$file" ]] || die "Plugin not found: $name"
  local url=$(cut -d'|' -f1 < "$file")
  pkg_build "$url"
}

pkg_list_plugins() {
  for f in "$PKG_REGISTRY"/*.plugin; do
    [[ -f "$f" ]] || continue
    local name=$(basename "$f" .plugin)
    local desc=$(cut -d'|' -f2- < "$f")
    echo "$name - $desc"
  done
}

usage() {
  cat << USAGE
Usage: tajapkg <command> [args]

  search <query>         Search packages
  info <pkg>             Package info
  install <pkg...>       Install packages
  remove <pkg...>        Remove packages
  update                 Update system
  list                   List installed
  updates                List available updates
  clean                  Clean cache
  cache-dl <pkg>         Download to cache
  cache-list             List cached packages
  cache-install          Install from cache
  build <git-url>        Build from source
  plugin-reg <name> <url> <desc>  Register plugin
  plugin-install <name>  Install plugin
  plugin-list            List plugins
USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    search) pkg_search "$@" ;;
    info) pkg_info "$@" ;;
    install) pkg_install "$@" ;;
    remove) pkg_remove "$@" ;;
    update) pkg_update ;;
    list) pkg_list_installed ;;
    updates) pkg_list_updates ;;
    clean) pkg_clean ;;
    cache-dl) pkg_cache_download "$@" ;;
    cache-list) pkg_cache_list ;;
    cache-install) pkg_cache_install ;;
    build) pkg_build "$@" ;;
    plugin-reg) pkg_register_plugin "$@" ;;
    plugin-install) pkg_install_plugin "$@" ;;
    plugin-list) pkg_list_plugins ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"