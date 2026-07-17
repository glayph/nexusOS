# Shell Environment

## Prompt

The bash prompt is styled after Ubuntu/Kali with a colored format:

```
user@tajaos:/root$
```

- Cyan `\u@\h` (user@host)
- White `\w` (working directory)
- Default `\$` (shows `#` for root, `$` for non-root)

Set via `PS1` in `/root/.bashrc`:
```bash
PS1='\[\033[96m\]\u@\h\[\033[0m\]:\[\033[97m\]\w\[\033[0m\]\$ '
```

## Aliases

| Alias | Command | Purpose |
|---|---|---|
| `ll` | `ls -lh` | Long listing with human-readable sizes |
| `la` | `ls -A` | Show all files (except `.` and `..`) |
| `l` | `ls -CF` | Compact column listing |
| `ls` | `ls --color=auto` | Colorized output |
| `grep` | `grep --color=auto` | Highlighted matches |
| `cls` | `clear` | Clear screen |
| `h` | `history` | Command history |
| `q` | `exit` | Exit shell |
| `..` | `cd ..` | Go up one directory |
| `ip` | `ip -c` | Colored ip output |
| `df` | `df -h` | Human-readable disk usage |
| `du` | `du -sh` | Summary disk usage per item |
| `free` | `free -h` | Human-readable memory |
| `nano` | `nano -l` | Nano with line numbers |

## Colors

`dircolors` is evaluated at shell start to colorize `ls` output:
```bash
eval "$(dircolors -b 2>/dev/null)"
```

This provides standard Linux color coding:
- Blue: directories
- Green: executables
- Cyan: symlinks
- Red: archives
- Pink: images

## Tab Completion

Bash completion is loaded if available:
```bash
[ -f /usr/share/bash-completion/bash_completion ] && \
  . /usr/share/bash-completion/bash_completion
```

Provides tab completion for:
- Commands and arguments
- File paths
- Apt package names
- Systemctl units
- And more

## InputRC

The `/root/.inputrc` file sets readline behavior:
```
set editing-mode emacs
set bell-style none
TAB: menu-complete
```

- **Emacs mode**: Standard terminal keybindings
- **No bell**: No beep on errors
- **Menu-complete**: Tab cycles through completions instead of listing
