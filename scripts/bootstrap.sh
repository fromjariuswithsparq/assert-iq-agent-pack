#!/usr/bin/env bash
# Assert.IQ Agent Pack — workspace bootstrap (macOS / Linux)
#
# Copies workspace-loaded surfaces (instructions, .assert-iq/, CLAUDE.md,
# copilot-instructions.md, AGENTS.md) from a plugin install into the
# user's workspace or user-global slots.
#
# Three install modes:
#   --mode=committed   Files are visible to git; user opts in to commit.
#   --mode=trial       Files are added to .git/info/exclude (local-only,
#                      codebase .gitignore untouched). User can graduate
#                      to committed later with --graduate.
#   --mode=ask         Interactive prompt (default when TTY). Non-TTY
#                      falls back to committed.
#
# Other modes:
#   --graduate / --untrial   Reverse trial mode: remove pack entries from
#                            .git/info/exclude. Files stay on disk.
#
# See .github/skills/assert-iq-bootstrap/SKILL.md for full docs.

set -euo pipefail

# ---- Defaults ---------------------------------------------------------------
PRESET=""
ASSERT_IQ=""
INSTRUCTIONS=""
CLAUDE_MD=""
COPILOT=""
AGENTS_MD=""
VSCODE=""
HOOKS=""
CLAUDE_SETTINGS=""
WORKSPACE="$PWD"
MODE=""
GRADUATE=0
CONFLICT_BULK_CHOICE=""   # K|O|S once user picks an "-all" shortcut
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

EXCLUDE_BEGIN="# >>> assert-iq trial mode (managed) >>>"
EXCLUDE_END="# <<< assert-iq trial mode (managed) <<<"

# ---- Parse flags ------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --preset=*)          PRESET="${arg#*=}" ;;
    --assert-iq=*)       ASSERT_IQ="${arg#*=}" ;;
    --instructions=*)    INSTRUCTIONS="${arg#*=}" ;;
    --claude=*)          CLAUDE_MD="${arg#*=}" ;;
    --copilot=*)         COPILOT="${arg#*=}" ;;
    --agents=*)          AGENTS_MD="${arg#*=}" ;;
    --vscode=*)          VSCODE="${arg#*=}" ;;
    --hooks=*)           HOOKS="${arg#*=}" ;;
    --claude-settings=*) CLAUDE_SETTINGS="${arg#*=}" ;;
    --workspace=*)       WORKSPACE="${arg#*=}" ;;
    --source=*)          SOURCE="${arg#*=}" ;;
    --mode=*)            MODE="${arg#*=}" ;;
    --trial)             MODE="trial" ;;
    --committed)         MODE="committed" ;;
    --graduate|--untrial) GRADUATE=1 ;;
    --help|-h)
      sed -n '2,20p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

# ---- Resolve user-global paths by OS ----------------------------------------
case "$(uname -s)" in
  Darwin)
    USER_PROMPTS="$HOME/Library/Application Support/Code/User/prompts"
    ;;
  Linux|*)
    USER_PROMPTS="$HOME/.config/Code/User/prompts"
    ;;
esac
USER_ASSERT_IQ="$HOME/.assert-iq"
USER_CLAUDE_MD="$HOME/.claude/CLAUDE.md"

MANIFEST_PATH="$WORKSPACE/.assert-iq/.install-manifest.json"

# =============================================================================
# Manifest, sha256, git-exclude helpers
# =============================================================================

sha256_of() {
  # Prints sha256 hex of file at $1, or empty if file missing.
  [[ -f "$1" ]] || { echo ""; return; }
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo ""  # no hasher; treat as unknown, will not match
  fi
}

declare -a MANIFEST_ENTRIES=()

manifest_add() {
  # action | abs_path | scope (workspace|user)
  local action="$1" path="$2" scope="$3"
  MANIFEST_ENTRIES+=("$action|$path|$scope")
}

