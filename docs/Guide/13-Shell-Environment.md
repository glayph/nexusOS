# Chapter 13: Shell Environment and User Experience

The shell prompt is the primary user interface of a CLI-focused distribution. A well-configured shell makes the system feel polished and professional.

## Configuring the Prompt (PS1)

### Default Ubuntu Prompt

```
root@nexus:/root#
```

### Ubuntu/Kali-Style Colored Prompt

```bash
PS1='\[\033[96m\]\u@\h\[\033[0m\]:\[\033[97m\]\w\[\033[0m\]\$ '
```

| Escape | Color | Purpose |
|---|---|---|
| `\033[96m` | Cyan | `\u@\h` (user@host) |
| `\033[0m` | Reset | Separator (`:`) |
| `\033[97m` | White | `\w` (working directory) |
| `\033[0m` | Reset | `\$` prompt symbol (`#` for root, `$` for user) |

### Available Prompt Colors

| Code | Color | Use Case |
|---|---|---|
| `\033[91m` | Red | Error, danger |
| `\033[92m` | Green | Success, OK |
| `\033[93m` | Yellow | Warning |
| `\033[94m` | Blue | Info |
| `\033[95m` | Magenta | Special |
| `\033[96m` | Cyan | Primary accent |
| `\033[97m` | White | Normal text |
| `\033[1m` | Bold | Emphasis |
| `\033[2m` | Dim | Secondary/secondary |

## Useful Aliases

```bash
# File listing
alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -A'
alias l='ls -CF'

# Search
alias grep='grep --color=auto'

# Navigation
alias ..='cd ..'
alias cls='clear'

# History
alias h='history'
alias q='exit'

# Utilities with human-readable output
alias ip='ip -c'
alias df='df -h'
alias du='du -sh'
alias free='free -h'

# Editor
alias nano='nano -l'
```

## Tab Completion

Enable bash-completion for tab-completing commands, paths, arguments, and even apt package names:

```bash
[ -f /usr/share/bash-completion/bash_completion ] && \
  . /usr/share/bash-completion/bash_completion
```

## Colors for ls (dircolors)

Enable colored `ls` output:

```bash
eval "$(dircolors -b 2>/dev/null)"
```

This provides:
- Blue: directories
- Green: executables
- Cyan: symlinks
- Red: archives (.tar, .gz, .zip)
- Pink: images (.jpg, .png)

## Readline Configuration (.inputrc)

Customize terminal input behavior:

```
set editing-mode emacs
set bell-style none
TAB: menu-complete
```

| Setting | Effect |
|---|---|
| `editing-mode emacs` | Default keybindings (Ctrl+A = home, Ctrl+E = end) |
| `bell-style none` | No beep on errors |
| `TAB: menu-complete` | Tab cycles through completions (instead of listing all) |

## Message of the Day (MOTD)

The MOTD is displayed after login. Keep it minimal:

```
╭──────────────────────────────────────╮
│  nexus  •  System Shell             │
╰──────────────────────────────────────╯
```

Location: `/etc/motd`

## Complete .bashrc

Here's the complete `.bashrc` used by Nexus OS:

```bash
# Prompt
PS1='\[\033[96m\]\u@\h\[\033[0m\]:\[\033[97m\]\w\[\033[0m\]\$ '

# LS colors
eval "$(dircolors -b 2>/dev/null)"
alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -A'
alias l='ls -CF'

# Utils
alias grep='grep --color=auto'
alias h='history'
alias q='exit'
alias ..='cd ..'
alias cls='clear'
alias ip='ip -c'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias nano='nano -l'

# Editor
export EDITOR=nano

# Completion
[ -f /usr/share/bash-completion/bash_completion ] && \
  . /usr/share/bash-completion/bash_completion
```

## Problem: Prompt Changes Are Lost on Reboot

**Issue**: You customize the prompt in a live session, but it resets after reboot.

**Fix**: The `.bashrc` must be baked into the ISO. Edit it in `makebuild.sh` before running `mksquashfs`:

```bash
cat > "$ROOTFS/root/.bashrc" << 'BASHRC'
# All your custom settings here
BASHRC

cp "$ROOTFS/root/.bashrc" "$ROOTFS/root/.bash_profile"
```

## Problem: Settings Don't Apply to New Users

**Issue**: A user created via `nexus-setup` has the default bash prompt.

**Fix**: Copy the `.bashrc` template to `/etc/skel/` so new users get it:

```bash
cp rootfs/root/.bashrc rootfs/etc/skel/.bashrc
```

Then when `useradd -m` creates a new user, it copies files from `/etc/skel/` to the new home directory.
