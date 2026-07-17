# ============================================================
#  TAJAOS — Build System
#  Usage: make [target]
# ============================================================

.PHONY: all install build clean flash help lint shellcheck

# Default target
all: help

help:
	@echo ""
	@echo "  TAJAOS Build System"
	@echo "  ─────────────────────────────────────────────"
	@echo "  make install        Install build dependencies"
	@echo "  make build          Build tajaos.iso"
	@echo "  make build CLEAN=1  Fresh build (delete rootfs)"
	@echo "  make build FAST=1   Skip squashfs rebuild"
	@echo "  make clean          Remove all build artifacts"
	@echo "  make flash DEV=/dev/sdX   Flash ISO to USB"
	@echo "  make qemu           Test in QEMU (needs qemu)"
	@echo "  make lint           Run shellcheck on all scripts"
	@echo "  make shellcheck     Alias for lint"
	@echo "  ─────────────────────────────────────────────"
	@echo ""

install:
	@echo "[TAJAOS] Installing dependencies..."
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
	@echo "[TAJAOS] Cleaning build artifacts..."
	@sudo rm -rf rootfs iso core.img bios.img efiboot.img tajaos.iso
	@echo "[TAJAOS] Clean done."

flash:
	@if [ -z "$(DEV)" ]; then \
	    echo "Usage: make flash DEV=/dev/sdX"; \
	    exit 1; \
	fi
	@echo "[TAJAOS] Flashing tajaos.iso to $(DEV)..."
	@sudo dd if=tajaos.iso of=$(DEV) bs=4M status=progress && sync
	@echo "[TAJAOS] Flash complete! Eject and boot."

qemu:
	@command -v qemu-system-x86_64 >/dev/null || (echo "Install: apt install qemu-system-x86"; exit 1)
	@echo "[TAJAOS] Starting QEMU test..."
	qemu-system-x86_64 \
	  -m 2048 \
	  -cdrom tajaos.iso \
	  -boot d \
	  -enable-kvm \
	  -nographic \
	  -serial mon:stdio

lint:
	@command -v shellcheck >/dev/null || (echo "Install: apt install shellcheck"; exit 1)
	@echo "[TAJAOS] Running shellcheck on all scripts..."
	@shellcheck makebuild.sh install-deps.sh nexus-setup.sh

shellcheck: lint
