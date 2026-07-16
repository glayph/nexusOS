#!/bin/bash
# ============================================================
#  NEXUS OS — One-Click Dependency Installer (Linux / WSL)
#  Usage: sudo bash install-deps.sh
# ============================================================

set -e
C='\033[96m'; G='\033[92m'; R='\033[91m'; N='\033[0m'

echo -e "${C}"
echo "  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗"
echo "  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝"
echo "  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗"
echo "  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║"
echo "  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║"
echo "  ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
echo -e "${N}  Nexus OS — Dependency Installer"
echo ""

[[ $EUID -ne 0 ]] && echo -e "${R}[ERROR] Run as root: sudo bash install-deps.sh${N}" && exit 1

# Detect distro
if command -v apt-get &>/dev/null; then
  PKG_MGR="apt-get"
elif command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
else
  echo -e "${R}[ERROR] Unsupported distro. Need apt-get or dnf.${N}"
  exit 1
fi

echo -e "${C}[1/3]${N} Updating package lists..."
if [[ $PKG_MGR == "apt-get" ]]; then
  apt-get update -qq

  echo -e "${C}[2/3]${N} Installing build tools..."
  apt-get install -y \
    debootstrap \
    xorriso \
    squashfs-tools \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-common \
    mtools \
    dosfstools \
    python3 \
    python3-pip \
    python3-requests \
    git \
    curl \
    wget \
    make

elif [[ $PKG_MGR == "dnf" ]]; then
  echo -e "${C}[2/3]${N} Installing build tools (Fedora/RHEL)..."
  dnf install -y \
    debootstrap \
    xorriso \
    squashfs-tools \
    grub2-pc \
    grub2-efi-x64 \
    mtools \
    dosfstools \
    python3 \
    python3-pip \
    python3-requests \
    git curl wget make
fi

echo -e "${C}[3/3]${N} Verifying tools..."
TOOLS=(debootstrap xorriso mksquashfs grub-mkrescue grub-mkstandalone mkfs.fat python3)
ALL_OK=true
for t in "${TOOLS[@]}"; do
  if command -v $t &>/dev/null; then
    echo -e "  ${G}✅${N} $t"
  else
    echo -e "  ❌ $t — NOT FOUND"
    ALL_OK=false
  fi
done

echo ""
if $ALL_OK; then
  echo -e "${G}✅ All dependencies installed successfully!${N}"
  echo ""
  echo "  Next steps:"
  echo "    make build          ← Build nexus.iso"
  echo "    make build CLEAN=1  ← Fresh build"
  echo "    make help           ← See all options"
else
  echo -e "${R}Some tools missing. Check errors above.${N}"
  exit 1
fi
