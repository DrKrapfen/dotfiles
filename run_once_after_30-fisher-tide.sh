#!/usr/bin/env bash
# Re-hydrate fisher-managed fish plugins and pin the Tide prompt look.
set -euo pipefail
if ! command -v fish >/dev/null 2>&1; then
    # Fail (don't exit 0) so chezmoi retries on the next apply instead of
    # marking this script as done.
    echo "fisher-tide: fish is not installed — install it, then re-run 'chezmoi apply'" >&2
    exit 1
fi
fish -c '
if not functions -q fisher
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
    fisher install jorgebucaran/fisher
end
fisher update; or exit 1
# tide clears the screen when done — silence it so earlier apply output stays visible
tide configure --auto --style=Lean --prompt_colors="True color" --show_time=No \
    --lean_prompt_height="Two lines" --prompt_connection=Disconnected \
    --prompt_spacing=Sparse --icons="Few icons" --transient=No >/dev/null
'
