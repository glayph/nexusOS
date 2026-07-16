# Customization

## The `customize/` Directory

Before building the ISO, you can modify files in the `customize/` directory to change the system behavior.

| File | Purpose |
|---|---|
| `packages.list` | Extra apt packages to install |
| `startup.sh` | Runs on every boot before the shell |
| `motd.txt` | Welcome message shown at boot |

## packages.list

Add one package name per line. Comments start with `#`.

```bash
# Example: custom packages.list
git
htop
neofetch
python3
docker.io
```

These are installed during the build via `apt-get install --no-install-recommends`.

## startup.sh

This script runs automatically on every boot before the shell prompt appears. It's executed by the root user.

```bash
#!/bin/bash
# Example: start SSH and set an environment variable
systemctl start ssh
export MY_VAR="hello"
echo "Custom startup complete!"
```

## motd.txt

The Message of the Day is displayed on tty1 after login. Keep it short.

## Rebuilding After Customization

```bash
# Fast rebuild (keeps rootfs, only repackages ISO)
make build FAST=1

# Full rebuild
make build
```

## Adding Custom Files

To add permanent files to the ISO, you can extend `makebuild.sh`. For example, to add a script to `/usr/local/bin`:

```bash
# In makebuild.sh, after Step 7:
cp my-custom-script.sh "$ROOTFS/usr/local/bin/my-custom-script"
chmod +x "$ROOTFS/usr/local/bin/my-custom-script"
```

Then `make build` to regenerate the ISO.
