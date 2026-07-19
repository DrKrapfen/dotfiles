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

The everyday case: you already have your YubiKey with the credential
provisioned (from the "First-time provisioning" section below) and you're
setting up a second machine — work laptop, homelab jump box, whatever.
**No secret material moves.** The token stays where it is; you regenerate
the on-disk stub file from the token itself.

Prereqs on the new machine:

- YubiKey plugged in, unlocked (know your FIDO2 PIN).
- Linux side of the [restore story](#on-a-linux-box-wsl-arch-ubuntu-)
  above already run → chezmoi has laid down `~/.ssh/config`, the fish
  agent-bridge, everything.
- Windows OpenSSH client installed (built-in on Windows 10/11; check
  `ssh -V` ≥ 8.9).

#### 1. On Windows — `npiperelay` + `ssh-agent`

Grab `npiperelay.exe` from [jstarks/npiperelay] and drop it at the fixed
path the tracked bridge expects (this must match on every machine):

[jstarks/npiperelay]: https://github.com/jstarks/npiperelay

```powershell
mkdir C:\Tools 2>$null
Copy-Item .\npiperelay.exe C:\Tools\npiperelay.exe
```

Turn on Windows' ssh-agent service (idempotent):

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
```

#### 2. Pull the stub file from the YubiKey — no file transfer

Because the credential was generated with `-O resident`, the YubiKey itself
holds enough to reconstruct the stub. From a new PowerShell in
`C:\Users\<user>\.ssh`:

```powershell
cd $HOME\.ssh
ssh-keygen -K
# → touch + PIN → writes: id_ed25519_sk_ssh_josef and id_ed25519_sk_ssh_josef.pub
```

`ssh-keygen -K` dumps every resident credential; each gets a name derived
from its `application=` value (`ssh_josef` for `ssh:josef`). Rename to
match what `~/.ssh/config` references:

```powershell
Move-Item id_ed25519_sk_ssh_josef      id_ed25519_josef-ssh-key
Move-Item id_ed25519_sk_ssh_josef.pub  id_ed25519_josef-ssh-key.pub
```

#### 3. Register with Windows' ssh-agent

```powershell
ssh-add $HOME\.ssh\id_ed25519_josef-ssh-key
ssh-add -L
# → sk-ssh-ed25519@openssh.com AAAA…== josef-ssh-key
```

#### 4. On the Linux side — hydrate the stub + sockets dir

`~/.ssh/config`'s `IdentityFile` needs the stub file present, even though
signing runs through the agent. Copy from Windows:

```bash
cp /mnt/c/Users/<user>/.ssh/id_ed25519_josef-ssh-key* ~/.ssh/
chmod 600 ~/.ssh/id_ed25519_josef-ssh-key
chmod 644 ~/.ssh/id_ed25519_josef-ssh-key.pub
mkdir -p ~/.ssh/sockets && chmod 700 ~/.ssh/sockets
sudo apt install -y socat   # or: sudo pacman -S socat
```

#### 5. Open a new fish shell — bridge auto-spawns — verify

```bash
ssh-add -l
# → 256 SHA256:… josef-ssh-key (ED25519-SK)   ← Windows agent, via bridge
ssh -T git@github.com
# → Hi <you>! You've successfully authenticated…
```

Same key, no cross-syncing of secrets, `authorized_keys` on your servers
already recognizes it. VPN into home (Wireguard/Tailscale) → `ssh homelab-host`
→ touch YubiKey plugged into the work laptop → in.

---

### First-time provisioning of a new YubiKey (documented for the record)

This is the one-time credential generation. On any second-or-later
machine, use **"Adding this key to a new machine"** above instead — no
regeneration needed.

#### 0. Prep the YubiKey

Firmware ≥ 5.2.3 required for `ed25519-sk`. Check the version in Yubico
Authenticator's home screen. Set a FIDO2 PIN if you haven't already:

```
ykman fido access change-pin
```

#### 1. Generate the credential — on Windows, not WSL

Windows OpenSSH ≥ 8.9 is required (check `ssh -V` in PowerShell).

```powershell
ssh-keygen -t ed25519-sk `
  -O resident `
  -O verify-required `
  -O application=ssh:josef `
  -C "josef-ssh-key" `
  -f $HOME\.ssh\id_ed25519_josef-ssh-key
```

You'll get a touch + PIN prompt twice (once to unlock the token, once to
confirm generation). Two files land in `%USERPROFILE%\.ssh\`:

- `id_ed25519_josef-ssh-key` — **stub / key handle only.** No secret in it;
  the actual private key lives in the token's secure element.
- `id_ed25519_josef-ssh-key.pub` — public key, safe to distribute.

Options in play:

- **`-O resident`** — credential also lives *on* the YubiKey, so
  `ssh-keygen -K` on a fresh machine can reconstruct the stub from just
  the token. **This is what makes the "Adding to a new machine" flow above
  work without moving any files.** Non-resident sk-keys would require
  copying the stub over some other channel.
- **`-O verify-required`** — PIN demanded at every new SSH auth. Combined
  with `ControlPersist 4h` this is roughly one PIN per idle window per
  host. Drop this flag if you'd rather have touch-only convenience.
- **`-O application=ssh:josef`** — namespace inside the token. Lets you
  hold multiple SSH credentials on one YubiKey (e.g. `ssh:josef`,
  `ssh:work-only`) that `ssh-keygen -K` distinguishes.
- **No passphrase** — omitted deliberately. The key is worthless without
  the physical YubiKey; a disk passphrase would add nothing.

#### 2. Load the credential into Windows' ssh-agent

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add $HOME\.ssh\id_ed25519_josef-ssh-key
ssh-add -L
# → sk-ssh-ed25519@openssh.com AAAA…== josef-ssh-key
```

