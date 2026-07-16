# Chapter 15: Build Automation and CI/CD

Manual builds work for development, but for distribution you need automated builds. This chapter covers setting up continuous integration with GitHub Actions.

## Makefile

Start with a Makefile that wraps the build script:

```bash
.PHONY: all install build clean flash help

build:
	sudo bash makebuild.sh

build CLEAN=1:
	sudo bash makebuild.sh --clean

build FAST=1:
	sudo bash makebuild.sh --no-squash

clean:
	sudo rm -rf rootfs iso core.img bios.img efiboot.img nexus.iso

flash:
	sudo dd if=nexus.iso of=$(DEV) bs=4M status=progress

qemu:
	qemu-system-x86_64 -m 2048 -cdrom nexus.iso -boot d -enable-kvm
```

This lets you type:
```bash
make build          # Normal build
make build CLEAN=1  # Fresh build
make qemu           # Test in VM
```

## GitHub Actions Workflow

### Basic Workflow

```yaml
name: Build ISO

on:
  push:
    branches: [main]
    paths:
      - 'makebuild.sh'
      - 'nexus-setup.sh'
      - 'boot/**'
      - 'customize/**'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-24.04
    timeout-minutes: 120
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: sudo bash install-deps.sh
      
      - name: Build ISO
        run: sudo bash makebuild.sh
      
      - name: Upload Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v1.0
          files: |
            nexus.iso
            SHA256SUMS
          make_latest: true
          overwrite: true
```

### Key Features

| Feature | Implementation | Purpose |
|---|---|---|
| **Selective trigger** | `paths:` filter | Only build when relevant files change |
| **Manual trigger** | `workflow_dispatch:` | Build on demand without pushing |
| **Timeout** | `timeout-minutes: 120` | Prevent runaway builds |
| **Overwrite** | `overwrite: true` | Same tag always gets latest ISO |
| **Auto-release** | `action-gh-release` | ISO is downloadable after each build |

## Problem: Build Takes Too Long in CI

**Issue**: A full build can take 1-2 hours in GitHub Actions.

**Fixes**:
1. Use `FAST=1` if rootfs is cached (but CI starts fresh each time)
2. Cache the rootfs directory:
   ```yaml
   - name: Cache rootfs
     uses: actions/cache@v4
     with:
       path: rootfs
       key: rootfs-${{ hashFiles('makebuild.sh') }}
   ```
3. Build only when relevant files change (already implemented with `paths:`)

## Problem: Squashfs Fails in CI

**Issue**: `mksquashfs` runs out of memory in the CI runner.

**Fix**: GitHub Actions runners have 7 GB RAM. If this isn't enough, reduce the block size or switch compression:

```bash
# Use less memory-hungry compression
mksquashfs rootfs filesystem.squashfs -comp gzip -b 256K
```

## Problem: Release Not Created

**Issue**: The workflow succeeds but no release appears.

**Fixes**:
1. Ensure `contents: write` permission is set:
   ```yaml
   permissions:
     contents: write
   ```
2. The tag must exist. Create it once:
   ```bash
   git tag v1.0
   git push origin v1.0
   ```
3. With `overwrite: true`, the release is updated on each build.

## Versioning

### Automatic Version from Date

```bash
VERSION=$(date +%Y%m%d-%H%M%S)
make build OUTPUT=nexus-$VERSION.iso
```

### Semantic Versioning

```bash
VERSION=1.2.3
git tag v$VERSION
make build OUTPUT=nexus-$VERSION.iso
```

## Testing in CI

Add a step to test the ISO boots in QEMU:

```yaml
- name: Test ISO in QEMU
  run: |
    timeout 30 qemu-system-x86_64 \
      -m 1024 \
      -cdrom nexus.iso \
      -nographic \
      -serial mon:stdio 2>&1 | head -50
```

This boots the ISO and checks that it reaches the login prompt within 30 seconds.

## Checksums

Always generate SHA256 checksums for your releases:

```bash
sha256sum nexus.iso | tee SHA256SUMS
```

Users can verify:

```bash
sha256sum -c SHA256SUMS
```
