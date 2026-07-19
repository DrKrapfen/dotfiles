# dotfiles

Private dotfiles for **josef**, managed with [chezmoi]. Backs a WSL Ubuntu box
that serves as central SSH hub + coding environment, with an Arch Linux
ThinkPad rebuild planned for later — every choice biases toward portability.

- **Shell**: fish + Tide (Classic preset)
- **Toolchain**: mise (one manifest, everything else)
- **Python**: uv
- **Editor**: neovim + [kickstart.nvim] (own fork, no AI plugins)
- **Container runtime**: docker-ce inside WSL
- **History**: atuin (local-only)
- **SSH**: FIDO2/YubiKey via `sk-ssh-ed25519` — bridged from Windows'
  `ssh-agent` into WSL over `npiperelay.exe` + `socat`

[chezmoi]: https://www.chezmoi.io
[kickstart.nvim]: https://github.com/nvim-lua/kickstart.nvim

---

## Layout

| Path (in `$HOME`)                          | Purpose |
| ---                                        | --- |
| `~/.config/fish/config.fish`               | Fish shell — PATH, mise/uv activation, tool init |
| `~/.config/fish/fish_plugins`              | fisher manifest (rehydrates fisher/Tide on restore) |
| `~/.config/fish/conf.d/ssh-agent-bridge.fish` | WSL → Windows ssh-agent bridge (YubiKey) |
| `~/.config/mise/config.toml`               | The one tool manifest — `mise install` restores everything |
| `~/.gitconfig`                             | user, delta pager, sensible defaults |
| `~/.ssh/config`                            | `Host *` defaults + ControlMaster + hostnames |
| `run_once_after_install-fisher-plugins.sh` | chezmoi one-shot: bootstrap fisher + reinstall Tide |

`.chezmoiignore` excludes chezmoi from touching plugin-installed files
(`fish/functions/`, `fish/conf.d/_*`, `fish/conf.d/atuin.env.fish`,
`atuin/config.toml`) — those come back automatically from their installers.

`~/.config/nvim` (kickstart.nvim fork) is **not** in this repo — it's its own
git repo. Clone separately.

---

## Restore story — fresh machine

### On a Linux box (WSL, Arch, Ubuntu, …)

```bash
# 0. Prereqs — git, curl. Adjust to your distro.
sudo apt install -y git curl unzip                       # Debian/Ubuntu
# sudo pacman -S --needed git curl unzip                 # Arch

# 1. Install chezmoi and pull this repo
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply DrKrapfen/dotfiles

# 2. Install mise, then rebuild the entire toolset from the manifest
curl https://mise.run | sh
~/.local/bin/mise install                                # fish, node, go, kubectl, …

# 3. Register fish as default login shell
sudo apt install -y fish                                 # if not via mise
chsh -s "$(which fish)"

# 4. uv (Python) — separate installer
curl -LsSf https://astral.sh/uv/install.sh | sh

# 5. atuin (local-only history)
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
atuin import auto

# 6. kickstart.nvim — clone your fork alongside
git clone git@github.com:DrKrapfen/kickstart.nvim ~/.config/nvim

# 7. Reopen the shell. Fisher + Tide re-hydrate via the run_once script.
```

### On a Windows-hosted WSL box

Same as above, plus:

- Enable systemd in `/etc/wsl.conf` and reboot the distro.
- Install `docker-ce` (see the WSL build in `HANDOFF.md` on the original
  machine; the five-line Docker apt install works as-is on Ubuntu 24.04+).
- Set up the YubiKey SSH bridge — see the next section.

---

## YubiKey FIDO2 SSH — full setup

Architecture: **generate and hold the key on the Windows side** (Windows
OpenSSH has native FIDO2 support — no USB passthrough into WSL, no re-attach
after undock/sleep/reboot) and **bridge Windows' ssh-agent socket into WSL**.
Same key works from Windows terminals, WSL, and any other OS you plug the
YubiKey into.

**What you end up with**: touch (+ PIN, if `verify-required` is set) once per
`ControlPersist` window, then every subsequent SSH / git / Claude Code
subprocess reuses the multiplexed connection silently. The key never has a
passphrase — protection comes from the hardware token + PIN + physical touch.

### 0. Prep the YubiKey

Firmware ≥ 5.2.3 required for `ed25519-sk`. Check in Yubico Authenticator's
home screen. Set a FIDO2 PIN if you haven't already:

```
ykman fido access change-pin
```

### 1. Generate the key — on Windows, not WSL

Windows OpenSSH ≥ 8.9 is required. Check `ssh -V` in PowerShell.

```powershell
ssh-keygen -t ed25519-sk `
  -O resident `
  -O verify-required `
  -O application=ssh:josef `
  -C "josef-ssh-key" `
  -f C:\Users\josef\.ssh\id_ed25519_josef-ssh-key
```

You'll get a touch + PIN prompt twice (once to unlock, once to confirm
generation). Two files land in `C:\Users\josef\.ssh\`:

- `id_ed25519_josef-ssh-key` — **stub / key handle only.** No secret material
  in it; the actual private key lives in the token's secure element.
- `id_ed25519_josef-ssh-key.pub` — public key, safe to distribute.

Options in play:

- **`-O resident`** — the credential also lives *on* the YubiKey. If the stub
  file is ever gone (fresh machine, wiped `.ssh`), pull it back with
  `ssh-keygen -K` using just the token + PIN — no backup needed.
- **`-O verify-required`** — PIN is demanded at every new SSH auth. Combined
  with `ControlPersist 4h` below, this is one PIN per ~4h idle window.
  Drop this flag if you want touch-only.
- **`-O application=ssh:josef`** — the credential's application id on the
  token. Namespacing lets you have multiple SSH keys on one YubiKey (e.g.
  `ssh:josef`, `ssh:work-only`).
- **No passphrase** — omitted deliberately. The key is worthless without the
  physical YubiKey; a disk passphrase would add nothing here.

### 2. Load the key into Windows' ssh-agent

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add C:\Users\josef\.ssh\id_ed25519_josef-ssh-key
```