From here, drop into the "Adding this key to a new machine" flow from step
4 onwards to hydrate any WSL / Linux side.

---

### Reference: the bridge

`~/.config/fish/conf.d/ssh-agent-bridge.fish` (tracked) auto-spawns on
every fish start:

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

Guard clause: on Arch (or anywhere without `/mnt/c/Tools/npiperelay.exe`)
the `test -x` short-circuits — the file is safe to sync verbatim.

**Bash / zsh equivalent** for machines without fish — drop into `~/.bashrc`:

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

---

### Reference: `~/.ssh/config`

Tracked in this repo. `Host *` defaults:

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
each host — actual signing goes through agent → Windows → YubiKey. But
`IdentitiesOnly yes` means the stub file must exist; without it, ssh
refuses to fall back to the agent's list. This is why every new machine
needs the `ssh-keygen -K` + copy step.

`ControlMaster` + `ControlPath ~/.ssh/sockets/%C` + `ControlPersist 4h`
give you the one-touch-per-idle-window UX: first `ssh homelab-host` prompts for
PIN + touch; every command against the same host for the next 4h idle
reuses the muxed socket silently.

---

### Deploy the public key to a new server

On each target host:

```
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "sk-ssh-ed25519@openssh.com AAAA…== josef-ssh-key" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Or `ssh-copy-id -i ~/.ssh/id_ed25519_josef-ssh-key.pub <host>` if password
auth is temporarily on.

---

### Test end-to-end

```
ssh -v homelab-host
```

Expect a PIN + touch prompt on Windows on first connect, then instant
reuse on any subsequent SSH/git/Claude Code within `ControlPersist`.

---

### chezmoi / portability notes

- `~/.ssh/config` — tracked as-is (`private_dot_ssh/private_config`), no
  templating.
- The fish bridge — tracked verbatim; safe because `npiperelay.exe` is
  pinned at `C:\Tools\`, not a per-user path.
- **No key material syncs.** The credential never leaves the YubiKey.
  `ssh-keygen -K` reconstructs the stub file on any new machine from just
  the token + PIN.
- **Arch / non-Windows Linux** (future ThinkPad): skip the bridge
  entirely. Native `ssh-agent` + `ssh-add ~/.ssh/id_ed25519_josef-ssh-key`
  handles the YubiKey via `libfido2`. The tracked fish file no-ops
  correctly there. The `ssh-keygen -K` step still applies — same command,
  run in the Linux shell.
- **`verify-required` trade-off**: PIN at every new muxed session. With
  `ControlPersist 4h`, that's once per idle window per host. Regenerate
  the credential without the flag if you want touch-only convenience.

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
