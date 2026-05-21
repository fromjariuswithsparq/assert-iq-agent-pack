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

# ---- 3. QI Signal Aggregator MCP server (optional) ----------------------
# As of v0.2.0 the aggregator is a single static Go binary distributed via
# GitHub Releases. No Python or Go toolchain required on the target machine.
#   - Set QI_INSTALL_AGGREGATOR=0 to skip.
#   - Set QI_AGGREGATOR_VERSION=vX.Y.Z to pin (default: latest release).
AGGREGATOR_DIR="$ROOT/mcp/qi-signal-aggregator"
if [ "${QI_INSTALL_AGGREGATOR:-1}" = "1" ] && [ -d "$AGGREGATOR_DIR" ]; then
    BIN_NAME="qi-signal-aggregator"
    INSTALL_DIR="${QI_AGGREGATOR_BIN_DIR:-$HOME/.local/bin}"
    VERSION="${QI_AGGREGATOR_VERSION:-latest}"
    REPO="${QI_AGGREGATOR_REPO:-assert-iq/qi-signal-aggregator}"

    UNAME_S=$(uname -s)
    UNAME_M=$(uname -m)
    case "$UNAME_S" in
        Darwin) GO_OS=darwin ;;
        Linux)  GO_OS=linux ;;
        *)      GO_OS="" ;;
    esac
    case "$UNAME_M" in
        x86_64|amd64) GO_ARCH=amd64 ;;
        arm64|aarch64) GO_ARCH=arm64 ;;
        *)            GO_ARCH="" ;;
    esac

    if [ -z "$GO_OS" ] || [ -z "$GO_ARCH" ]; then
        say "[skip] qi-signal-aggregator: unsupported platform $UNAME_S/$UNAME_M"
    elif ! command -v curl >/dev/null 2>&1; then
        say "[skip] qi-signal-aggregator: curl not found"
    else
        ASSET="${BIN_NAME}_${GO_OS}_${GO_ARCH}.tar.gz"
        if [ "$VERSION" = "latest" ]; then
            URL_BASE="https://github.com/${REPO}/releases/latest/download"
        else
            URL_BASE="https://github.com/${REPO}/releases/download/${VERSION}"
        fi
        URL="${URL_BASE}/${ASSET}"
        SUM_URL="${URL_BASE}/checksums.txt"

        TMP=$(mktemp -d)
        trap 'rm -rf "$TMP"' EXIT
        if curl -fsSL -o "$TMP/$ASSET" "$URL" 2>/dev/null && \
           curl -fsSL -o "$TMP/checksums.txt" "$SUM_URL" 2>/dev/null; then
            # Verify SHA256 (entry in checksums.txt). Tolerate either sha256sum or shasum.
            EXPECTED=$(grep "  $ASSET$" "$TMP/checksums.txt" | awk '{print $1}')
            if [ -n "$EXPECTED" ]; then
                if command -v sha256sum >/dev/null 2>&1; then
                    ACTUAL=$(sha256sum "$TMP/$ASSET" | awk '{print $1}')
                else
                    ACTUAL=$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')
                fi
                if [ "$EXPECTED" != "$ACTUAL" ]; then
                    fail "qi-signal-aggregator: SHA256 mismatch on $ASSET (expected $EXPECTED, got $ACTUAL)"
                fi
            else
                say "[warn] qi-signal-aggregator: no checksum found for $ASSET (continuing)"
            fi

            mkdir -p "$INSTALL_DIR"
            tar -xzf "$TMP/$ASSET" -C "$TMP"
            mv "$TMP/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
            chmod +x "$INSTALL_DIR/$BIN_NAME"

            # macOS: drop quarantine so the unsigned binary runs without
            # the user being prompted to allow it from Settings.
            if [ "$GO_OS" = "darwin" ]; then
                xattr -d com.apple.quarantine "$INSTALL_DIR/$BIN_NAME" 2>/dev/null || true
            fi

            say "[ok] installed $BIN_NAME ($VERSION, $GO_OS/$GO_ARCH) -> $INSTALL_DIR"
            case ":$PATH:" in
                *":$INSTALL_DIR:"*) ;;
                *) say "     NOTE: $INSTALL_DIR is not in \$PATH. Add: export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
            esac
            say "[ok] client snippets at: $AGGREGATOR_DIR/clients/"
            say "     - VS Code / Copilot : copy clients/vscode-mcp.json -> .vscode/mcp.json"
            say "     - Claude Code       : copy clients/claude-code.json -> .mcp.json (workspace) or ~/.claude.json"
            say "     - Codex CLI         : copy clients/codex-cli.toml block -> ~/.codex/config.toml"
            say "     Try it: $BIN_NAME --config $AGGREGATOR_DIR/samples/config.yaml demo"
        else
            say "[skip] qi-signal-aggregator: could not download $URL"
            say "       Build from source: cd $AGGREGATOR_DIR && go build -o $INSTALL_DIR/$BIN_NAME ./cmd/qi-signal-aggregator"
        fi
        trap - EXIT
        rm -rf "$TMP"
    fi
fi

say ""
say "Pack installed."
say "  Copilot reads .github/copilot-instructions.md, .github/instructions/*, .github/agents/*, .github/skills/*"
say "  Claude  reads CLAUDE.md, .claude/agents/*, .claude/skills/*, .claude/settings.json (hooks)"
say "  MCP     qi-signal-aggregator (if installed): see $AGGREGATOR_DIR/README.md"
