#!/usr/bin/env python3
"""
UNIT: Markdown / HTML documentation parity.

WHY THIS EXISTS

The pack ships every user-facing doc twice: a markdown source and a
hand-authored HTML sister for GitHub Pages / offline distribution. The CHANGELOG
calls this an "HTML/MD parity rule", but nothing enforced it and the two copies
had drifted:

  * README.assert-iq.md said "Skills (22)" while its HTML twin said "Skills (26)"
    and the repo actually shipped 30.
  * The HTML twin was missing the whole "Calibration & Reproducibility" section
    (including "The Moat"), the core commercial argument of the pack.
  * README.assert-iq.md was missing the "Multi-agent orchestration" section that
    the HTML had.
  * Four Installation topics sat at h4 in HTML but "###" in markdown. Because
    build-search-index.py indexes h1-h3 only, those sections were invisible to
    the site search.
  * MCP.html had dropped the "The 20 servers" parent and promoted all 8
    categories to h2.
  * dreaming-readme.html numbered its sections ("1. The two loops") while the
    markdown did not, so every title disagreed.

This test compares heading trees (text AND depth) for each pair. Divergence that
is deliberate must be declared in ACCEPTED below with a reason, never silenced by
loosening the comparison.

PORTABILITY: stdlib only. Forces UTF-8 stdout because a Windows console defaults
to cp1252 and would raise UnicodeEncodeError on the em-dashes in these headings.
Run from the repo root.
"""

import io
import os
import re
import sys
import html as H

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PAIRS = [
    ("README.md",                     "README.html"),
    ("README.assert-iq.md",           "README.assert-iq.html"),
    (".claude/claude-readme.md",      "claude-readme.html"),
    (".github/vscode-readme.md",      "vscode-readme.html"),
    (".vscode/MCP.md",                "MCP.html"),
    (".assert-iq/dreaming/README.md", "dreaming-readme.html"),
    ("ORACLE_QUICK_START.md",         "oracles-readme.html"),
]

# Declared, deliberate divergences. Anything NOT listed here fails.
#
# README.md is the repository front page; README.html is the GitHub Pages landing
# page. They deliberately differ in information architecture: the landing page
# presents feature "cards" as h4 and delegates depth to the dedicated pages
# (oracles-readme.html, README.assert-iq.html) rather than duplicating 70+ lines
# of prose that would then need syncing in two places.
ACCEPTED = {
    ("README.md", "README.html"): {
        "reason": "repo front page vs GitHub Pages landing page: the landing page "
                  "uses h4 feature cards and links out for depth instead of "
                  "duplicating the deep sections.",
        "md_only": [
            "Decision Confidence Calibration — Proving Your QI Verdicts (v1.7.0+)",
            "Oracle Layer — Defensible Quality Verification (v1.6.0+)",
            # Procedure for trying an unreleased branch. Belongs with the
            # install steps in the repo front page, and is exactly the kind of
            # install depth the landing page delegates rather than duplicates.
            "Testing an unreleased branch",
        ],
        "html_only": [
            "Change Risk", "Protection Strength", "Signal Trustworthiness",
            "Outcome Evidence", "The immediate impact",
            "30 Skills", "Multi-Agent Orchestration (v2.0)",
            "Business Impact Dashboards (v2.0)", "Oracle Layer", "Maturity-Aware",
            "20 MCP Servers", "Dreaming", "Decision Confidence Calibration",
            "Pick your workspace topology",
        ],
    },
}

EMPH2 = re.compile(r"\*\*(.+?)\*\*")
EMPH1 = re.compile(r"(?<![A-Za-z0-9])[*_](.+?)[*_](?![A-Za-z0-9])")
MD_H = re.compile(r"^(#{2,4})\s+(.*?)\s*$")
HTML_H = re.compile(r"<h([234])\b[^>]*>(.*?)</h\1>", re.S)


def norm(s):
    # Strip inline tags, unescape entities, drop code backticks, and remove
    # markdown emphasis markers: the md writes **not** where the html writes
    # <strong>not</strong>, and without this the same heading compares as
    # different. That produced two false divergences when first written.
    s = re.sub(r"<[^>]+>", "", s)
    s = H.unescape(s).replace("`", "")
    s = EMPH2.sub(lambda m: m.group(1), s)
    s = EMPH1.sub(lambda m: m.group(1), s)
    return re.sub(r"\s+", " ", s).strip().rstrip("¶").strip()


def md_headings(path):
    out, fence = [], False
    for line in io.open(path, encoding="utf-8").read().split("\n"):
        if line.startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        m = MD_H.match(line)
        if m:
            out.append((len(m.group(1)), norm(m.group(2))))
    return out


def html_headings(path):
    src = io.open(path, encoding="utf-8").read()
    return [(int(m.group(1)), norm(m.group(2))) for m in HTML_H.finditer(src)]


def main():
    passed = failed = 0
    print("=== UNIT: Markdown / HTML documentation parity ===")
    print("")

    for md, ht in PAIRS:
        label = "%s <-> %s" % (md, ht)
        if not os.path.isfile(md) or not os.path.isfile(ht):
            print("FAIL %s: missing file" % label)
            failed += 1
            continue

        a, b = md_headings(md), html_headings(ht)
        depth_md = {t: l for l, t in a}
        depth_ht = {t: l for l, t in b}

        allow = ACCEPTED.get((md, ht), {})
        allow_md = set(allow.get("md_only", []))
        allow_ht = set(allow.get("html_only", []))

        mismatch = [(t, depth_md[t], depth_ht[t]) for t in depth_md
                    if t in depth_ht and depth_md[t] != depth_ht[t]]
        md_only = [t for _, t in a if t not in depth_ht and t not in allow_md]
        ht_only = [t for _, t in b if t not in depth_md and t not in allow_ht]
        # A declared exception that is no longer divergent is also drift: the
        # docs converged and the waiver should be deleted.
        stale = ([t for t in allow_md if t in depth_ht or t not in depth_md] +
                 [t for t in allow_ht if t in depth_md or t not in depth_ht])

        if not (mismatch or md_only or ht_only or stale):
            extra = ""
            if allow:
                extra = " (%d declared exception(s))" % (len(allow_md) + len(allow_ht))
            print("PASS %s: heading trees agree%s" % (label, extra))
            passed += 1
            continue

        print("FAIL %s: heading trees diverge" % label)
        for t, lm, lh in mismatch:
            print("       depth: %-42s md=h%d html=h%d" % (t[:42], lm, lh))
        for t in md_only:
            print("       only in md:   %s" % t)
        for t in ht_only:
            print("       only in html: %s" % t)
        for t in stale:
            print("       stale exception (no longer divergent, remove it): %s" % t)
        failed += 1

    print("")
    print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
    if failed:
        print("")
        print("Fix by editing the markdown and its HTML sister so the headings")
        print("match, or -- if the difference is deliberate -- add it to ACCEPTED")
        print("in this file WITH a reason. Note build-search-index.py indexes")
        print("h1-h3 only, so a section demoted to h4 in HTML silently drops out")
        print("of the site search.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
