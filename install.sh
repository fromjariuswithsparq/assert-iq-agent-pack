#!/usr/bin/env bash
# install.sh — wire the Assert.IQ agent pack into a repo for dual-target use.
# Idempotent: safe to re-run.
#
# What it does:
#   1. Syncs hooks/hooks.json -> .claude/settings.json (hooks key),
#      preserving any other keys you already have in .claude/settings.json.
#   2. Creates .claude/skills as a symlink to ../.github/skills so Claude
#      Code discovers the same skills Copilot does. Falls back to copy on
#      filesystems that don't support symlinks.
#
# Copilot needs no extra wiring — it reads .github/* natively.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_TEMPLATE="$ROOT/hooks/hooks.template.json"
HOOKS_SRC="$ROOT/hooks/hooks.json"
SETTINGS_DST="$ROOT/.claude/settings.json"
SKILLS_SRC_REL="../.github/skills"
SKILLS_DST="$ROOT/.claude/skills"

say() { printf '%s\n' "$*"; }
fail() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

[ -f "$HOOKS_TEMPLATE" ] || fail "missing $HOOKS_TEMPLATE"

mkdir -p "$ROOT/.claude/agents"

# ---- 0. render hooks.json from template ----------------------------------
# Substitute __PACK_ROOT__ with this absolute pack path. VS Code Copilot
# does not propagate any env var that carries the workspace path to hook
# commands, so the fallback path must be baked in at install time. Claude
# Code's CLAUDE_PLUGIN_ROOT still takes precedence at runtime.
# Escape characters with special replacement semantics in sed.
ROOT_SED=${ROOT//\\/\\\\}
ROOT_SED=${ROOT_SED//&/\&}
ROOT_SED=${ROOT_SED//|/\|}
sed "s|__PACK_ROOT__|$ROOT_SED|g" "$HOOKS_TEMPLATE" > "$HOOKS_SRC"
say "[ok] rendered hooks/hooks.json (pack root: $ROOT)"

# ---- 1. sync hooks block -------------------------------------------------
if command -v jq >/dev/null 2>&1; then
    if [ -f "$SETTINGS_DST" ]; then
        # Merge: replace only the .hooks key, preserve everything else.
        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' EXIT
        jq -s '.[0] as $existing | .[1] as $new | $existing + {hooks: $new.hooks}' \
            "$SETTINGS_DST" "$HOOKS_SRC" > "$tmp"
        mv "$tmp" "$SETTINGS_DST"
        trap - EXIT
    else
        cp "$HOOKS_SRC" "$SETTINGS_DST"
    fi
    say "[ok] synced hooks -> .claude/settings.json"
else
    # No jq: only safe move is a fresh copy if no settings exist.
    if [ -f "$SETTINGS_DST" ]; then
        fail "jq not installed and .claude/settings.json already exists; install jq or merge manually"
    fi
    cp "$HOOKS_SRC" "$SETTINGS_DST"
    say "[ok] copied hooks -> .claude/settings.json (jq not present; merge skipped)"
fi

# ---- 2. wire skills ------------------------------------------------------
if [ -L "$SKILLS_DST" ] || [ -e "$SKILLS_DST" ]; then
    rm -rf "$SKILLS_DST"
fi
if ln -s "$SKILLS_SRC_REL" "$SKILLS_DST" 2>/dev/null; then
    say "[ok] linked .claude/skills -> $SKILLS_SRC_REL"
else
    if [ -d "$ROOT/.github/skills" ]; then
        cp -R "$ROOT/.github/skills" "$SKILLS_DST"
        say "[ok] copied .github/skills -> .claude/skills (symlink unavailable; re-run install.sh after skill changes)"
    else
        fail "missing $ROOT/.github/skills; cannot link or copy skills"
    fi
fi

say ""
say "Pack installed."
say "  Copilot reads .github/copilot-instructions.md, .github/instructions/*, .github/agents/*, .github/skills/*"
say "  Claude  reads CLAUDE.md, .claude/agents/*, .claude/skills/*, .claude/settings.json (hooks)"