Confirm:

```powershell
ssh-add -L
# → sk-ssh-ed25519@openssh.com AAAA…== josef-ssh-key
```

### 3. Bridge the agent socket into Linux

Get `npiperelay.exe` from [jstarks/npiperelay] and drop it at a **fixed,
non-user-specific path** so chezmoi-managed shell configs work across users
without templating:

[jstarks/npiperelay]: https://github.com/jstarks/npiperelay

```powershell
mkdir C:\Tools 2>$null
Copy-Item .\npiperelay.exe C:\Tools\npiperelay.exe
```

In WSL (or any Linux terminal on the Windows host):

```bash
sudo apt install -y socat   # Debian/Ubuntu
# sudo pacman -S socat      # Arch (Arch box outside WSL doesn't need the bridge at all — see below)
```

#### Fish (this repo's default) — already in place

`~/.config/fish/conf.d/ssh-agent-bridge.fish` is tracked in this repo. It
runs on every fish start:

```fish
set -gx SSH_AUTH_SOCK $HOME/.ssh/agent.sock
set -l npiperelay /mnt/c/Tools/npiperelay.exe

if test -x $npiperelay
    if not ss -xlnp 2>/dev/null | string match -q "*$SSH_AUTH_SOCK*"
        rm -f $SSH_AUTH_SOCK
        setsid -f socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork \
            EXEC:"$npiperelay -ei -s //./pipe/openssh-ssh-agent",nofork \
            > /dev/null 2>&1 &
        disown 2>/dev/null; or true
    end
end
```

Guard clause: on Arch (or anywhere without `/mnt/c/Tools/npiperelay.exe`) the
`test -x` short-circuits and does nothing — the file is safe to sync
verbatim.

#### Bash (or zsh) — drop-in for `~/.bashrc`

For anyone on the box using bash (or for machines that don't have fish):

```bash
# --- WSL → Windows ssh-agent bridge (YubiKey via npiperelay) ---
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
NPIPERELAY=/mnt/c/Tools/npiperelay.exe
if [ -x "$NPIPERELAY" ]; then
    if ! ss -a 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
        rm -f "$SSH_AUTH_SOCK"
        (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork \
            EXEC:"$NPIPERELAY -ei -s //./pipe/openssh-ssh-agent",nofork \
            &) > /tmp/npiperelay.log 2>&1
    fi
fi
```

Verify the bridge works:

```bash
ssh-add -l
# → 256 SHA256:… josef-ssh-key (ED25519-SK)
```

### 4. SSH config for one-touch-per-session behaviour

`~/.ssh/config` (tracked in this repo) declares sensible defaults:

```
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

The `IdentityFile` line just tells `ssh` **which public key to offer** to
each host — the actual signing goes through the agent → Windows → YubiKey.
The stub file needs to be on disk for the `IdentityFile` reference (copy it
over from Windows, or run `ssh-keygen -K` on a fresh box).

Prep the sockets directory once:

```
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh/sockets
```

First connect to any host prompts PIN + touch. For the next 4 hours of idle
time, every SSH, git, or Claude Code subprocess reuses the muxed connection
silently.

### 5. Deploy the public key to your servers

On each target host:

```
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "sk-ssh-ed25519@openssh.com AAAA…== josef-ssh-key" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Or `ssh-copy-id -i ~/.ssh/id_ed25519_josef-ssh-key.pub <host>` if the host
already accepts password auth.

### 6. Test

```
ssh -v <hostname>
```

Expect a PIN prompt + touch on first connect (that's Windows' agent asking
the token to sign), then instant reuse on subsequent invocations within
`ControlPersist`.

### chezmoi / portability notes

- `~/.ssh/config` — tracked as-is (`private_dot_ssh/private_config`), no
  templating.
- The fish bridge snippet — tracked verbatim; safe because `npiperelay.exe`
  is pinned at `C:\Tools\`, not a per-user path.
- **No key material syncs.** The key never leaves the YubiKey. On a fresh
  machine, if the stub file is missing, `ssh-keygen -K` regenerates it from
  the token alone (PIN required).
- **Arch / non-Windows Linux**: skip the bridge entirely. Native
  `ssh-agent` + `ssh-add ~/.ssh/id_ed25519_josef-ssh-key` handles the
  YubiKey via `libfido2`. The tracked fish file no-ops correctly there.
- **`verify-required` trade-off**: PIN at every new muxed session. With
  `ControlPersist 4h`, that's once per idle window per host. Regenerate
  without the flag if you want touch-only convenience.

---

## Common tasks

**Rebuild the toolset after editing `mise/config.toml`:**

```
mise install
```

**Apply chezmoi changes after editing source files:**

```
chezmoi diff              # dry-run
chezmoi apply             # apply
```

**Commit + push updates:**

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

- Full build recipe for this WSL machine: `HANDOFF.md` (stays on the origin
  machine at `/mnt/c/Users/josef/HANDOFF.md` — not tracked here).
- kickstart.nvim fork: `github.com/DrKrapfen/kickstart.nvim`
- YubiKey Nano firmware: <https://developers.yubico.com/YubiKey-Manager/>
- npiperelay: <https://github.com/jstarks/npiperelay>
