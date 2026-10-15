# dotfiles

Dotfiles for **josef**, managed with [chezmoi]. Backs Windows + WSL Ubuntu
work laptops (central SSH hub + coding environment); an Arch Linux ThinkPad is
planned for later, so per-machine differences are template flags, not forks.

> **This repo is public.** Nothing secret or work-internal goes in here — no
> SSH config/keys, no hostnames/IPs, no tokens. Per-machine values (work
> email, …) are prompted on `chezmoi init` and stay in
> `~/.config/chezmoi/chezmoi.toml`.

- **Shell**: fish + Tide (Lean, true color, two lines, few icons)
- **Toolchain**: mise (one manifest — CLI tools, node, go, uv, pnpm, atuin, …)
- **Editor**: VS Code on the Windows host (`EDITOR='code --wait'` via WSL
  interop); neovim as terminal fallback
- **Container runtime**: docker-ce inside WSL (user in `docker` group)
- **History**: atuin (local-only, daemon + fuzzy search)
- **Agents**: Claude Code, Grok CLI, shared skills via `npx skills`
- **SSH**: FIDO2/YubiKey via `sk-ssh-ed25519` — bridged from Windows'
  `ssh-agent` into WSL over `npiperelay.exe` + `socat`. `~/.ssh` itself is
  **not** managed here — copy it by hand.

[chezmoi]: https://www.chezmoi.io

---

## Layout

| Source (this repo)                                 | Target / purpose |
| ---                                                | --- |
| `.chezmoi.toml.tmpl`                               | Per-machine flags: `isWSL` (detected), `isWork`, work git name/email, usage-push host + remote dir (prompted once) |
| `dot_config/fish/config.fish`                      | PATH, mise activation, EDITOR, completions, abbreviations, atuin |
| `dot_config/fish/fish_plugins`                     | fisher manifest (fisher + Tide v6) |
| `dot_config/fish/conf.d/ssh-agent-bridge.fish`     | WSL → Windows ssh-agent bridge (WSL only) |
| `dot_config/mise/config.toml`                      | The one tool manifest |
| `dot_config/atuin/config.toml`                     | atuin: enter_accept, daemon-fuzzy search, daemon autostart |
| `dot_gitconfig.tmpl`                               | user, delta pager, defaults; work identity via `includeIf` (work only) |
| `dot_config/git/work.gitconfig.tmpl`               | Work `user.name`/`user.email` from chezmoi data (work only) |
| `dot_config/git/ignore`                            | Global gitignore |
| `dot_claude/modify_settings.json`                  | Seeds missing Claude Code defaults + merges atuin hooks into `~/.claude/settings.json` |
| `dot_local/bin/executable_usage-push.tmpl`         | Hourly agent-usage push (rsync over ssh) to a usage mirror host (work only) |
| `run_onchange_before_10-system-packages.sh.tmpl`   | apt packages, docker-ce + docker group, fish login shell, `~/.ssh/sockets`, WSL nopasswd sudo |
| `run_onchange_after_20-mise-install.sh.tmpl`       | `mise install` — re-runs whenever the manifest changes |
| `run_once_after_30-fisher-tide.sh`                 | fisher + Tide, then pins the Tide look (`tide configure --auto …`) |
| `run_once_after_40-ai-clis.sh`                     | Claude Code + Grok CLI (native installers) + `npx skills` (orca, find-skills) |
| `run_onchange_after_50-work-tools.sh.tmpl`         | Work only: ansible via `uv tool`, usage-push crontab entry |
| `windows/`                                         | Windows-host side (not deployed by chezmoi): `setup-windows.ps1`, `.wslconfig` |

`.chezmoiignore` keeps `README.md` and `windows/` out of `$HOME`, skips
installer-generated fish files (`functions/`, `completions/`, `conf.d/_*`,
`conf.d/*.env.fish`, `fish_variables`), and guards secret paths (`.ssh/`,
`.claude.json`, credentials, `.config/tailscale/`, …) against an accidental
`chezmoi add`.

---

## New laptop — Windows + WSL

### 1. Windows host — apps

Install WSL (`wsl --install -d Ubuntu-26.04`), Windows Terminal, VS Code
(+ *WSL* extension; install it **before** opening Ubuntu so `code` is on the
WSL PATH), and Tailscale. **Don't** install Docker Desktop (docker-ce runs inside WSL);
if the image ships it, turn off its WSL integration for Ubuntu. YubiKey SSH needs Windows OpenSSH
≥ 8.9 (`ssh -V`): Windows 11 24H2+ ships 9.5; older builds ship 8.1/8.6 →
`winget install Microsoft.OpenSSH.Preview`, then remove the built-in
*OpenSSH Client* optional feature (it comes first on PATH) and check
`where.exe ssh` / `ssh -V`. Open Ubuntu once to create the
user (`josef`). Tailscale runs **on Windows**; with mirrored networking WSL uses
it too.

