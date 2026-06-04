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
#   3. Commits "Release v<version>" if VERSION changed.
#   4. Creates annotated tag v<version>.
#   5. Pushes main + tag.
#   6. Creates a GitHub Release whose body is the CHANGELOG section for
#      that version (extracted between "## [<v>]" and the next "## [").

set -euo pipefail

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

if ! git diff --quiet -- VERSION CHANGELOG.md 2>/dev/null; then
  echo ">> Committing release bump"
  git add VERSION CHANGELOG.md
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
