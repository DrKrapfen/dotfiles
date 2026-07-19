#!/usr/bin/env bash
# Re-hydrate fisher-managed fish plugins after chezmoi apply on a fresh machine.
set -e
command -v fish >/dev/null 2>&1 || exit 0
[ -f "$HOME/.config/fish/fish_plugins" ] || exit 0
fish -c '
if not functions -q fisher
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
    fisher install jorgebucaran/fisher
end
fisher update
'
