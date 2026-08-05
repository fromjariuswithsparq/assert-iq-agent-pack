#!/usr/bin/env bash
# install.sh — wire the Assert.IQ agent pack into a repo for dual-target use.
# Idempotent: safe to re-run.
#
# What it does:
#   1. Renders .assert-iq/dreaming/session-events.json from its template and
#      syncs it into .claude/settings.json (hooks key — the harness contract),
#      preserving any other keys you already have in .claude/settings.json.
#   2. Scaffolds the Dreaming memory store at .assert-iq/memory/.
#   3. Creates .claude/skills as a symlink to ../.github/skills so Claude
#      Code discovers the same skills Copilot does. Falls back to copy on
#      filesystems that don't support symlinks.
#
# Copilot needs no extra wiring — it reads .github/* natively.
#
# Uninstall: pass --uninstall (or -u) to reverse the above. The uninstall
# step only removes pack-owned wiring; your other keys in
# .claude/settings.json and your .assert-iq/memory/ store are preserved.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Defense-in-depth: refuse to operate at filesystem root if ROOT ever
# resolves to something dangerous (e.g., script relocated to "/").
[[ -n "$ROOT" && "$ROOT" != "/" ]] || { printf 'install.sh: refusing to operate at filesystem root (ROOT=%q)\n' "$ROOT" >&2; exit 1; }

HOOKS_TEMPLATE_LEGACY="$ROOT/hooks/hooks.json"
EVENTS_TEMPLATE="$ROOT/.assert-iq/dreaming/session-events.template.json"
EVENTS_SRC="$ROOT/.assert-iq/dreaming/session-events.json"
MEMORY_DIR="$ROOT/.assert-iq/memory"
SETTINGS_DST="$ROOT/.claude/settings.json"
SKILLS_SRC_REL="../.github/skills"
SKILLS_DST="$ROOT/.claude/skills"
RENDER_LIB="$ROOT/.assert-iq/dreaming/scripts/lib/render-events.sh"

say() { printf '%s\n' "$*"; }
fail() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# Accept --yes/-y in any position as a no-op (parity with bootstrap.sh; this
# installer has no interactive prompts, so the flag is informational only).
args=()
for a in "$@"; do
  case "$a" in --yes|-y) ;; *) args+=("$a") ;; esac
done
set -- "${args[@]:-}"

# ---- Uninstall path ------------------------------------------------------
case "${1:-}" in
  --uninstall|-u)
    say "=== Assert.IQ install.sh: uninstall ==="
    # 1. Remove .claude/skills (symlink or copied dir).
    if [[ -L "$SKILLS_DST" || -e "$SKILLS_DST" ]]; then
      rm -rf "$SKILLS_DST"
      say "[ok] removed $SKILLS_DST"
    fi
    # 2. Strip hooks key from .claude/settings.json (preserve other keys).
    if [[ -f "$SETTINGS_DST" ]]; then
      if command -v jq >/dev/null 2>&1; then
        tmp="$(mktemp "$SETTINGS_DST.XXXXXX")"
        if jq 'del(.hooks)' "$SETTINGS_DST" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
          # If only "{}" remains (no other keys), drop the file entirely.
          if [[ "$(jq -r 'keys | length' "$tmp")" == "0" ]]; then
            rm -f "$SETTINGS_DST" "$tmp"
            say "[ok] removed $SETTINGS_DST (was hooks-only)"
          else
            mv "$tmp" "$SETTINGS_DST"
            say "[ok] stripped hooks key from $SETTINGS_DST"
          fi
        else
          rm -f "$tmp"
          say "[skip] could not parse $SETTINGS_DST; left untouched"
        fi
      else
        say "[skip] jq not installed; cannot safely strip hooks key from $SETTINGS_DST"
      fi
    fi
    # 3. Remove rendered session-events.json (committed source is the template).
    if [[ -f "$EVENTS_SRC" ]]; then
      rm -f "$EVENTS_SRC"
      say "[ok] removed $EVENTS_SRC"
    fi
    # 3a. Remove any leftover rendered file from the retired hooks feature.
    if [[ -f "$HOOKS_TEMPLATE_LEGACY" ]]; then
      rm -f "$HOOKS_TEMPLATE_LEGACY"
      say "[ok] removed legacy $HOOKS_TEMPLATE_LEGACY"
    fi
    # 4. Remove .claude dir if now empty.
    if [[ -d "$ROOT/.claude" ]] && [[ -z "$(ls -A "$ROOT/.claude")" ]]; then
      rmdir "$ROOT/.claude"
      say "[ok] removed empty .claude/"
    fi
    say ""
    say "Uninstall complete."
    say "Pack source files (.github/, CLAUDE.md, AGENTS.md, etc.) are unchanged."
    say "Your .assert-iq/memory/ store is preserved."
    exit 0
    ;;
  --help|-h)
    sed -n '2,18p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
