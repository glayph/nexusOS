#!/bin/bash
# ============================================================
#  TajaBuild — Build & Release Pipeline
#  ISO building, testing, release signing, OTA updates
# ============================================================
set -euo pipefail

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[TajaBuild]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

BUILD_DIR="/build"
ISO_DIR="$BUILD_DIR/iso"
ROOTFS_DIR="$BUILD_DIR/rootfs"

# Build ISO
build_iso() {
  local output="${1:-/tmp/tajados.iso}"
  log "Building TajaOS ISO..."
  cd /opt/tajados 2>/dev/null || cd "$(dirname "$0")/../.." 2>/dev/null || die "TajaOS directory not found"
  make build
  ok "ISO built: $output"
}

build_fast() {
  make build FAST=1
}

build_clean() {
  make build CLEAN=1
}

# Test ISO
build_test_qemu() {
  make qemu 2>&1 &
  log "QEMU started (PID: $!)"
}

build_test_integrity() {
  local iso="${1:-tajaos.iso}"
  [[ -f "$iso" ]] || die "ISO not found"
  sha256sum "$iso"
}

# Release signing
build_sign() {
  local file="$1" key="${2:-}"
  gpg --detach-sign --armor "$file" 2>/dev/null || warn "GPG signing failed"
  ok "Signed: $file"
}

build_verify() {
  local file="$1" sig="${1}.asc"
  gpg --verify "$sig" "$file" 2>/dev/null
}

# Changelog
build_changelog() {
  local range="${1:-HEAD~10..HEAD}"
  git log --oneline "$range" 2>/dev/null || echo "No git history"
}

build_changelog_generate() {
  local version="${1:-$(date +%Y.%m.%d)}"
  cat << CHANGELOG
# Changelog

## Version $version ($(date +%Y-%m-%d))

$(git log --oneline --no-decorate 2>/dev/null | head -50 | sed 's/^/- /')

CHANGELOG
}

# OTA updates
build_ota_prepare() {
  local version="$1" output="${2:-/tmp/ota-update-$version.tar.gz}"
  local files=(
    /usr/local/lib/tajados
    /usr/local/bin/tajados*
    /etc/tajados
    /customize
  )
  tar -czf "$output" "${files[@]}" 2>/dev/null
  ok "OTA update: $output ($(du -h "$output" | cut -f1))"
}

build_ota_apply() {
  local update="$1"
  [[ -f "$update" ]] || die "Update not found"
  tar -xzf "$update" -C / 2>/dev/null
  ok "OTA update applied: $update"
}

# Release
build_release() {
  local version="${1:-$(date +%Y.%m.%d)}"
  local iso="${2:-tajaos.iso}"
  [[ -f "$iso" ]] || die "ISO not found"
  local release_dir="/tmp/release-$version"
  mkdir -p "$release_dir"
  cp "$iso" "$release_dir/"
  build_changelog_generate "$version" > "$release_dir/CHANGELOG.md"
  build_sign "$iso"
  cp "${iso}.asc" "$release_dir/"
  sha256sum "$iso" > "$release_dir/SHA256SUMS"
  ok "Release $version ready: $release_dir"
}

# Version bump
build_version_bump() {
  local part="${1:-patch}"
  local ver_file="VERSION"
  [[ -f "$ver_file" ]] || echo "0.0.0" > "$ver_file"
  local ver=$(cat "$ver_file")
  local major=$(echo "$ver" | cut -d. -f1)
  local minor=$(echo "$ver" | cut -d. -f2)
  local patch=$(echo "$ver" | cut -d. -f3)
  case "$part" in
    major) major=$((major+1)); minor=0; patch=0 ;;
    minor) minor=$((minor+1)); patch=0 ;;
    patch) patch=$((patch+1)) ;;
  esac
  echo "$major.$minor.$patch" > "$ver_file"
  ok "Version bumped to $major.$minor.$patch"
}

usage() {
  cat << USAGE
Usage: tajabuild <command> [args]

  iso [output]              Build ISO
  iso-fast                  Fast rebuild (skip squashfs)
  iso-clean                 Clean build
  test-qemu                 Test in QEMU
  test-integrity [iso]      Verify ISO checksum
  sign <file> [key]         Sign file with GPG
  verify <file>             Verify GPG signature
  changelog [range]         View changelog
  changelog-gen [version]   Generate changelog
  ota-prepare <ver> [out]   Prepare OTA update
  ota-apply <update>        Apply OTA update
  release <version> [iso]   Prepare release
  version-bump [patch|minor|major]  Bump version
USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    iso) build_iso "$@" ;;
    iso-fast) build_fast ;;
    iso-clean) build_clean ;;
    test-qemu) build_test_qemu ;;
    test-integrity) build_test_integrity "$@" ;;
    sign) build_sign "$@" ;;
    verify) build_verify "$@" ;;
    changelog) build_changelog "$@" ;;
    changelog-gen) build_changelog_generate "$@" ;;
    ota-prepare) build_ota_prepare "$@" ;;
    ota-apply) build_ota_apply "$@" ;;
    release) build_release "$@" ;;
    version-bump) build_version_bump "$@" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"