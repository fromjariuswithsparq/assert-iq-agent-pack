#!/usr/bin/env bash
# Assert.IQ Agent Pack — workspace bootstrap (macOS / Linux)
#
# Copies workspace-loaded surfaces (instructions, .assert-iq/, CLAUDE.md,
# copilot-instructions.md, AGENTS.md) from the cloned pack into the
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
# Skills scope (where the 24 QI skills land):
#   --skills-scope=workspace   (default) workspace .github/skills + .claude/skills symlink
#   --skills-scope=user        only ~/.agents/skills + ~/.claude/skills (every workspace gets them)
#   --skills-scope=both        workspace AND user-global
#
# Presets:
#   --preset=pod        (default) team install — everything in workspace
#   --preset=solo       solo dev — instructions + CLAUDE.md user-global
#   --preset=portable   skills user-global, minimal workspace footprint
#                       (chat agents + manifest still live in the repo)
#
# Other modes:
#   --graduate / --untrial   Reverse trial mode: remove pack entries from
#                            .git/info/exclude. Files stay on disk.
#   --uninstall              Reverse install: delete pack-created files,
#                            restore pre-install backups for files we modified,
#                            strip the trial-mode exclude block, and remove
#                            the manifest. Use --user to also remove user-scope
#                            copies. --yes skips the confirmation prompt;
#                            --dry-run shows what would happen without changing.
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
SKILLS_SCOPE=""
WORKSPACE="$PWD"
MODE=""
GRADUATE=0
UNINSTALL=0
UNINSTALL_USER=0
ASSUME_YES=0
DRY_RUN=0
CONFLICT_BULK_CHOICE=""   # K|O|S once user picks an "-all" shortcut
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

EXCLUDE_BEGIN="# >>> assert-iq trial mode (managed) >>>"
EXCLUDE_END="# <<< assert-iq trial mode (managed) <<<"

# Manifest action vocabulary — kept here so adding a new action only touches
# one place. REMOVABLE_ACTIONS are deleted on uninstall; EXCLUDABLE_ACTIONS
# get emitted into .git/info/exclude in trial mode.
REMOVABLE_ACTIONS="created unchanged_owned overwritten rendered sidecar"
EXCLUDABLE_ACTIONS="created unchanged_owned overwritten merged_hooks_key merged_settings rendered sidecar"
MERGED_ACTIONS="merged_settings merged_hooks_key"

_in_action_set() {
  # $1 = action, $2 = space-separated set
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

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
    --skills-scope=*)    SKILLS_SCOPE="${arg#*=}" ;;
    --workspace=*)       WORKSPACE="${arg#*=}" ;;
    --source=*)          SOURCE="${arg#*=}" ;;
    --mode=*)            MODE="${arg#*=}" ;;
    --trial)             MODE="trial" ;;
    --committed)         MODE="committed" ;;
    --graduate|--untrial) GRADUATE=1 ;;
    --uninstall)        UNINSTALL=1 ;;
    --user)             UNINSTALL_USER=1 ;;
    --yes|-y)           ASSUME_YES=1 ;;
    --dry-run)          DRY_RUN=1 ;;
    --help|-h)
      sed -n '2,40p' "${BASH_SOURCE[0]}"
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
USER_VSCODE_SKILLS="$HOME/.agents/skills"
USER_CLAUDE_SKILLS="$HOME/.claude/skills"

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

backup_if_user_owned() {
  # Snapshot a pre-existing user file before we modify or overwrite it, so
  # --uninstall can restore the original. No-op if no destination file
  # exists yet, or if a backup is already on disk (idempotent across re-runs).
  # Args: dst scope
  local dst="$1" scope="$2"
  [[ -f "$dst" ]] || return 0
  local backup="$dst.assert-iq.pre-install"
  if [[ -e "$backup" ]]; then
    return 0
  fi
  cp -p "$dst" "$backup"
  manifest_add "pre_install_backup" "$backup" "$scope"
}

