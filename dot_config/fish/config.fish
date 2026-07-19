# ~/.config/fish/config.fish — layered per Handoff phases

if status is-interactive
    # Colors: subtle greeting suppression
    set -g fish_greeting
end

# PATH — must precede everything else so `claude` and mise-shims resolve
fish_add_path -g $HOME/.local/bin $HOME/.cargo/bin $HOME/go/bin

# --- Phase 2: mise (version/tool manager) ---
~/.local/bin/mise activate fish | source

# --- Phase 3: uv (Python) — completions ---
if type -q uv
    uv generate-shell-completion fish | source
    uvx --generate-shell-completion fish | source
end

# --- Phase 5: Modern CLI wiring ---
# smart cd (Ctrl-R goes to atuin in Phase 6, so fzf init MUST precede atuin)
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
abbr -a top   'btop'   # btop from apt (installed later) or `btm` if you prefer bottom
abbr -a btm   'btm'
abbr -a zj    'zellij'
abbr -a lg    'lazygit'
abbr -a lzd   'lazydocker'

# --- Phase 6: atuin (local-only, no sync) ---
# NOTE: must come AFTER fzf --fish above so Ctrl-R is bound to atuin (Handoff spec)
if type -q atuin
    atuin init fish | source
end
