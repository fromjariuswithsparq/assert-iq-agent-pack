#!/usr/bin/env bash
# Cut a release of the Assert.IQ Agent Pack.
#
# Usage:   scripts/make-release.sh <version> [--draft] [--prerelease]
# Example: scripts/make-release.sh 1.1.0
#
# Preconditions:
#   - clean working tree on main (or override with ALLOW_DIRTY=1)
#   - CHANGELOG.md has a "## [<version>] — YYYY-MM-DD" section
#   - gh CLI authenticated (`gh auth status`)
#
# What it does:
#   1. Sanity-checks branch, working tree, version format, CHANGELOG section.
#   2. Writes <version> to VERSION.
#   3. Bumps current-version banners across the README / docs family
#      (README.md, MANIFEST.md, README.assert-iq.md, and every *.html
#      sibling). Anchored regexes only touch the "this is the current
#      version" banner sites; CHANGELOG entries, [n.n.n] link refs, and
#      version-history table rows are left untouched.
#   4. Commits "Release v<version>" if VERSION or any banner changed.
#   5. Creates annotated tag v<version>.
#   6. Pushes main + tag.
#   7. Creates a GitHub Release whose body is the CHANGELOG section for
#      that version (extracted between "## [<v>]" and the next "## [").

set -euo pipefail

# Bump every "current version" banner across the doc set in-place.
# Anchored on the surrounding text so version-history rows and CHANGELOG
# link refs are not rewritten.
bump_doc_banners() {
  local new="$1"
  local files=(
    "README.md"
    "MANIFEST.md"
    "README.assert-iq.md"
    "README.assert-iq.html"
    "README.html"
    "claude-readme.html"
    "vscode-readme.html"
    "hooks-readme.html"
    "MCP.html"
  )
  local v='v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?'
  local f tmp
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    tmp="$(mktemp)"
    sed -E \
      -e "s|(\\*\\*)$v(\\*\\* · \\[Full documentation)|\\1v$new\\3|" \
      -e "s|(\\*\\*Version\\*\\*: )$v|\\1v$new|" \
      -e "s|(<span class=\"sidebar-version\">)$v(</span>)|\\1v$new\\3|" \
      -e "s|(<strong>Version:</strong> )$v|\\1v$new|" \
      -e "s|(Pack · )$v( · Owned)|\\1v$new\\3|g" \
      -e "s|(<span class=\"badge-dot\"></span>)$v( · Internal)|\\1v$new\\3|" \
      -e "s|(git checkout )$v|\\1v$new|g" \
      -e "s|(git clone --branch )$v|\\1v$new|g" \
      "$f" > "$tmp"
    if ! cmp -s "$f" "$tmp"; then
      mv "$tmp" "$f"
      echo "  bumped $f"
    else
      rm -f "$tmp"
    fi
  done
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-}"
shift || true
DRAFT=0
PRERELEASE=0
for arg in "$@"; do
  case "$arg" in
    --draft)      DRAFT=1 ;;
    --prerelease) PRERELEASE=1 ;;
    *) echo "ERROR: unknown flag '$arg'" >&2; exit 2 ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Usage: scripts/make-release.sh <version> [--draft] [--prerelease]" >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "ERROR: version '$VERSION' is not semver (X.Y.Z or X.Y.Z-suffix)" >&2
  exit 2
fi
TAG="v$VERSION"

# Branch + working tree
branch="$(git symbolic-ref --short HEAD)"
if [[ "$branch" != "main" ]]; then
  echo "ERROR: must release from main (current: $branch)" >&2
  exit 1
fi
if [[ -z "${ALLOW_DIRTY:-}" ]] && ! git diff --quiet HEAD --; then
  echo "ERROR: working tree is dirty. Commit or stash, or set ALLOW_DIRTY=1." >&2
  git status --short
  exit 1
fi

# Tag must not already exist
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "ERROR: tag $TAG already exists" >&2
  exit 1
fi

# CHANGELOG section must exist
if ! grep -q "^## \[$VERSION\] " CHANGELOG.md; then
  echo "ERROR: CHANGELOG.md has no '## [$VERSION] — ...' section" >&2
  exit 1
fi

# Extract release notes for this version
notes_file="$(mktemp)"
trap 'rm -f "$notes_file"' EXIT
awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" {flag=1; next}
  /^## \[/ {flag=0}
  flag {print}
' CHANGELOG.md > "$notes_file"
if [[ ! -s "$notes_file" ]]; then
  echo "ERROR: extracted release notes are empty" >&2
  exit 1
fi

# gh auth
gh auth status >/dev/null 2>&1 || {
  echo "ERROR: gh CLI not authenticated. Run: gh auth login" >&2
  exit 1
}

echo ">> Writing VERSION = $VERSION"
echo "$VERSION" > VERSION

echo ">> Bumping doc banners"
bump_doc_banners "$VERSION"

if ! git diff --quiet -- VERSION CHANGELOG.md README.md MANIFEST.md README.assert-iq.md README.assert-iq.html README.html claude-readme.html vscode-readme.html hooks-readme.html MCP.html 2>/dev/null; then
  echo ">> Committing release bump"
  git add VERSION CHANGELOG.md README.md MANIFEST.md README.assert-iq.md README.assert-iq.html README.html claude-readme.html vscode-readme.html hooks-readme.html MCP.html
  git commit -m "Release $TAG"
fi

echo ">> Creating annotated tag $TAG"
git tag -a "$TAG" -F "$notes_file"

echo ">> Pushing main + $TAG"
git push origin main
git push origin "$TAG"

echo ">> Creating GitHub Release"
gh_args=(release create "$TAG" --title "$TAG" --notes-file "$notes_file")
if [[ $DRAFT -eq 1 ]];      then gh_args+=(--draft); fi
if [[ $PRERELEASE -eq 1 ]]; then gh_args+=(--prerelease); else gh_args+=(--latest); fi
gh "${gh_args[@]}"

echo ""
echo "✓ Released $TAG"
gh release view "$TAG" --json url --jq .url