# Stage-then-commit a merged JSON. If the staged content is byte-identical
# to the existing dst, discards the temp and records unchanged_owned;
# otherwise backs up (if user-owned) and atomically replaces dst, recording
# $changed_action. Centralizes the no-op short-circuit used by JSON merges.
# Args: label tmp dst scope changed_action changed_message
write_or_skip_if_unchanged() {
  local label="$1" tmp="$2" dst="$3" scope="$4" changed_action="$5" changed_msg="$6"
  local sh_merged sh_dst_now
  sh_merged="$(sha256_of "$tmp")"
  sh_dst_now="$(sha256_of "$dst")"
  if [[ -n "$sh_merged" && "$sh_merged" == "$sh_dst_now" ]]; then
    rm -f "$tmp"
    manifest_add "unchanged_owned" "$dst" "$scope"
    record "$label" "unchanged (merge no-op)" "$dst"
    return
  fi
  backup_if_user_owned "$dst" "$scope"
  mv "$tmp" "$dst"
  manifest_add "$changed_action" "$dst" "$scope"
  record "$label" "$changed_msg" "$dst"
}

declare -a MANIFEST_ENTRIES=()
# Vocabulary of actions allowed in the manifest. Validation in manifest_add
# turns silent typos into immediate errors; without this, a typo would still
# be written but downstream action-set predicates would never match.
KNOWN_MANIFEST_ACTIONS="created unchanged_owned overwritten rendered sidecar merged_settings merged_hooks_key pre_install_backup"

manifest_add() {
  # action | abs_path | scope (workspace|user)
  local action="$1" path="$2" scope="$3"
  if ! _in_action_set "$action" "$KNOWN_MANIFEST_ACTIONS"; then
    echo "ERROR: manifest_add: unknown action '$action' (typo? add it to KNOWN_MANIFEST_ACTIONS)" >&2
    exit 1
  fi
  MANIFEST_ENTRIES+=("$action|$path|$scope")
}

