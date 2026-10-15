# ~/.config/fish/config.fish

# PATH — must precede everything else so `claude`, `grok` and mise resolve
fish_add_path -g $HOME/.local/bin $HOME/.cargo/bin $HOME/go/bin

# --- mise (version/tool manager) ---
if type -q mise
    mise activate fish | source
end

# --- pnpm (installed via mise) — global bin dir for `pnpm add -g` ---
# pnpm refuses global installs unless this dir is on PATH, and fish_add_path
# skips dirs that don't exist yet — so create it first.
set -gx PNPM_HOME $HOME/.local/share/pnpm
test -d $PNPM_HOME/bin; or mkdir -p $PNPM_HOME/bin
fish_add_path -g $PNPM_HOME/bin

# --- Editor: VS Code on the Windows host (WSL interop), nvim as fallback ---
# (a list, not one quoted string, so `$EDITOR file` also works inside fish;
# over SSH don't pop a window on the Windows desktop)
if type -q code; and not set -q SSH_CONNECTION
    set -gx EDITOR code --wait
else if type -q nvim
    set -gx EDITOR nvim
else
    set -gx EDITOR nano
end
set -gx VISUAL $EDITOR

if status is-interactive
    set -g fish_greeting

    # --- uv (Python) — completions ---
    if type -q uv
        uv generate-shell-completion fish | source
        uvx --generate-shell-completion fish | source
    end

    # --- Modern CLI wiring ---
    # smart cd (Ctrl-R goes to atuin below, so fzf init MUST precede atuin)
    if type -q zoxide
        zoxide init fish | source
    end
    if type -q fzf
        fzf --fish | source
    end

    # friendly aliases / abbreviations
    abbr -a ls    'eza --icons --group-directories-first'
    abbr -a ll    'eza -l --icons --group-directories-first'
    abbr -a la    'eza -la --icons --group-directories-first'
    abbr -a tree  'eza --tree --icons'
    abbr -a cat   'bat'
    abbr -a top   'btop'
    abbr -a zj    'zellij'
    abbr -a lg    'lazygit'
    abbr -a lzd   'lazydocker'

    # --- atuin (history) ---
    # NOTE: must come AFTER fzf --fish above so Ctrl-R is bound to atuin
    if type -q atuin
        atuin init fish | source
    end
end

# Marker block written by grok's installer when run from fish. Keeping it means
# a manual `grok` reinstall replaces it in place (it still appends a blank line
# — `chezmoi apply` restores the file). The bootstrap runs the installer with
# SHELL=/bin/sh so it doesn't touch rc files at all.
# >>> grok installer >>>
fish_add_path -g $HOME/.grok/bin
# <<< grok installer <<<
