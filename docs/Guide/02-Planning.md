# Chapter 2: Planning Your Distribution

Before writing a single line of code, you need to make several architectural decisions. These choices affect every subsequent chapter.

## Design Decisions

### 1. Base Distribution

| Choice | Pros | Cons |
|---|---|---|
| **Ubuntu Noble (24.04)** | Large package repository, long-term support, well-documented | Larger base install |
| **Debian Bookworm (12)** | Smaller base, very stable | Slightly older packages |
| **Debian Sid** | Latest packages | Unstable, may break during build |
| **Arch Linux** | Minimal, cutting-edge | Requires `pacstrap`, different package management |
| **Alpine Linux** | Extremely small (5 MB base) | Uses `musl` libc, not `glibc` — compatibility issues |

Nexus OS chose **Ubuntu 24.04 Noble** for its balance of stability, package availability, and LTS support.

### 2. Package Selection Philosophy

Decide early: **minimal** or **feature-rich**?

| Approach | ISO Size | Functionality |
|---|---|---|
| **Minimal** (bare CLI) | ~130 MB | Just a shell. User installs everything else. |
| **Standard** (CLI + tools) | ~250 MB | Networking, audio, editor, build tools |
| **Full desktop** (Xorg + DE) | ~1-2 GB | Everything included out of the box |

Nexus OS started minimal and grew to a **standard + optional desktop** approach:
- **Base ISO (~258 MB)**: CLI with networking, audio, bluetooth, minimal X
- **Optional (via nexus-setup)**: Desktop environments, GPU drivers, firmware

### 3. Live or Installed?

| Type | Pros | Cons |
|---|---|---|
| **Live ISO** | No installation needed, one file to distribute | Changes lost on reboot |
| **Installed system** | Persistent by nature | Requires installation process, partition management |

Nexus OS is a **live ISO with optional persistence** — the best of both worlds.

### 4. BIOS, UEFI, or Both?

| Boot Method | Support Required |
|---|---|
| BIOS-only | Simpler ISO, but doesn't boot on modern UEFI systems |
| UEFI-only | Required for modern laptops and Secure Boot |
| **Dual (BIOS+UEFI)** | Boots everywhere, slightly larger ISO |

Always choose **dual boot**. `grub-mkrescue` makes this easy.

### 5. Read-Only or Writable Root?

| Approach | How It Works |
|---|---|
| **Squashfs** (read-only) | Compressed, small, fast. Changes go to overlay. |
| **Full ext4 image** | Writable but larger, no compression |

Squashfs is the standard for live distributions. It's what Ubuntu, Debian, Fedora, Knoppix, and virtually every live distribution uses.

## Planning Checklist

Before you start coding:

- [ ] Choose base distribution and release
- [ ] Decide target audience (developer, sysadmin, hobbyist)
- [ ] List required packages (start minimal, then add)
- [ ] Choose init system (systemd is standard)
- [ ] Choose desktop environment (or none for CLI)
- [ ] Decide on display manager (or none)
- [ ] Plan kernel configuration (full, stripped, or custom)
- [ ] Design the boot experience (GRUB menu, auto-login)
- [ ] Plan persistence strategy (overlay, partition, or none)
- [ ] Decide on build automation (local, CI/CD)

## The Nexus OS Blueprint

Here's the architecture that Nexus OS follows. You can use it as a template for your own distribution:

```
┌──────────────────────────────────────┐
│          Application Layer           │
│  (nexus-setup, bash, tmux, nano)     │
├──────────────────────────────────────┤
│          System Services             │
│  (systemd, pulseaudio, bluez, ssh)   │
├──────────────────────────────────────┤
│          Kernel Modules              │
│  (stripped: -media, -staging, +drm)  │
├──────────────────────────────────────┤
│           Linux Kernel               │
│  (linux-image-virtual, 6.8.x)        │
├──────────────────────────────────────┤
│         Boot Layer (GRUB)            │
│  (BIOS + UEFI, grub-mkrescue)        │
├──────────────────────────────────────┤
│          Squashfs (XZ compressed)     │
│  (read-only root filesystem)          │
└──────────────────────────────────────┘
```