manifest_write() {
  # Merge with existing manifest if present (preserve older entries).
  local out_dir
  out_dir="$(dirname "$MANIFEST_PATH")"
  mkdir -p "$out_dir"
  local pack_version="unknown"
  if [[ -f "$SOURCE/.claude-plugin/plugin.json" ]] && command -v jq >/dev/null 2>&1; then
    pack_version="$(jq -r '.version // "unknown"' "$SOURCE/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)"
  fi
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if command -v jq >/dev/null 2>&1; then
    # Build new entries array via jq.
    local new_json="[]"
    local e
    for e in "${MANIFEST_ENTRIES[@]}"; do
      IFS='|' read -r a p s <<< "$e"
      new_json="$(jq --arg a "$a" --arg p "$p" --arg s "$s" '. + [{action:$a, path:$p, scope:$s}]' <<< "$new_json")"
    done
    if [[ -f "$MANIFEST_PATH" ]]; then
      # Merge: prefer new entry for same path, keep older paths not touched this run.
      jq --arg v "$pack_version" --arg t "$now" --arg m "$MODE" \
         --argjson new "$new_json" \
         '{
            version:$v,
            installed_at:$t,
            mode:$m,
            paths: (
              ([.paths[]? | select((.path) as $p | ($new | map(.path) | index($p)) == null)])
              + $new
            )
          }' "$MANIFEST_PATH" > "$MANIFEST_PATH.tmp" && mv "$MANIFEST_PATH.tmp" "$MANIFEST_PATH"
    else
      jq -n --arg v "$pack_version" --arg t "$now" --arg m "$MODE" --argjson new "$new_json" \
        '{version:$v, installed_at:$t, mode:$m, paths:$new}' > "$MANIFEST_PATH"
    fi
  else
    # No jq: write a simple, valid JSON ourselves (replace, no merge — best we can do).
    {
      printf '{\n  "version": "%s",\n  "installed_at": "%s",\n  "mode": "%s",\n  "paths": [\n' \
        "$pack_version" "$now" "$MODE"
      local i=0 n=${#MANIFEST_ENTRIES[@]}
      for e in "${MANIFEST_ENTRIES[@]}"; do
        IFS='|' read -r a p s <<< "$e"
        i=$((i+1))
        local sep=","
        [[ $i -eq $n ]] && sep=""
        printf '    {"action": "%s", "path": "%s", "scope": "%s"}%s\n' "$a" "$p" "$s" "$sep"
      done
      printf '  ]\n}\n'
    } > "$MANIFEST_PATH"
  fi
}

# --- Git-exclude block management -------------------------------------------

git_dir() {
  # Echoes absolute .git dir for $WORKSPACE, or empty if not a repo.
  ( cd "$WORKSPACE" 2>/dev/null && git rev-parse --git-dir 2>/dev/null ) || echo ""
}

