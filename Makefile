# ============================================================
#  NEXUS OS — Build System
#  Usage: make [target]
# ============================================================

.PHONY: all install build clean flash help

# Default target
all: help

help:
	@echo ""
	@echo "  NEXUS OS Build System"
	@echo "  ─────────────────────────────────────────────"
	@echo "  make install        Install build dependencies"
	@echo "  make build          Build nexus.iso"
	@echo "  make build CLEAN=1  Fresh build (delete rootfs)"
	@echo "  make build FAST=1   Skip squashfs rebuild"
	@echo "  make clean          Remove all build artifacts"
	@echo "  make flash DEV=/dev/sdX   Flash ISO to USB"
	@echo "  make qemu           Test in QEMU (needs qemu)"
	@echo "  ─────────────────────────────────────────────"
	@echo ""

install:
	@echo "[NEXUS] Installing dependencies..."
	@sudo bash install-deps.sh

build:
	@if [ "$(CLEAN)" = "1" ]; then \
	    sudo bash makebuild.sh --clean; \
	elif [ "$(FAST)" = "1" ]; then \
	    sudo bash makebuild.sh --no-squash; \
	else \
	    sudo bash makebuild.sh; \
	fi

clean:
	@echo "[NEXUS] Cleaning build artifacts..."
	@sudo rm -rf rootfs iso core.img bios.img efiboot.img nexus.iso
	@echo "[NEXUS] Clean done."

flash:
	@if [ -z "$(DEV)" ]; then \
	    echo "Usage: make flash DEV=/dev/sdX"; \
	    exit 1; \
	fi
	@echo "[NEXUS] Flashing nexus.iso to $(DEV)..."
	@sudo dd if=nexus.iso of=$(DEV) bs=4M status=progress && sync
	@echo "[NEXUS] Flash complete! Eject and boot."

qemu:
	@command -v qemu-system-x86_64 >/dev/null || (echo "Install: apt install qemu-system-x86"; exit 1)
	@echo "[NEXUS] Starting QEMU test..."
	qemu-system-x86_64 \
	  -m 2048 \
	  -cdrom nexus.iso \
	  -boot d \
	  -enable-kvm \
	  -nographic \
	  -serial mon:stdio
