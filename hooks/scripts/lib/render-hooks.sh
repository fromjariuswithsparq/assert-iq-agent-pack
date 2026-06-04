#!/usr/bin/env bash
# Shared helper: render hooks.template.json with __PACK_ROOT__ substituted
# for an absolute path. Sourced by install.sh and scripts/bootstrap.sh so
# the substitution logic stays in one place.
#
# Usage:
#   source hooks/scripts/lib/render-hooks.sh
#   sed_escape_replacement "$some_path"          # prints escaped string
#   render_hooks_template <template> <out> <pack_root>

# Escape a string so it is safe to use as the replacement side of a sed
# `s|...|REPL|` command. Handles backslash, ampersand, and the `|` delimiter.
sed_escape_replacement() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//&/\\&}
  s=${s//|/\\|}
  printf '%s' "$s"
}

# Render template -> out, replacing __PACK_ROOT__ with pack_root.
# Returns non-zero if template is missing or sed fails.
render_hooks_template() {
  local template="$1" out="$2" pack_root="$3"
  [[ -f "$template" ]] || return 1
  local escaped
  escaped="$(sed_escape_replacement "$pack_root")"
  sed "s|__PACK_ROOT__|$escaped|g" "$template" > "$out"
}
