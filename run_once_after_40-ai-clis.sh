#!/usr/bin/env bash
# Agent CLIs (native installers keep their own self-updaters) + shared skills.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
MISE="$(command -v mise || echo "$HOME/.local/bin/mise")"
failed=()

command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash || failed+=(claude)
# SHELL=/bin/sh: stop grok's installer from editing shell rc files (config.fish
# is chezmoi-managed and already has ~/.local/bin, where the grok symlink lives)
command -v grok   >/dev/null 2>&1 || curl -fsSL https://x.ai/cli/install.sh  | SHELL=/bin/sh bash || failed+=(grok)

# Third-party skills (npx skills), linked into Claude Code and Grok
skills() { "$MISE" exec node@lts -- npx -y skills add "$@" -g -y -a claude-code grok; }
skills stablyai/orca -s orca-cli orchestration computer-use orca-linear || failed+=(skills:orca)
skills vercel-labs/skills -s find-skills || failed+=(skills:find-skills)

if [ ${#failed[@]} -gt 0 ]; then
    echo "ai-clis: failed: ${failed[*]} — re-run 'chezmoi apply' to retry" >&2
    exit 1
fi