manifest_write() {
  # Merge with existing manifest if present (preserve older entries).
  local out_dir
  out_dir="$(dirname "$MANIFEST_PATH")"
  mkdir -p "$out_dir"
  local pack_version="unknown"
  if [[ -f "$SOURCE/VERSION" ]]; then
    pack_version="$(head -n1 "$SOURCE/VERSION" | tr -d '[:space:]')"
    [[ -n "$pack_version" ]] || pack_version="unknown"
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
    json_escape() {
      local s="$1"
      s="${s//\\/\\\\}"
      s="${s//\"/\\\"}"
      s="${s//$'\n'/\\n}"
      s="${s//$'\r'/\\r}"
      s="${s//$'\t'/\\t}"
      printf '%s' "$s"
    }
    local mtmp="$MANIFEST_PATH.tmp"
    {
      printf '{\n  "version": "%s",\n  "installed_at": "%s",\n  "mode": "%s",\n  "paths": [\n' \
        "$(json_escape "$pack_version")" "$(json_escape "$now")" "$(json_escape "$MODE")"
      local i=0 n=${#MANIFEST_ENTRIES[@]}
      for e in "${MANIFEST_ENTRIES[@]}"; do
        IFS='|' read -r a p s <<< "$e"
        i=$((i+1))
        local sep=","
        [[ $i -eq $n ]] && sep=""
        printf '    {"action": "%s", "path": "%s", "scope": "%s"}%s\n' \
          "$(json_escape "$a")" "$(json_escape "$p")" "$(json_escape "$s")" "$sep"
      done
      printf '  ]\n}\n'
    } > "$mtmp" && mv "$mtmp" "$MANIFEST_PATH"
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

# Strip the managed begin..end block from $1 in place. Sets global
# _STRIP_REMOVED=1 if a block was found, 0 otherwise. Used by both
# write_exclude_block (to clear stale block before re-append) and
# strip_exclude_block (to remove permanently).
_strip_managed_block() {
  local file="$1"
  local tmp="$file.tmp"
  if awk -v b="$EXCLUDE_BEGIN" -v e="$EXCLUDE_END" '
    BEGIN { skip=0; removed=0 }
    {
      if ($0 == b) { skip=1; removed=1; next }
      if (skip && $0 == e) { skip=0; next }
      if (!skip) print
    }
    END { exit (removed?0:1) }
  ' "$file" > "$tmp"; then
    _STRIP_REMOVED=1
  else
    _STRIP_REMOVED=0
  fi
  mv "$tmp" "$file"
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

  # Preload tracked files once — hoisting the per-entry git invocation out
  # of the loop. macOS ships bash 3.2 which has no associative arrays, so
  # we use a sorted file + grep -Fxq, which is plenty fast for our scale.
  local tracked_list
  tracked_list="$(mktemp)"
  ( cd "$WORKSPACE" && git ls-files 2>/dev/null ) > "$tracked_list" || true

  # Collect workspace-scoped manifest paths, relative to workspace root.
  # Filter out already-tracked files (we don't auto-untrack).
  local -a rels=() skipped_tracked=()
  local e a p s rel
  for e in "${MANIFEST_ENTRIES[@]}"; do
    IFS='|' read -r a p s <<< "$e"
    [[ "$s" == "workspace" ]] || continue
    _in_action_set "$a" "$EXCLUDABLE_ACTIONS" || continue
    rel="${p#"$WORKSPACE/"}"
    if grep -Fxq "$rel" "$tracked_list" 2>/dev/null; then
      skipped_tracked+=("$rel")
      continue
    fi
    rels+=("$rel")
  done

  # Always exclude the manifest itself so it doesn't leak into git status.
  local manifest_rel="${MANIFEST_PATH#"$WORKSPACE/"}"
  if ! grep -Fxq "$manifest_rel" "$tracked_list" 2>/dev/null; then
    rels+=("$manifest_rel")
  fi
  rm -f "$tracked_list"

  # Atomic block replace via shared helper, then append a fresh block.
  _strip_managed_block "$excl"
  local tmp="$excl.tmp"
  {
    cat "$excl"
    printf '%s\n' "$EXCLUDE_BEGIN"
    printf '# Managed by scripts/bootstrap.sh — do not edit by hand.\n'
    printf '# Remove with: scripts/bootstrap.sh --graduate\n'
    local r
    for r in "${rels[@]}"; do
      printf '%s\n' "$r"
    done
    printf '%s\n' "$EXCLUDE_END"
  } > "$tmp"
  mv "$tmp" "$excl"

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
  _strip_managed_block "$excl"
  if [[ "${_STRIP_REMOVED:-0}" -eq 1 ]]; then
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
# --uninstall short-circuit
# =============================================================================

uninstall_run() {
  local prefix=""
  [[ $DRY_RUN -eq 1 ]] && prefix="[dry-run] "

  echo "=== Assert.IQ uninstall ==="
  echo "Workspace: $WORKSPACE"
  echo "Manifest:  $MANIFEST_PATH"
  if [[ $UNINSTALL_USER -eq 1 ]]; then
    echo "Scope:     workspace + user-global slots"
  else
    echo "Scope:     workspace only (use --user to also remove user-global copies)"
  fi
  [[ $DRY_RUN -eq 1 ]] && echo "Mode:      DRY RUN (no files will be changed)"
  echo ""

  if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "No manifest found at $MANIFEST_PATH."
    echo "Nothing to uninstall (or this workspace was not bootstrapped)."
    exit 0
  fi

  # Confirmation prompt (skip if --yes or non-interactive).
  if [[ $DRY_RUN -eq 0 && $ASSUME_YES -eq 0 && -t 0 ]]; then
    echo "This will:"
    echo "  - delete files the bootstrap created in this workspace"
    echo "  - restore originals where the bootstrap modified your files (from .assert-iq.pre-install backups)"
    echo "  - strip the trial-mode block from .git/info/exclude (if any)"
    echo "  - clear hooks/state/, hooks/logs/, hooks/sessions/ runtime data"
    if [[ $UNINSTALL_USER -eq 1 ]]; then
      echo "  - also remove user-scope copies in ~/.assert-iq, ~/.claude, ~/Library or ~/.config prompts dir"
    fi
    echo "  - delete $MANIFEST_PATH"
    echo ""
    local ans=""
    read -r -p "Proceed? [y/N] " ans </dev/tty || ans=""
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "Aborted."; exit 1 ;;
    esac
  fi

  # Strip trial-mode exclude block first (always safe).
  strip_exclude_block || true
  echo ""

  # Walk manifest entries. Need jq to read JSON safely; fall back to a simple
  # line-by-line parse for the no-jq case.
  local removed=0 restored=0 preserved=0 skipped=0

  remove_path() {
    # Args: path (file or dir)
    local p="$1"
    if [[ ! -e "$p" && ! -L "$p" ]]; then
      skipped=$((skipped+1))
      return 0
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "${prefix}rm: $p"
      removed=$((removed+1))
      return 0
    fi
    if [[ -d "$p" && ! -L "$p" ]]; then
      rm -rf -- "$p"
    else
      rm -f -- "$p"
    fi
    removed=$((removed+1))
  }

  restore_backup() {
    # Args: backup_path
    local backup="$1"
    local original="${backup%.assert-iq.pre-install}"
    if [[ ! -f "$backup" ]]; then
      echo "${prefix}WARN: backup not found, skipping restore: $backup" >&2
      skipped=$((skipped+1))
      return 0
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "${prefix}restore: $original  (from $backup)"
      restored=$((restored+1))
      return 0
    fi
    # If user has edited the merged file post-install, save current state
    # before restoring so nothing is silently lost.
    if [[ -f "$original" ]]; then
      cp -p "$original" "$original.assert-iq.uninstall-saved" 2>/dev/null || true
    fi
    cp -p "$backup" "$original"
    rm -f -- "$backup"
    restored=$((restored+1))
  }

  process_entry() {
    # Args: action path scope
    local action="$1" path="$2" scope="$3"
    # Honor --user gate: skip user-scope entries unless requested.
    if [[ "$scope" == "user" && $UNINSTALL_USER -eq 0 ]]; then
      preserved=$((preserved+1))
      return 0
    fi
    case "$action" in
      pre_install_backup)
        restore_backup "$path"
        ;;
      created|unchanged_owned|overwritten|rendered|sidecar)
        remove_path "$path"
        ;;
      merged_settings|merged_hooks_key)
        # Restoration is handled by the corresponding pre_install_backup
        # entry. If the backup was missing (e.g. install pre-dated backup
        # support), leave the file in place so we don't destroy user data.
        if [[ -f "$path.assert-iq.pre-install" ]]; then
          # Will be restored when we hit the pre_install_backup entry.
          :
        else
          echo "preserved (no pre-install backup): $path" >&2
          preserved=$((preserved+1))
        fi
        ;;
      *)
        # Unknown action — surface to the user instead of silently skipping;
        # a manifest from a newer pack version may include actions we don't
        # know how to clean up, and orphans on disk are worse than a warning.
        echo "WARN: unknown manifest action '$action' for $path — skipping (manifest may be from a newer pack version)" >&2
        skipped=$((skipped+1))
        ;;
    esac
  }

  if command -v jq >/dev/null 2>&1; then
    # Process pre_install_backup entries FIRST so they restore originals
    # before the merged_* / overwritten entries try to clean up.
    while IFS=$'\t' read -r action path scope; do
      [[ -n "$path" ]] || continue
      process_entry "$action" "$path" "$scope"
    done < <(jq -r '.paths[] | select(.action == "pre_install_backup") | [.action, .path, .scope] | @tsv' "$MANIFEST_PATH" 2>/dev/null)

    while IFS=$'\t' read -r action path scope; do
      [[ -n "$path" ]] || continue
      [[ "$action" == "pre_install_backup" ]] && continue
      process_entry "$action" "$path" "$scope"
    done < <(jq -r '.paths[] | [.action, .path, .scope] | @tsv' "$MANIFEST_PATH" 2>/dev/null)
  else
    # Best-effort no-jq parser. Manifest is written by us, one path per line.
    local action="" path="" scope=""
    while IFS= read -r line; do
      case "$line" in
        *'"action":'*) action="$(echo "$line" | sed -E 's/.*"action": *"([^"]*)".*/\1/')" ;;
      esac
      case "$line" in
        *'"path":'*)   path="$(echo "$line" | sed -E 's/.*"path": *"([^"]*)".*/\1/')" ;;
      esac
      case "$line" in
        *'"scope":'*)  scope="$(echo "$line" | sed -E 's/.*"scope": *"([^"]*)".*/\1/')" ;;
      esac
      if [[ -n "$action" && -n "$path" && -n "$scope" ]]; then
        process_entry "$action" "$path" "$scope"
        action=""; path=""; scope=""
      fi
    done < "$MANIFEST_PATH"
  fi

  # Hooks runtime state — regenerated on next install, safe to clear.
  for d in "$WORKSPACE/hooks/state" "$WORKSPACE/hooks/logs" "$WORKSPACE/hooks/sessions"; do
    [[ -e "$d" ]] && remove_path "$d"
  done
  if [[ $UNINSTALL_USER -eq 1 ]]; then
    for d in "$HOME/.agents/hooks/state" "$HOME/.agents/hooks/logs" "$HOME/.agents/hooks/sessions"; do
      [[ -e "$d" ]] && remove_path "$d"
    done
  fi

  # Remove now-empty parent dirs (bottom-up). Safe: rmdir refuses non-empty.
  if [[ $DRY_RUN -eq 0 ]]; then
    # First, clean nested empty subdirectories left by tree-style copies
    # (.github/skills/<skill>/, eval-optimizer/references/, etc.).
    local tree
    local -a tree_roots=(
      "$WORKSPACE/.github/skills"
      "$WORKSPACE/.github/agents"
      "$WORKSPACE/.claude/agents"
      "$WORKSPACE/hooks"
    )
    if [[ $UNINSTALL_USER -eq 1 ]]; then
      tree_roots+=(
        "$USER_VSCODE_SKILLS"
        "$USER_CLAUDE_SKILLS"
        "$HOME/.agents/hooks"
        "$USER_ASSERT_IQ"
      )
    fi
    for tree in "${tree_roots[@]}"; do
      [[ -d "$tree" && ! -L "$tree" ]] && find "$tree" -depth -type d -empty -delete 2>/dev/null || true
    done
    local d
    local -a empty_dirs=(
      "$WORKSPACE/hooks"
      "$WORKSPACE/.vscode"
      "$WORKSPACE/.claude/agents"
      "$WORKSPACE/.claude/skills"
      "$WORKSPACE/.claude"
      "$WORKSPACE/.github/instructions"
      "$WORKSPACE/.github/agents"
      "$WORKSPACE/.github/skills"
      "$WORKSPACE/.github"
      "$WORKSPACE/.assert-iq"
    )
    if [[ $UNINSTALL_USER -eq 1 ]]; then
      empty_dirs+=(
        "$USER_VSCODE_SKILLS"
        "$HOME/.agents"
        "$USER_CLAUDE_SKILLS"
        "$(dirname "$USER_CLAUDE_MD")"
        "$USER_ASSERT_IQ"
      )
    fi
    for d in "${empty_dirs[@]}"; do
      [[ -d "$d" && ! -L "$d" ]] && rmdir "$d" 2>/dev/null || true
    done

    # Manifest-derived safety net: rmdir every ancestor dir of paths we just
    # removed (bottom-up, scope-gated, symlink-safe). This means future
    # additions don't have to update the hardcoded lists above — if the
    # path went into the manifest, its empty parent dirs get reaped here.
    if command -v jq >/dev/null 2>&1 && [[ -f "$MANIFEST_PATH" ]]; then
      local _p _s _d _stop
      while IFS=$'\t' read -r _p _s; do
        [[ -n "$_p" ]] || continue
        [[ "$_s" == "user" && $UNINSTALL_USER -eq 0 ]] && continue
        if [[ "$_s" == "user" ]]; then _stop="$HOME"; else _stop="$WORKSPACE"; fi
        _d="$(dirname "$_p")"
        while [[ -n "$_d" && "$_d" != "/" && "$_d" != "$_stop" ]]; do
          [[ -d "$_d" && ! -L "$_d" ]] && rmdir "$_d" 2>/dev/null || true
          _d="$(dirname "$_d")"
        done
      done < <(jq -r '.paths[] | [.path, .scope] | @tsv' "$MANIFEST_PATH" 2>/dev/null)
    fi
  fi

  # Remove the manifest last.
  if [[ $DRY_RUN -eq 0 ]]; then
    rm -f -- "$MANIFEST_PATH"
    rmdir "$(dirname "$MANIFEST_PATH")" 2>/dev/null || true
  else
    echo "${prefix}rm: $MANIFEST_PATH"
  fi

  echo ""
  echo "Summary: $removed removed, $restored restored from backup, $preserved preserved, $skipped skipped."
  if [[ $UNINSTALL_USER -eq 0 ]]; then
    # Quick check: did the manifest contain user-scope entries we left behind?
    if command -v jq >/dev/null 2>&1; then
      local user_count
      user_count="$(jq -r '[.paths[] | select(.scope == "user")] | length' "$MANIFEST_PATH" 2>/dev/null || echo 0)"
      if [[ "${user_count:-0}" -gt 0 ]]; then
        echo ""
        echo "Note: $user_count user-scope path(s) were preserved."
        echo "      Re-run with --user to also remove user-global copies."
      fi
    fi
  fi
  echo ""
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run complete. Re-run without --dry-run to apply."
  else
    echo "Uninstall complete."
  fi
}

if [[ $UNINSTALL -eq 1 ]]; then
  uninstall_run
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
    : "${SKILLS_SCOPE:=workspace}"
    ;;
  portable)
    # Skills live user-globally so every workspace can use them. The
    # workspace still receives the Assert-IQ chat agent files
    # (.github/agents/, .claude/agents/) and the install manifest so
    # uninstall stays clean; instructions, hooks, settings, MCP config,
    # and CLAUDE.md stay out. Ideal for "I want skills available in
    # every repo I open without committing the full pack".
    : "${ASSERT_IQ:=user}"
    : "${INSTRUCTIONS:=user}"
    : "${CLAUDE_MD:=user}"
    : "${COPILOT:=skip}"
    : "${AGENTS_MD:=skip}"
    : "${VSCODE:=skip}"
    : "${HOOKS:=skip}"
    : "${CLAUDE_SETTINGS:=skip}"
    : "${SKILLS_SCOPE:=user}"
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
    : "${SKILLS_SCOPE:=workspace}"
    ;;
  *)
    echo "ERROR: unknown --preset value '$PRESET' (expected: solo, pod, portable)" >&2
    exit 2
    ;;
esac

case "$SKILLS_SCOPE" in
  workspace|user|both) ;;
  *)
    echo "ERROR: invalid --skills-scope value '$SKILLS_SCOPE' (expected: workspace, user, both)" >&2
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
      backup_if_user_owned "$dst" "$scope"
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
  local f rel base
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    # Skip OS/editor cruft.
    case "$base" in
      .DS_Store|Thumbs.db|desktop.ini) continue ;;
    esac
    rel="${f#"$src_dir/"}"
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
    write_or_skip_if_unchanged "$label" "$tmp" "$dst" "$scope" \
      "merged_settings" "merged (additive, yours wins)"
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
  local lib="$SOURCE/hooks/scripts/lib/render-hooks.sh"
  [[ -f "$lib" ]] || { echo ""; return; }
  # shellcheck source=../hooks/scripts/lib/render-hooks.sh
  source "$lib"
  local tmp
  tmp="$(mktemp)"
  if ! render_hooks_template "$template" "$tmp" "$pack_root"; then
    rm -f "$tmp"
    echo ""
    return
  fi
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
    user)
      # User-global install: pack lives at $HOME/.agents/hooks/. Power users
      # who want hooks to fire across all VS Code workspaces register the
      # rendered hooks.json from their VS Code USER settings.json (printed
      # below). The wrapper exports SKILL_IMPROVE_ROOT so the scripts route
      # to ~/.agents/hooks/ regardless of which workspace VS Code opens.
      if [[ ! -d "$SOURCE/hooks" ]]; then
        record "hooks/ (user)" "missing-source" "$SOURCE/hooks"
        return
      fi
      local user_hooks="$HOME/.agents/hooks"
      if [[ -d "$SOURCE/hooks/scripts" ]]; then
        copy_tree "hooks/scripts" "$SOURCE/hooks/scripts" "$user_hooks/scripts" "user"
      fi
      if [[ -d "$SOURCE/hooks/lib" ]]; then
        copy_tree "hooks/lib" "$SOURCE/hooks/lib" "$user_hooks/lib" "user"
      fi
      if [[ -d "$SOURCE/hooks/config" ]]; then
        copy_tree "hooks/config" "$SOURCE/hooks/config" "$user_hooks/config" "user"
      fi
      if [[ -d "$SOURCE/hooks/state" ]]; then
        copy_tree "hooks/state" "$SOURCE/hooks/state" "$user_hooks/state" "user"
      fi
      if [[ -d "$SOURCE/hooks/logs" ]]; then
        copy_tree "hooks/logs" "$SOURCE/hooks/logs" "$user_hooks/logs" "user"
      fi
      mkdir -p "$user_hooks/sessions"
      manifest_add "created" "$user_hooks/sessions" "user"
      record "hooks/sessions/ (user)" "created" "$user_hooks/sessions"
      # Render hooks.json with __PACK_ROOT__ = $HOME/.agents (so $R/hooks =
      # $HOME/.agents/hooks at runtime).
      local rendered
      rendered="$(render_hooks_json "$HOME/.agents")"
      if [[ -z "$rendered" ]]; then
        record "hooks/hooks.json (user)" "missing-template" "$SOURCE/hooks/hooks.template.json"
      else
        copy_file "hooks/hooks.json" "$rendered" "$user_hooks/hooks.json" "user"
        rm -f "$rendered"
      fi
      USER_HOOKS_INSTALLED=1
      ;;
    skip) record "hooks/" "skipped (user choice)" "-" ;;
    *) echo "ERROR: invalid --hooks value '$HOOKS' (workspace|user|skip)" >&2; exit 2 ;;
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
          write_or_skip_if_unchanged ".claude/settings.json" "$tmp" "$dst" "workspace" \
            "merged_hooks_key" "merged hooks key"
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