### 2. WSL (Ubuntu) — bootstrap

```bash
# 0. Prereqs. If you copied chezmoi state from another machine, remove it so
#    init clones fresh and prompts (never share chezmoi.toml between machines)
rm -rf ~/.local/share/chezmoi ~/.config/chezmoi
sudo apt update && sudo apt install -y git curl

# 1. mise, then chezmoi via mise — one chezmoi binary, managed by mise
curl https://mise.run | sh
~/.local/bin/mise exec chezmoi@latest -- chezmoi init --apply --keep-going DrKrapfen/dotfiles
```

`chezmoi init` asks once: *work machine?* (+ work git name/email, and the
usage-push ssh host alias + a remote dir **unique to this machine** — never
reuse another machine's dir). `--apply` then runs, in order:

1. **system packages** (sudo password once): git, curl, unzip,
   build-essential, fish, rsync, htop, git-filter-repo, cron, socat (WSL),
   krb5 (work); docker-ce + compose/buildx, `docker` group; fish as login
   shell; `~/.ssh/sockets`; passwordless sudo (WSL)
2. all dotfiles
3. `mise install` — the whole toolset (set `GITHUB_TOKEN` first if you hit
   GitHub rate limits)
4. fisher + Tide, prompt pinned to Lean
5. Claude Code, Grok CLI, skills
6. work only: ansible (`uv tool`), usage-push cron

If a step fails, fix the cause and re-run the same way (neither `mise` nor
`chezmoi` is on the bash PATH yet):

```bash
~/.local/bin/mise exec chezmoi@latest -- chezmoi apply --keep-going
```

Failed scripts retry, finished ones don't. If apply warned that systemd isn't
enabled: `printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf`
(docker and cron depend on it). Don't restart WSL yet — step 3 first.

### 3. Windows host — setup script

From a **normal (not elevated)** PowerShell — everything is per-user; only
the `ssh-agent` service step asks for UAC — run the host script straight out
of the chezmoi source in WSL (check the distro name with `wsl -l -v`):

```powershell
powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu-26.04\home\josef\.local\share\chezmoi\windows\setup-windows.ps1
wsl --shutdown
```

It installs `npiperelay.exe` to `C:\Tools`, enables the `ssh-agent` service,
installs *MesloLGLDZ Nerd Font*, writes `%USERPROFILE%\.wslconfig`
(mirrored networking, no idle stop) and sets the Nerd Font on the Windows
Terminal Ubuntu profile(s). Idempotent — re-run any time (open Windows
Terminal once first so its settings.json exists). For Tide icons in VS Code's
integrated terminal too, set `"terminal.integrated.fontFamily": "MesloLGLDZ
Nerd Font"` in VS Code settings.

After `wsl --shutdown`, reopen Ubuntu: you land in fish, `docker ps` works
without sudo, and `chezmoi` / `mise` are on PATH.

### 4. Manual bits

```bash
# ~/.ssh — copy all of it from the old machine (config, keys, YubiKey stub + .pub)
chmod 700 ~/.ssh && chmod 600 ~/.ssh/config ~/.ssh/id_* && chmod 644 ~/.ssh/*.pub

# YubiKey: hand the copied stub to the Windows agent (WINUSER = Windows login)
mkdir -p /mnt/c/Users/WINUSER/.ssh
cp ~/.ssh/id_ed25519_josef-ssh-key* /mnt/c/Users/WINUSER/.ssh/
#   PowerShell:  ssh-add $HOME\.ssh\id_ed25519_josef-ssh-key; ssh-add -l
#   new fish:    ssh-add -l; ssh -T git@github.com   (touch + PIN)
#   (no copy available? → "Adding this key to a new machine" below)

# Switch the chezmoi source to SSH (init cloned over https)
chezmoi git -- remote set-url origin git@github.com:DrKrapfen/dotfiles.git

# Shell history — copy once from the old machine (atuin isn't syncing).
# OLD machine: take a consistent snapshot of the live DB
python3 -c 'import sqlite3,os; s=sqlite3.connect(os.path.expanduser("~/.local/share/atuin/history.db")); d=sqlite3.connect("/tmp/history.db"); s.backup(d)'
# NEW machine: one bash command, so fish's atuin hook can't restart the
# daemon between steps; the next fish prompt restarts it (autostart)
bash -c 'atuin daemon stop; pkill -f "atuin daemon"; rm -f ~/.local/share/atuin/history.db-{wal,shm}; cp /path/to/history.db ~/.local/share/atuin/history.db'

# Logins
claude          # /login
grok            # OAuth for MCP servers on first use
gh auth login --git-protocol ssh --skip-ssh-key
```

Work machines additionally:

```bash
sudo dpkg-reconfigure krb5-config        # set the default realm (not in this repo)
kinit <user>@<REALM> && klist
# Ansible vault password file → restore from the password manager, chmod 600
# usage-push: ~/.ssh/config needs a Host block for the mirror alias with a
# non-FIDO key (cron has no agent). Test:
~/.local/bin/usage-push; tail -n 3 ~/.cache/usage-push.log
```

### Arch / non-WSL Linux (later)

The package script only knows apt; on Arch install by hand, then run the
same `mise` + `chezmoi init --apply` lines:

```bash
sudo pacman -S --needed git curl unzip base-devel fish rsync htop cronie \
    git-filter-repo docker docker-compose docker-buildx libfido2   # + krb5 (work)
sudo systemctl enable --now docker cronie && sudo usermod -aG docker $USER
chsh -s /usr/bin/fish
```

`isWSL` is false there, so the ssh-agent bridge isn't deployed; use the
native `ssh-agent` + `ssh-add ~/.ssh/id_ed25519_josef-ssh-key` (libfido2).

---

## YubiKey FIDO2 SSH

Architecture: **generate and hold the key on the Windows side** (Windows
OpenSSH has native FIDO2 support — no USB passthrough into WSL, no re-attach
after undock/sleep/reboot) and **bridge Windows' ssh-agent socket into WSL**.
Same YubiKey works from Windows terminals, WSL, and any other OS you plug
the token into.

**What you end up with**: touch (+ PIN, if `verify-required` is set) once
per `ControlPersist` window, then every subsequent SSH / git / Claude Code
subprocess reuses the multiplexed connection silently. The key never has a
passphrase — protection is hardware token + PIN + physical touch.

---

### Adding this key to a new machine (the flow you'll actually run)

You already have the YubiKey with the credential provisioned (see
"First-time provisioning" below). **No secret material moves.** The token
stays where it is; you regenerate the on-disk stub file from the token.

Prereqs: YubiKey plugged in (know your FIDO2 PIN), `windows/setup-windows.ps1`
run (npiperelay + ssh-agent), WSL side bootstrapped (bridge + socat).

#### 1. Pull the stub file from the YubiKey — no file transfer

Because the credential was generated with `-O resident`, the YubiKey itself
holds enough to reconstruct the stub. In PowerShell:

```powershell
New-Item -ItemType Directory -Force $HOME\.ssh | Out-Null
cd $HOME\.ssh
ssh-keygen -K
# → touch + PIN → writes id_ed25519_sk_rk_josef (+ .pub)
#   (OpenSSH ≥ 8.9 names it id_<type>_rk_<application minus "ssh:">)
```

Rename to the name everything references:

```powershell
Move-Item id_ed25519_sk_rk_josef      id_ed25519_josef-ssh-key
Move-Item id_ed25519_sk_rk_josef.pub  id_ed25519_josef-ssh-key.pub
```

#### 2. Register with Windows' ssh-agent

```powershell
ssh-add $HOME\.ssh\id_ed25519_josef-ssh-key
ssh-add -l
# → 256 SHA256:… ssh:josef (ED25519-SK)
```

(Stubs from `-K` carry the `application` string — `ssh:josef` — as their
comment; a stub copied from the generating machine shows `josef-ssh-key`.)

Shortcut: you already copied `~/.ssh` from the old machine, so instead of
`-K` you can copy the stub over from WSL and `ssh-add` it on Windows:
`cp ~/.ssh/id_ed25519_josef-ssh-key* /mnt/c/Users/<winuser>/.ssh/`

#### 3. On the Linux side — hydrate the stub

`~/.ssh/config`'s `IdentityFile` needs the stub present, even though signing
runs through the agent. If you copied `~/.ssh` from the old machine it's
already there; otherwise:

```bash
cp /mnt/c/Users/<winuser>/.ssh/id_ed25519_josef-ssh-key* ~/.ssh/
chmod 600 ~/.ssh/id_ed25519_josef-ssh-key
chmod 644 ~/.ssh/id_ed25519_josef-ssh-key.pub
```

#### 4. Open a new fish shell — bridge auto-spawns — verify

```bash
ssh-add -l
# → 256 SHA256:… ssh:josef (ED25519-SK)   ← Windows agent, via bridge
ssh -T git@github.com
# → Hi DrKrapfen! You've successfully authenticated…
```

---

### First-time provisioning of a new YubiKey (documented for the record)

One-time credential generation. On any second-or-later machine use
**"Adding this key to a new machine"** above instead.

#### 0. Prep the YubiKey

Firmware ≥ 5.2.3 required for `ed25519-sk`. Set a FIDO2 PIN if needed:

```
ykman fido access change-pin
```

#### 1. Generate the credential — on Windows, not WSL

Windows OpenSSH ≥ 8.9 (`ssh -V` in PowerShell).

```powershell
ssh-keygen -t ed25519-sk `
  -O resident `
  -O verify-required `
  -O application=ssh:josef `
  -C "josef-ssh-key" `
  -f $HOME\.ssh\id_ed25519_josef-ssh-key
```

Two files land in `%USERPROFILE%\.ssh\`:

- `id_ed25519_josef-ssh-key` — **stub / key handle only.** No secret in it;
  the private key lives in the token's secure element.
- `id_ed25519_josef-ssh-key.pub` — public key, safe to distribute.

Options in play:

- **`-O resident`** — credential also lives *on* the YubiKey, so
  `ssh-keygen -K` on a fresh machine reconstructs the stub from just the
  token. This is what makes the new-machine flow work without moving files.
- **`-O verify-required`** — PIN at every new SSH auth. With
  `ControlPersist 4h` that's roughly one PIN per idle window per host.
- **`-O application=ssh:josef`** — namespace inside the token; lets one
  YubiKey hold several SSH credentials that `ssh-keygen -K` tells apart.
- **No passphrase** — deliberately. Worthless without the physical token.

#### 2. Load into Windows' ssh-agent

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add $HOME\.ssh\id_ed25519_josef-ssh-key
```

---

### Reference: the bridge

`~/.config/fish/conf.d/ssh-agent-bridge.fish` is deployed only when
`isWSL`, and only takes over `SSH_AUTH_SOCK` when
`/mnt/c/Tools/npiperelay.exe` exists — otherwise any native agent is left
alone.

**Bash / zsh equivalent** for non-fish shells — drop into `~/.bashrc`:

```bash
# --- WSL → Windows ssh-agent bridge (YubiKey via npiperelay) ---
NPIPERELAY=/mnt/c/Tools/npiperelay.exe
if [ -x "$NPIPERELAY" ]; then
    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    if ! ss -a 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
        rm -f "$SSH_AUTH_SOCK"
        (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork \
            EXEC:"$NPIPERELAY -ei -s //./pipe/openssh-ssh-agent",nofork \
            &) > /tmp/npiperelay.log 2>&1
    fi
fi
```

### Reference: `~/.ssh/config` (not managed — copied by hand)

The defaults the YubiKey flow relies on — keep host-specific blocks
**above** `Host *` (ssh uses the first value it finds, so `Host *` at the
top would override per-host settings):

```
Host github.com
    User git
    ControlMaster no

# … other hosts …

Host *
    IdentityFile ~/.ssh/id_ed25519_josef-ssh-key
    IdentitiesOnly yes
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%C
    ControlPersist 4h
    HashKnownHosts no
```

`IdentitiesOnly yes` means the stub file must exist — without it ssh won't
fall back to the agent's list. `ControlMaster` + `ControlPersist 4h` give
the one-touch-per-idle-window UX. `~/.ssh/sockets` is created by the
package bootstrap.

### Deploy the public key to a new server

```
ssh-copy-id -i ~/.ssh/id_ed25519_josef-ssh-key.pub <host>
# or: append the .pub line to ~/.ssh/authorized_keys (700 dir / 600 file)
```

---

## Common tasks

**Pull + apply updates from GitHub:** `chezmoi update`.

**Claude Code settings:** `dot_claude/modify_settings.json` only seeds missing
keys (and keeps the atuin hooks merged) — `/config` changes stick.

**Change a dotfile:** `chezmoi edit <target>` (or edit in `chezmoi cd`),
then `chezmoi diff` / `chezmoi apply`.

**Installer edited a managed file** (shows as `MM` in `chezmoi status`):
`chezmoi diff`, then either `chezmoi re-add <file>` (keep it) or
`chezmoi apply <file>` (discard).

**Add a tool:** add it to `dot_config/mise/config.toml`; `chezmoi apply`
runs `mise install` automatically.

**Change per-machine answers:** edit `~/.config/chezmoi/chezmoi.toml`, or
`chezmoi init --prompt`.

**Existing machine, first apply after pulling new template variables:** run
`chezmoi init` first (it prompts for new keys only), then `chezmoi apply`.

**Apply fails on `.claude/settings.json`:** the file isn't valid JSON (the
merge refuses to overwrite it). Fix or move it, or `chezmoi apply
--keep-going` to apply everything else.

**Commit + push:**

```
chezmoi cd
git add -A && git commit -m "…" && git push
```

**Nuke and rebuild the ssh-agent bridge (if it got wedged):**

```
rm -f ~/.ssh/agent.sock
pkill -f "socat.*agent.sock"
# reopen the shell — the bridge respawns
```

---

## References

- YubiKey Manager: <https://developers.yubico.com/YubiKey-Manager/>
- npiperelay: <https://github.com/jstarks/npiperelay>
- Tide: <https://github.com/IlanCosman/tide>
- chezmoi templates/scripts: <https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/>
