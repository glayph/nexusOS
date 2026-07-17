# Audio

## Stack

Audio is provided by ALSA (kernel-level) + PulseAudio (userserver).

| Component | Package | Purpose |
|---|---|---|
| Kernel drivers | `linux-image-virtual` | `snd-*` modules (kept during stripping) |
| ALSA utilities | `alsa-utils` | `alsamixer`, `aplay`, `arecord`, `amixer` |
| Sound server | `pulseaudio` | Per-application volume, network audio, Bluetooth audio |

## Kernel Modules

The `sound` directory in kernel modules is **not** stripped during the build, so all sound drivers are available. Most common sound hardware is supported:

- Intel HDA (`snd-hda-intel`)
- USB audio (`snd-usb-audio`)
- AC97 (`snd-ac97-codec`)
- PC Speaker (`pcspkr`)
- Virtio sound (`snd-virtio`)

## Usage

```bash
# List playback devices
aplay -l

# Set volume
alsamixer

# Test playback
speaker-test -t sine -f 440

# PulseAudio control
pactl list sinks short
```

## Troubleshooting

**No sound devices found:**
```bash
# Check if modules are loaded
lsmod | grep snd

# Force module load
modprobe snd-hda-intel
```

**PulseAudio not starting:**
```bash
pulseaudio --start
```

**Audio alsa not visible:** Run as non-root user (after creating one via `taja-setup`). PulseAudio per-user daemon requires a user session.