process_github_skills() {
  # Skills can live in the workspace (.github/skills) so they ship with the
  # repo, OR user-globally in ~/.agents/skills (VS Code Copilot Chat) so they
  # work in every workspace. SKILLS_SCOPE selects which, or "both".
  if skills_scope_has_workspace; then
    copy_tree ".github/skills" "$SOURCE/.github/skills" "$WORKSPACE/.github/skills" "workspace"
  fi
  if skills_scope_has_user; then
    # The first argument is only a summary label; the real destination is
    # $USER_VSCODE_SKILLS.
    copy_tree "~/.agents/skills" "$SOURCE/.github/skills" "$USER_VSCODE_SKILLS" "user"
  fi
}

process_github_agents() {
  # Custom chat modes (e.g. Assert-IQ.agent.md) read from .github/agents.
  if [[ -d "$SOURCE/.github/agents" ]]; then
    copy_tree ".github/agents" "$SOURCE/.github/agents" "$WORKSPACE/.github/agents" "workspace"
  fi
}

process_claude_agents() {
  # Claude Code subagents must live in .claude/agents within the workspace.
  if [[ -d "$SOURCE/.claude/agents" ]]; then
    copy_tree ".claude/agents" "$SOURCE/.claude/agents" "$WORKSPACE/.claude/agents" "workspace"
  fi
}