esac

[[ -f "$EVENTS_TEMPLATE" ]] || fail "missing $EVENTS_TEMPLATE"
[[ -f "$RENDER_LIB" ]] || fail "missing $RENDER_LIB"

# shellcheck source=.assert-iq/dreaming/scripts/lib/render-events.sh
source "$RENDER_LIB"

mkdir -p "$ROOT/.claude/agents"

# ---- 0. scaffold the Dreaming memory store -------------------------------
mkdir -p "$MEMORY_DIR/topics" "$MEMORY_DIR/logs" "$MEMORY_DIR/.dream"
[[ -f "$MEMORY_DIR/.dream/state.json" ]] || \
  printf '{\n  "last_dream_utc": null,\n  "sessions_since_dream": 0\n}\n' > "$MEMORY_DIR/.dream/state.json"
say "[ok] ensured Dreaming memory store at .assert-iq/memory/"

# ---- 1. render session-events wiring from template -----------------------
# Substitute __PACK_ROOT__ with this absolute pack path. VS Code Copilot
# does not propagate any env var that carries the workspace path to event
# commands, so the fallback path must be baked in at install time. Claude
# Code's CLAUDE_PLUGIN_ROOT still takes precedence at runtime.
render_events_template "$EVENTS_TEMPLATE" "$EVENTS_SRC" "$ROOT" \
  || fail "failed to render $EVENTS_SRC from template"
say "[ok] rendered .assert-iq/dreaming/session-events.json (pack root: $ROOT)"

# ---- 2. sync session-events into settings --------------------------------
if command -v jq >/dev/null 2>&1; then
    if [[ -f "$SETTINGS_DST" ]]; then
        # Merge: replace only the .hooks key, preserve everything else.
        # Stage the merged JSON next to the destination so the final mv is
        # atomic on the same filesystem, and gate it on jq's exit code so
        # a failed merge can never truncate the user's settings.
        tmp="$(mktemp "$SETTINGS_DST.XXXXXX")"
        cleanup_tmp() { [[ -n "${tmp:-}" && -e "$tmp" ]] && rm -f "$tmp"; }
        trap cleanup_tmp EXIT
        if ! jq -s '.[0] as $existing | .[1] as $new | $existing + {hooks: $new.hooks}' \
                "$SETTINGS_DST" "$EVENTS_SRC" > "$tmp"; then
            fail "jq merge failed; $SETTINGS_DST left untouched"
        fi
        [[ -s "$tmp" ]] || fail "jq merge produced empty output; $SETTINGS_DST left untouched"
        mv "$tmp" "$SETTINGS_DST"
        tmp=""
        trap - EXIT
    else
        cp "$EVENTS_SRC" "$SETTINGS_DST"
    fi
    say "[ok] synced session events -> .claude/settings.json (hooks key)"
else
    # No jq: only safe move is a fresh copy if no settings exist.
    if [[ -f "$SETTINGS_DST" ]]; then
        fail "jq not installed and .claude/settings.json already exists; install jq or merge manually"
    fi
    cp "$EVENTS_SRC" "$SETTINGS_DST"
    say "[ok] copied session events -> .claude/settings.json (jq not present; merge skipped)"
fi

# ---- 3. wire skills ------------------------------------------------------
if [[ -L "$SKILLS_DST" || -e "$SKILLS_DST" ]]; then
    rm -rf "$SKILLS_DST"
fi
if ln -s "$SKILLS_SRC_REL" "$SKILLS_DST" 2>/dev/null; then
    say "[ok] linked .claude/skills -> $SKILLS_SRC_REL"
else
    if [[ -d "$ROOT/.github/skills" ]]; then
        cp -R "$ROOT/.github/skills" "$SKILLS_DST"
        say "[ok] copied .github/skills -> .claude/skills (symlink unavailable; re-run install.sh after skill changes)"
    else
        fail "missing $ROOT/.github/skills; cannot link or copy skills"
    fi
fi

say ""
say "Pack installed."
say "  Copilot reads .github/copilot-instructions.md, .github/instructions/*, .github/agents/*, .github/skills/*"
say "  Claude  reads CLAUDE.md, .claude/agents/*, .claude/skills/*, .claude/settings.json (session events)"
say "  Dreaming memory store: .assert-iq/memory/ (run /dream to consolidate)"
