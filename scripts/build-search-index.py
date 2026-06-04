#!/usr/bin/env python3
"""
Build cross-page search index for the Assert.IQ HTML doc set.

For each *.html file in PAGES:
  1. Find every <h1>/<h2>/<h3>.
  2. If the heading is missing an id="…" attr, generate a stable slug from
     the heading text and inject the id (mutating the file in place).
     Slugs are deduped within a file by appending -2, -3, ...
  3. Inject the search widget markup once (between marker comments) into
     <head> and <body> if missing. Re-running is a no-op.
  4. Emit assets/search-index.js as a single
     `window.__ASSERT_IQ_SEARCH = [...]` JSON literal.

Run after editing the doc set:
    python3 scripts/build-search-index.py

Wired into scripts/make-release.sh so the index refreshes on every cut.
"""
from __future__ import annotations

import html
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ASSETS_DIR = REPO / "assets"
INDEX_JS = ASSETS_DIR / "search-index.js"

PAGES = [
    ("README.html",            "Pack overview"),
    ("README.assert-iq.html",  "Assert.IQ overview"),
    ("MCP.html",               "MCP servers"),
    ("vscode-readme.html",     "VS Code guide"),
    ("claude-readme.html",     "Claude Code guide"),
    ("hooks-readme.html",      "Hindsight Hooks"),
]

# --- markers (idempotency) ---
HEAD_OPEN  = "<!-- aiq-search:head:start -->"
HEAD_CLOSE = "<!-- aiq-search:head:end -->"
BODY_OPEN  = "<!-- aiq-search:widget:start -->"
BODY_CLOSE = "<!-- aiq-search:widget:end -->"
TAIL_OPEN  = "<!-- aiq-search:scripts:start -->"
TAIL_CLOSE = "<!-- aiq-search:scripts:end -->"

HEAD_BLOCK = f"""{HEAD_OPEN}
<link rel="stylesheet" href="assets/search.css">
{HEAD_CLOSE}"""

WIDGET_BLOCK = f"""{BODY_OPEN}
<div id="aiq-search" role="search">
  <input id="aiq-search-input" type="search" autocomplete="off" spellcheck="false"
         placeholder="Search docs (press / to focus)…" aria-label="Search documentation">
  <div id="aiq-search-results" hidden role="listbox"></div>
</div>
{BODY_CLOSE}"""

TAIL_BLOCK = f"""{TAIL_OPEN}
<script src="assets/search-index.js"></script>
<script src="assets/search.js"></script>
{TAIL_CLOSE}"""

# --- helpers ---
SLUG_NON = re.compile(r"[^a-z0-9]+")
TAG_RE   = re.compile(r"<[^>]+>")
WS_RE    = re.compile(r"\s+")
HEADING_RE = re.compile(
    r"<h([1-3])((?:\s+[^>]*)?)>(.*?)</h\1>",
    re.IGNORECASE | re.DOTALL,
)
ID_RE = re.compile(r"""\bid\s*=\s*["']([^"']+)["']""", re.IGNORECASE)


def slugify(text: str) -> str:
    s = SLUG_NON.sub("-", text.lower()).strip("-")
    return s or "section"


def text_of(html_fragment: str) -> str:
    return WS_RE.sub(" ", html.unescape(TAG_RE.sub("", html_fragment))).strip()


def ensure_block(content: str, before: str, block: str) -> str:
    """Insert block immediately before `before` if not already present."""
    if BODY_OPEN in content and before == "</body>":
        # marker already present somewhere
        pass
    if block.split("\n", 1)[0] in content:
        return content  # marker already present → idempotent
    if before not in content:
        return content
    return content.replace(before, block + "\n" + before, 1)


def process_page(path: Path, page_title_fallback: str) -> list[dict]:
    src = path.read_text(encoding="utf-8")
    used_ids: set[str] = set()
    entries: list[dict] = []

    # Capture <title>
    m = re.search(r"<title>(.*?)</title>", src, re.IGNORECASE | re.DOTALL)
    page_title = text_of(m.group(1)) if m else page_title_fallback

    # Pre-scan existing ids to seed dedupe
    for hm in HEADING_RE.finditer(src):
        attrs = hm.group(2) or ""
        idm = ID_RE.search(attrs)
        if idm:
            used_ids.add(idm.group(1))

    def repl(hm: re.Match) -> str:
        level = int(hm.group(1))
        attrs = hm.group(2) or ""
        inner = hm.group(3)
        text  = text_of(inner)
        if not text:
            return hm.group(0)

        idm = ID_RE.search(attrs)
        if idm:
            anchor = idm.group(1)
            new_attrs = attrs
        else:
            base = slugify(text)
            anchor = base
            n = 2
            while anchor in used_ids:
                anchor = f"{base}-{n}"
                n += 1
            used_ids.add(anchor)
            spacer = "" if attrs.startswith(" ") else " "
            new_attrs = f'{spacer}id="{anchor}"' + attrs

        entries.append({
            "p": path.name,
            "pt": page_title,
            "t": text,
            "a": anchor,
            "l": level,
        })
        return f"<h{level}{new_attrs}>{inner}</h{level}>"

    new_src = HEADING_RE.sub(repl, src)

    # Inject widget blocks if missing
    if HEAD_OPEN not in new_src:
        new_src = new_src.replace("</head>", HEAD_BLOCK + "\n</head>", 1)
    if BODY_OPEN not in new_src:
        # put right after <body...> open tag
        body_m = re.search(r"<body[^>]*>", new_src, re.IGNORECASE)
        if body_m:
            insert_at = body_m.end()
            new_src = new_src[:insert_at] + "\n" + WIDGET_BLOCK + new_src[insert_at:]
    if TAIL_OPEN not in new_src:
        new_src = new_src.replace("</body>", TAIL_BLOCK + "\n</body>", 1)

    if new_src != src:
        path.write_text(new_src, encoding="utf-8")

    return entries


def main() -> int:
    all_entries: list[dict] = []
    for fname, fallback in PAGES:
        p = REPO / fname
        if not p.exists():
            print(f"SKIP {fname} (not found)", file=sys.stderr)
            continue
        entries = process_page(p, fallback)
        all_entries.extend(entries)
        print(f"  {fname}: {len(entries)} headings indexed")

    ASSETS_DIR.mkdir(exist_ok=True)
    payload = json.dumps(all_entries, ensure_ascii=False, separators=(",", ":"))
    INDEX_JS.write_text(
        "// Auto-generated by scripts/build-search-index.py — do not edit.\n"
        f"window.__ASSERT_IQ_SEARCH={payload};\n",
        encoding="utf-8",
    )
    print(f"\nWrote {INDEX_JS.relative_to(REPO)} ({len(all_entries)} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