process_claude_skills_link() {
  # Mirror install.sh: prefer a relative symlink .claude/skills -> ../.github/skills
  # so Claude Code auto-discovers the same skills Copilot uses. Falls back to a
  # recursive copy on filesystems / OSes where symlinks are unavailable.
  #
  # SKILLS_SCOPE controls placement:
  #   workspace -> only the workspace symlink (today's behavior)
  #   user      -> only ~/.claude/skills (no workspace symlink at all)
  #   both      -> workspace symlink AND ~/.claude/skills

  if skills_scope_has_user; then
    # The first argument is only a summary label; the real destination is
    # $USER_CLAUDE_SKILLS.
    copy_tree "~/.claude/skills" "$SOURCE/.github/skills" "$USER_CLAUDE_SKILLS" "user"
  fi

  if ! skills_scope_has_workspace; then
    return
  fi

  local dst="$WORKSPACE/.claude/skills"
  local target_rel="../.github/skills"
  local target_abs="$WORKSPACE/.github/skills"

  if [[ -L "$dst" ]]; then
    local current
    current="$(readlink "$dst" 2>/dev/null || echo "")"
    if [[ "$current" == "$target_rel" ]]; then
      manifest_add "unchanged_owned" "$dst" "workspace"
      record ".claude/skills" "unchanged (pack-owned symlink)" "$dst"
      return
    fi
    # User-owned symlink pointing elsewhere — write a sidecar, never overwrite.
    local side="$dst.assert-iq-new"
    rm -f "$side"
    ln -s "$target_rel" "$side" 2>/dev/null || cp -R "$target_abs" "$side"
    manifest_add "sidecar" "$side" "workspace"
    record ".claude/skills" "sidecar (existing symlink) -> .assert-iq-new" "$side"
    return
  fi

  if [[ -e "$dst" ]]; then
    local side="$dst.assert-iq-new"
    rm -rf "$side"
    ln -s "$target_rel" "$side" 2>/dev/null || cp -R "$target_abs" "$side"
    manifest_add "sidecar" "$side" "workspace"
    record ".claude/skills" "sidecar (path exists) -> .assert-iq-new" "$side"
    return
  fi

  mkdir -p "$(dirname "$dst")"
  if ln -s "$target_rel" "$dst" 2>/dev/null; then
    manifest_add "created" "$dst" "workspace"
    record ".claude/skills" "linked -> $target_rel" "$dst"
  elif [[ -d "$target_abs" ]]; then
    cp -R "$target_abs" "$dst"
    manifest_add "created" "$dst" "workspace"
    record ".claude/skills" "copied (symlink unavailable)" "$dst"
  else
    record ".claude/skills" "missing-source" "$target_abs"
  fi
}