exclude_file_path() {
  local gd
  gd="$(git_dir)"
  [[ -n "$gd" ]] || { echo ""; return; }
  # git rev-parse --git-dir returns relative; resolve against workspace.
  if [[ "$gd" = /* ]]; then
    echo "$gd/info/exclude"
  else
    echo "$WORKSPACE/$gd/info/exclude"
  fi
}

is_tracked() {
  # $1 = absolute path inside workspace. Returns 0 if tracked.
  local rel="${1#$WORKSPACE/}"
  ( cd "$WORKSPACE" && git ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 )
}

write_exclude_block() {
  # Writes the managed block to .git/info/exclude with the workspace-scoped
  # entries from the manifest. Replaces any existing block atomically.
  local excl
  excl="$(exclude_file_path)"
  if [[ -z "$excl" ]]; then
    echo "WARN: not inside a git repo — skipping .git/info/exclude wiring." >&2
    echo "      Pack files are present on disk; commit them only when ready." >&2
    return
  fi
  mkdir -p "$(dirname "$excl")"
  touch "$excl"

  # Collect workspace-scoped manifest paths, relative to workspace root.
  # Filter out already-tracked files (we don't auto-untrack).
  local -a rels=() skipped_tracked=()
  local e a p s rel
  for e in "${MANIFEST_ENTRIES[@]}"; do
    IFS='|' read -r a p s <<< "$e"
    [[ "$s" == "workspace" ]] || continue
    [[ "$a" == "created" || "$a" == "unchanged_owned" || "$a" == "overwritten" || "$a" == "merged_hooks_key" || "$a" == "merged_settings" || "$a" == "rendered" || "$a" == "sidecar" ]] || continue
    rel="${p#$WORKSPACE/}"
    if is_tracked "$p"; then
      skipped_tracked+=("$rel")
      continue
    fi
    rels+=("$rel")
  done

  # Always exclude the manifest itself so it doesn't leak into git status.
  local manifest_rel="${MANIFEST_PATH#$WORKSPACE/}"
  if ! is_tracked "$MANIFEST_PATH"; then
    rels+=("$manifest_rel")
  fi

  # Atomic block replace.
  local tmp="$excl.tmp"
  awk -v b="$EXCLUDE_BEGIN" -v e="$EXCLUDE_END" '
    BEGIN { skip=0 }
    {
      if ($0 == b) { skip=1; next }
      if (skip && $0 == e) { skip=0; next }
      if (!skip) print
    }
  ' "$excl" > "$tmp"
  {
    cat "$tmp"
    printf '%s\n' "$EXCLUDE_BEGIN"
    printf '# Managed by scripts/bootstrap.sh — do not edit by hand.\n'
    printf '# Remove with: scripts/bootstrap.sh --graduate\n'
    local r
    for r in "${rels[@]}"; do
      printf '%s\n' "$r"
    done
    printf '%s\n' "$EXCLUDE_END"
  } > "$tmp.2"
  mv "$tmp.2" "$excl"
  rm -f "$tmp"

  echo ""
  echo "Trial mode active. ${#rels[@]} path(s) added to .git/info/exclude."
  if ((${#skipped_tracked[@]} > 0)); then
    echo ""
    echo "NOTE: ${#skipped_tracked[@]} path(s) already tracked by git — left visible:"
    local t
    for t in "${skipped_tracked[@]}"; do printf '  %s\n' "$t"; done
    echo ""
    echo "If you want trial-mode behavior on those too, run (per path):"
    echo "  git rm --cached <path>"
    echo "Then re-run: scripts/bootstrap.sh --trial"
  fi
  echo ""
  echo "To expose these files to your team's git later:"
  echo "  scripts/bootstrap.sh --graduate"
}

strip_exclude_block() {
  local excl
  excl="$(exclude_file_path)"
  [[ -n "$excl" && -f "$excl" ]] || { echo "No .git/info/exclude found — nothing to do."; return; }
  local tmp="$excl.tmp"
  awk -v b="$EXCLUDE_BEGIN" -v e="$EXCLUDE_END" '
    BEGIN { skip=0; removed=0 }
    {
      if ($0 == b) { skip=1; removed=1; next }
      if (skip && $0 == e) { skip=0; next }
      if (!skip) print
    }
    END { exit (removed?0:1) }
  ' "$excl" > "$tmp" && removed=1 || removed=0
  mv "$tmp" "$excl"
  if [[ $removed -eq 1 ]]; then
    echo "Removed Assert.IQ managed block from $excl"
  else
    echo "No Assert.IQ managed block found in $excl — nothing to remove."
  fi
}

# =============================================================================
# --graduate short-circuit
# =============================================================================

if [[ $GRADUATE -eq 1 ]]; then
  echo "=== Assert.IQ graduate: trial -> committed ==="
  strip_exclude_block
  if [[ -f "$MANIFEST_PATH" ]] && command -v jq >/dev/null 2>&1; then
    jq '.mode = "committed"' "$MANIFEST_PATH" > "$MANIFEST_PATH.tmp" && mv "$MANIFEST_PATH.tmp" "$MANIFEST_PATH"
    echo "Updated $MANIFEST_PATH: mode -> committed"
  fi
  echo ""
  echo "Pack files are now visible to git. Suggested next steps:"
  echo "  git status                       # confirm pack files are untracked"
  echo "  git add .assert-iq .claude .github CLAUDE.md AGENTS.md"
  echo "  git commit -m \"chore: adopt Assert.IQ agent pack\""
  exit 0
fi

# =============================================================================
# Mode resolution (interactive prompt for ask-mode)
# =============================================================================

resolve_mode() {
  # Already set explicitly?
  case "$MODE" in
    trial|committed) return ;;
    ""|ask)
      if [[ -t 0 ]]; then
        echo ""
        echo "Choose install mode:"
        echo "  [t] Trial    — files added but ignored by .git/info/exclude"
        echo "                 (codebase .gitignore untouched; team won't see them)"
        echo "  [c] Committed — files visible to git (you commit when ready)"
        echo ""
        local ans=""
        while :; do
          read -r -p "Mode [t/c] (default c): " ans
          ans="${ans:-c}"
          case "$ans" in
            t|T|trial)     MODE="trial"; return ;;
            c|C|committed) MODE="committed"; return ;;
          esac
        done
      else
        MODE="committed"
      fi
      ;;
    *)
      echo "ERROR: invalid --mode value '$MODE' (expected: trial, committed, ask)" >&2
      exit 2
      ;;
  esac
}

resolve_mode

# =============================================================================
# Apply preset defaults (must run after mode is resolved)
# =============================================================================

case "$PRESET" in
  solo)
    : "${ASSERT_IQ:=workspace}"
    : "${INSTRUCTIONS:=user}"
    : "${CLAUDE_MD:=user}"
    : "${COPILOT:=workspace}"
    : "${AGENTS_MD:=workspace}"
    : "${VSCODE:=workspace}"
    : "${HOOKS:=workspace}"
    : "${CLAUDE_SETTINGS:=workspace}"
    ;;
  pod|"")
    : "${ASSERT_IQ:=workspace}"
    : "${INSTRUCTIONS:=workspace}"
    : "${CLAUDE_MD:=workspace}"
    : "${COPILOT:=workspace}"
    : "${AGENTS_MD:=workspace}"
    : "${VSCODE:=workspace}"
    : "${HOOKS:=workspace}"
    : "${CLAUDE_SETTINGS:=workspace}"
    ;;
  *)
    echo "ERROR: unknown --preset value '$PRESET' (expected: solo, pod)" >&2
    exit 2
    ;;
esac

# =============================================================================
# Result tracking + copy primitives
# =============================================================================

declare -a RESULTS=()

record() {
  RESULTS+=("$1|$2|$3")
}

resolve_conflict() {
  # Args: src dst label
  # Prints one of: keep|overwrite|sidecar
  local src="$1" dst="$2" label="$3"
  # Honor "-all" shortcut if set.
  case "$CONFLICT_BULK_CHOICE" in
    K) echo keep; return ;;
    O) echo overwrite; return ;;
    S) echo sidecar; return ;;
  esac
  if [[ ! -t 0 ]]; then
    # Non-interactive fallback: keep existing (safest).
    echo keep
    return
  fi
  echo "" >&2
  echo "Conflict: $label" >&2
  echo "  existing: $dst" >&2
  echo "  pack:     $src" >&2
  local ans=""
  while :; do
    read -r -p "  [k]eep / [o]verwrite / [s]idecar (.assert-iq-new) / [d]iff / [K/O/S]all / [a]bort: " ans </dev/tty
    case "$ans" in
      k) echo keep; return ;;
      o) echo overwrite; return ;;
      s) echo sidecar; return ;;
      K) CONFLICT_BULK_CHOICE=K; echo keep; return ;;
      O) CONFLICT_BULK_CHOICE=O; echo overwrite; return ;;
      S) CONFLICT_BULK_CHOICE=S; echo sidecar; return ;;
      d)
        if command -v diff >/dev/null 2>&1; then
          diff -u "$dst" "$src" >&2 || true
        else
          echo "  (diff not available)" >&2
        fi
        ;;
      a) echo "Aborted by user." >&2; exit 1 ;;
      *) echo "  (please type one of k, o, s, d, K, O, S, a)" >&2 ;;
    esac
  done
}

copy_file() {
  # Args: label src dst scope (workspace|user)
  local label="$1" src="$2" dst="$3" scope="$4"
  if [[ ! -e "$src" ]]; then
    record "$label" "missing-source" "$src"
    return
  fi
  if [[ ! -e "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    manifest_add "created" "$dst" "$scope"
    record "$label" "copied" "$dst"
    return
  fi
  # Destination exists. Compare hashes.
  local sh_src sh_dst
  sh_src="$(sha256_of "$src")"
  sh_dst="$(sha256_of "$dst")"
  if [[ -n "$sh_src" && "$sh_src" == "$sh_dst" ]]; then
    manifest_add "unchanged_owned" "$dst" "$scope"
    record "$label" "unchanged (pack-owned)" "$dst"
    return
  fi
  # Differs — invoke resolver.
  local choice
  choice="$(resolve_conflict "$src" "$dst" "$label")"
  case "$choice" in
    keep)
      record "$label" "skipped (user kept existing)" "$dst"
      ;;
    overwrite)
      cp "$src" "$dst"
      manifest_add "overwritten" "$dst" "$scope"
      record "$label" "overwritten" "$dst"
      ;;
    sidecar)
      local side="$dst.assert-iq-new"
      cp "$src" "$side"
      manifest_add "sidecar" "$side" "$scope"
      record "$label" "sidecar -> .assert-iq-new" "$side"
      ;;
  esac
}

copy_tree() {
  # Args: label src_dir dst_dir scope
  # Walks src_dir and per-file-copies into dst_dir, preserving relative layout.
  local label="$1" src_dir="$2" dst_dir="$3" scope="$4"
  if [[ ! -d "$src_dir" ]]; then
    record "$label" "missing-source" "$src_dir"
    return
  fi
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#$src_dir/}"
    copy_file "$label/$rel" "$f" "$dst_dir/$rel" "$scope"
  done < <(find "$src_dir" -type f -print0)
}

merge_json_file() {
  # Deep-merge $src JSON into $dst JSON. Existing $dst keys win on scalar
  # conflicts (additive, never clobbers user settings). Requires jq.
  # If $dst is missing, behaves like copy_file.
  # Args: label src dst scope
  local label="$1" src="$2" dst="$3" scope="$4"
  if [[ ! -e "$src" ]]; then
    record "$label" "missing-source" "$src"
    return
  fi
  if [[ ! -e "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    manifest_add "created" "$dst" "$scope"
    record "$label" "copied" "$dst"
    return
  fi
  # Identical?
  local sh_src sh_dst
  sh_src="$(sha256_of "$src")"
  sh_dst="$(sha256_of "$dst")"
  if [[ -n "$sh_src" && "$sh_src" == "$sh_dst" ]]; then
    manifest_add "unchanged_owned" "$dst" "$scope"
    record "$label" "unchanged (pack-owned)" "$dst"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    # No jq: fall back to sidecar (never silently overwrite a user JSON).
    local side="$dst.assert-iq-new"
    cp "$src" "$side"
    manifest_add "sidecar" "$side" "$scope"
    record "$label" "sidecar (jq missing) -> .assert-iq-new" "$side"
    return
  fi
  # Deep merge: pack first, user second -> user wins on scalar conflicts.
  local tmp
  tmp="$(mktemp)"
  if jq -s '.[0] * .[1]' "$src" "$dst" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$dst"
    manifest_add "merged_settings" "$dst" "$scope"
    record "$label" "merged (additive, yours wins)" "$dst"
  else
    rm -f "$tmp"
    # Invalid JSON on user side — don't risk corruption, write sidecar.
    local side="$dst.assert-iq-new"
    cp "$src" "$side"
    manifest_add "sidecar" "$side" "$scope"
    record "$label" "sidecar (existing not valid JSON) -> .assert-iq-new" "$side"
  fi
}

render_hooks_json() {
  # Renders hooks/hooks.template.json with __PACK_ROOT__ -> $1 (workspace root).
  # Echoes path to the rendered temp file. Caller must rm it.
  local pack_root="$1"
  local template="$SOURCE/hooks/hooks.template.json"
  [[ -f "$template" ]] || { echo ""; return; }
  local tmp
  tmp="$(mktemp)"
  # Use '|' delimiter since filesystem paths normally don't contain it.
  sed "s|__PACK_ROOT__|$pack_root|g" "$template" > "$tmp"
  echo "$tmp"
}

# =============================================================================
# Per-surface handlers
# =============================================================================

process_assert_iq() {
  case "$ASSERT_IQ" in
    workspace) copy_tree ".assert-iq" "$SOURCE/.assert-iq" "$WORKSPACE/.assert-iq" "workspace" ;;
    user)      copy_tree ".assert-iq" "$SOURCE/.assert-iq" "$USER_ASSERT_IQ"       "user" ;;
    skip)      record ".assert-iq" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --assert-iq value '$ASSERT_IQ'" >&2; exit 2 ;;
  esac
}

process_instructions() {
  case "$INSTRUCTIONS" in
    workspace)
      local dest="$WORKSPACE/.github/instructions"
      shopt -s nullglob
      for f in "$SOURCE/.github/instructions/"*.instructions.md; do
        copy_file "instructions/$(basename "$f")" "$f" "$dest/$(basename "$f")" "workspace"
      done
      shopt -u nullglob
      ;;
    user)
      shopt -s nullglob
      for f in "$SOURCE/.github/instructions/"*.instructions.md; do
        copy_file "instructions/$(basename "$f")" "$f" "$USER_PROMPTS/$(basename "$f")" "user"
      done
      shopt -u nullglob
      ;;
    skip) record "instructions" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --instructions value '$INSTRUCTIONS'" >&2; exit 2 ;;
  esac
}

process_claude() {
  case "$CLAUDE_MD" in
    workspace) copy_file "CLAUDE.md" "$SOURCE/CLAUDE.md" "$WORKSPACE/CLAUDE.md" "workspace" ;;
    user)      copy_file "CLAUDE.md" "$SOURCE/CLAUDE.md" "$USER_CLAUDE_MD"      "user" ;;
    skip)      record "CLAUDE.md" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --claude value '$CLAUDE_MD'" >&2; exit 2 ;;
  esac
}

process_copilot() {
  case "$COPILOT" in
    workspace)
      copy_file "copilot-instructions.md" \
        "$SOURCE/.github/copilot-instructions.md" \
        "$WORKSPACE/.github/copilot-instructions.md" \
        "workspace"
      ;;
    user)
      echo "WARN: copilot-instructions.md has no native user-global slot. Skipping." >&2
      echo "      (The .instructions.md files under --instructions=user cover the" >&2
      echo "       same QI rules and load globally from the user prompts folder.)" >&2
      record "copilot-instructions.md" "skipped (no user-global slot)" "-"
      ;;
    skip) record "copilot-instructions.md" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --copilot value '$COPILOT'" >&2; exit 2 ;;
  esac
}

process_agents() {
  case "$AGENTS_MD" in
    workspace) copy_file "AGENTS.md" "$SOURCE/AGENTS.md" "$WORKSPACE/AGENTS.md" "workspace" ;;
    user)
      echo "WARN: AGENTS.md has no native user-global slot. Skipping." >&2
      record "AGENTS.md" "skipped (no user-global slot)" "-"
      ;;
    skip) record "AGENTS.md" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --agents value '$AGENTS_MD'" >&2; exit 2 ;;
  esac
}

process_vscode() {
  # .vscode/settings.json wires VS Code Copilot to read instructions, prompts,
  # and hooks from the workspace. .vscode/mcp.json wires MCP servers.
  case "$VSCODE" in
    workspace)
      merge_json_file ".vscode/settings.json" \
        "$SOURCE/.vscode/settings.json" \
        "$WORKSPACE/.vscode/settings.json" \
        "workspace"
      # mcp.json: deep-merge if jq available (servers object union, inputs
      # array gets clobbered — acceptable since most users won't have mcp.json).
      if [[ -f "$WORKSPACE/.vscode/mcp.json" ]]; then
        merge_json_file ".vscode/mcp.json" \
          "$SOURCE/.vscode/mcp.json" \
          "$WORKSPACE/.vscode/mcp.json" \
          "workspace"
      else
        copy_file ".vscode/mcp.json" \
          "$SOURCE/.vscode/mcp.json" \
          "$WORKSPACE/.vscode/mcp.json" \
          "workspace"
      fi
      ;;
    user)
      echo "WARN: .vscode/ has no native user-global slot. Skipping." >&2
      record ".vscode/" "skipped (no user-global slot)" "-"
      ;;
    skip) record ".vscode/" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --vscode value '$VSCODE'" >&2; exit 2 ;;
  esac
}

process_hooks() {
  # hooks/ in the workspace root is what .vscode/settings.json's
  # chat.hookFilesLocations points at ("./hooks/hooks.json"). Renders
  # hooks.json with __PACK_ROOT__ = $WORKSPACE so the scripts resolve
  # to the workspace copies even when CLAUDE_PLUGIN_ROOT is unset.
  case "$HOOKS" in
    workspace)
      if [[ ! -d "$SOURCE/hooks" ]]; then
        record "hooks/" "missing-source" "$SOURCE/hooks"
        return
      fi
      # Copy scripts/ and lib/ trees verbatim.
      if [[ -d "$SOURCE/hooks/scripts" ]]; then
        copy_tree "hooks/scripts" "$SOURCE/hooks/scripts" "$WORKSPACE/hooks/scripts" "workspace"
      fi
      if [[ -d "$SOURCE/hooks/lib" ]]; then
        copy_tree "hooks/lib" "$SOURCE/hooks/lib" "$WORKSPACE/hooks/lib" "workspace"
      fi
      if [[ -d "$SOURCE/hooks/config" ]]; then
        copy_tree "hooks/config" "$SOURCE/hooks/config" "$WORKSPACE/hooks/config" "workspace"
      fi
      # Runtime dirs: state/ + logs/ hold seed JSON and append-only logs that
      # the hook scripts read and write. sessions/ is created empty; per-session
      # subdirs are written at SessionStart.
      if [[ -d "$SOURCE/hooks/state" ]]; then
        copy_tree "hooks/state" "$SOURCE/hooks/state" "$WORKSPACE/hooks/state" "workspace"
      fi
      if [[ -d "$SOURCE/hooks/logs" ]]; then
        copy_tree "hooks/logs" "$SOURCE/hooks/logs" "$WORKSPACE/hooks/logs" "workspace"
      fi
      mkdir -p "$WORKSPACE/hooks/sessions"
      manifest_add "created" "$WORKSPACE/hooks/sessions" "workspace"
      record "hooks/sessions/" "created" "$WORKSPACE/hooks/sessions"
      # Render hooks.json with __PACK_ROOT__ = workspace.
      local rendered
      rendered="$(render_hooks_json "$WORKSPACE")"
      if [[ -z "$rendered" ]]; then
        record "hooks/hooks.json" "missing-template" "$SOURCE/hooks/hooks.template.json"
      else
        copy_file "hooks/hooks.json" "$rendered" "$WORKSPACE/hooks/hooks.json" "workspace"
        rm -f "$rendered"
      fi
      ;;
    skip) record "hooks/" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --hooks value '$HOOKS'" >&2; exit 2 ;;
  esac
}

process_claude_settings() {
  # .claude/settings.json — Claude Code reads the hooks block from here.
  # VS Code Copilot side disables it via chat.hookFilesLocations to avoid
  # double-fire. Merge only the .hooks key; preserve everything else the
  # user may have under .claude/settings.json.
  case "$CLAUDE_SETTINGS" in
    workspace)
      local rendered
      rendered="$(render_hooks_json "$WORKSPACE")"
      if [[ -z "$rendered" ]]; then
        record ".claude/settings.json" "missing-template" "$SOURCE/hooks/hooks.template.json"
        return
      fi
      local dst="$WORKSPACE/.claude/settings.json"
      mkdir -p "$(dirname "$dst")"
      if [[ ! -f "$dst" ]]; then
        cp "$rendered" "$dst"
        manifest_add "created" "$dst" "workspace"
        record ".claude/settings.json" "copied" "$dst"
      elif command -v jq >/dev/null 2>&1; then
        # Replace only the .hooks key, preserve everything else.
        local tmp
        tmp="$(mktemp)"
        if jq -s '.[0] as $existing | .[1] as $new | $existing + {hooks: $new.hooks}' \
            "$dst" "$rendered" > "$tmp" 2>/dev/null; then
          mv "$tmp" "$dst"
          manifest_add "merged_hooks_key" "$dst" "workspace"
          record ".claude/settings.json" "merged hooks key" "$dst"
        else
          rm -f "$tmp"
          local side="$dst.assert-iq-new"
          cp "$rendered" "$side"
          manifest_add "sidecar" "$side" "workspace"
          record ".claude/settings.json" "sidecar (merge failed)" "$side"
        fi
      else
        local side="$dst.assert-iq-new"
        cp "$rendered" "$side"
        manifest_add "sidecar" "$side" "workspace"
        record ".claude/settings.json" "sidecar (jq missing)" "$side"
      fi
      rm -f "$rendered"
      ;;
    skip) record ".claude/settings.json" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --claude-settings value '$CLAUDE_SETTINGS'" >&2; exit 2 ;;
  esac
}

process_assert_iq
process_instructions
process_claude
process_copilot
process_agents
process_vscode
process_hooks
process_claude_settings

# =============================================================================
# Finalize: manifest + git-exclude wiring (trial mode only)
# =============================================================================

manifest_write

if [[ "$MODE" == "trial" ]]; then
  write_exclude_block
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=== Assert.IQ bootstrap summary ==="
echo "Source:    $SOURCE"
echo "Workspace: $WORKSPACE"
echo "Preset:    ${PRESET:-(none)}"
echo "Mode:      $MODE"
echo "Manifest:  $MANIFEST_PATH"
echo ""
printf "%-44s %-30s %s\n" "Surface" "Result" "Destination"
printf "%-44s %-30s %s\n" "-------" "------" "-----------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r label result dst <<< "$r"
  printf "%-44s %-30s %s\n" "$label" "$result" "$dst"
done
echo ""

# Surface conflict-resolution outcomes prominently
sidecar_count=0
kept_count=0
for r in "${RESULTS[@]}"; do
  IFS='|' read -r _ result _ <<< "$r"
  case "$result" in
    "sidecar -> .assert-iq-new") sidecar_count=$((sidecar_count+1)) ;;
    "skipped (user kept existing)") kept_count=$((kept_count+1)) ;;
  esac
done
if [[ $sidecar_count -gt 0 ]]; then
  echo "NOTE: $sidecar_count file(s) written as .assert-iq-new sidecars."
  echo "      Diff them against your existing files when ready, then delete the sidecar."
fi
if [[ $kept_count -gt 0 ]]; then
  echo "NOTE: $kept_count existing file(s) kept untouched (you chose 'keep')."
fi

echo "Reload your editor window so the new instructions and config are picked up:"
echo "  - VS Code:    Cmd/Ctrl + Shift + P -> 'Developer: Reload Window'"
echo "  - Claude Code: restart the session"