skills_scope_has_workspace() {
  [[ "$SKILLS_SCOPE" == "workspace" || "$SKILLS_SCOPE" == "both" ]]
}

skills_scope_has_user() {
  [[ "$SKILLS_SCOPE" == "user" || "$SKILLS_SCOPE" == "both" ]]
}

process_assert_iq
process_instructions
process_claude
process_copilot
process_agents
process_vscode
process_hooks
process_claude_settings
process_github_skills
process_github_agents
process_claude_agents
process_claude_skills_link

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
echo "Skills:    $SKILLS_SCOPE"
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

if [[ "${USER_HOOKS_INSTALLED:-0}" == "1" ]]; then
  cat <<'EOF'

─── USER-GLOBAL HOOKS INSTALLED ───
Hooks are at ~/.agents/hooks/ and will fire across every VS Code workspace
once you register them in your VS Code USER settings.json.

  1. Cmd/Ctrl + Shift + P → "Preferences: Open User Settings (JSON)"
  2. Add or merge this block:

    "chat.hookFilesLocations": {
      "~/.agents/hooks/hooks.json": true
    }

  3. Reload the VS Code window.

This is one-time setup. To uninstall the user-global hooks later, run:
  scripts/bootstrap.sh --uninstall --user
───
EOF
fi

echo "Reload your editor window so the new instructions and config are picked up:"
echo "  - VS Code:    Cmd/Ctrl + Shift + P -> 'Developer: Reload Window'"
echo "  - Claude Code: restart the session"
