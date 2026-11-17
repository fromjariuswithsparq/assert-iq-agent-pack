#!/usr/bin/env python3
"""
UNIT: the release record must stay internally consistent.

WHY THIS EXISTS

e2e-version-consistency.sh asserts that VERSION matches the NEWEST CHANGELOG
heading and that a version-history row exists for it. That is a real check,
but it only ever looks at the top of the file, and three separate defects
walked straight past it:

  * The ENTIRE Kiro changelog -- 304 lines, a whole harness plus four
    cross-harness fixes -- sat INSIDE the released [2.1.3] section for three
    commits, reading as though it had shipped on 2026-09-04. It landed there
    when main's [2.1.3] heading was inserted above the in-progress content
    during a merge. VERSION still matched the newest heading, so everything
    stayed green. Nothing in the suite had any opinion about content filed
    under the WRONG heading.
  * README.assert-iq.html's version-history table had no 2.3.0 row at all.
    make-release.sh promotes an `Unreleased` row to the shipping version and
    the HTML had none to promote, so the table simply stopped at 2.2.1 while
    the markdown twin moved on. E2E-17c reads the markdown table only.
  * The CHANGELOG link-reference block stopped at [2.2.1], so the 2.3.0
    heading rendered as plain text instead of a diff link. Nothing read that
    block.

The through-line: every one of these is a consistency fact ACROSS the release
record -- heading vs tag, markdown table vs HTML table, section vs link ref --
and the existing check compares a single value against a single heading.

WHAT THIS CHECKS

  C1  A released section is frozen. Its body must match the body at its own
      tag. This is the direct guard for the misfile above: content appended
      to a shipped section changes a section that shipped.
  C2  Every released section at or above MODERN_FLOOR has a [x.y.z]: link
      reference.
  C3  The markdown and HTML version-history tables agree at or above
      MODERN_FLOOR.
  C4  Every version-history row at or above MODERN_FLOOR has a CHANGELOG
      section behind it.
  C5  The newest version agrees across VERSION, the CHANGELOG, and both
      tables.
  C6  Every released section at or above MODERN_FLOOR has a git tag.

MODERN_FLOOR exists because the history below it is deliberately condensed:
the tables carry range rows like `1.3.0-1.4.x` that are not versions at all,
and not every 1.x patch earned a row. Raising the floor is a one-line
decision; loosening a check to accommodate old data is not the same thing and
should not be done in its place.

PACK CHECKOUT ONLY (exit 2 elsewhere). Everything here is about the PACK's
release record, and bootstrap.sh never copies it into a workspace -- no
CHANGELOG.md, no README.assert-iq.md, no scripts/. Worse, an installed
workspace is still a git repo, so `git tag` succeeds and returns the USER's
tags: C6 would then report every Assert.IQ version as untagged, which is a
confident lie about someone else's repository. Same detection and same
three-valued convention as e2e-agent-parity.sh -- 0 pass, 2 not applicable,
anything else fail.

NOT the job of this test: whether the prose is any good, or whether a given
release should have been major/minor/patch.

PORTABILITY: stdlib only. Forces UTF-8 stdout -- a Windows console defaults to
cp1252 and would raise UnicodeEncodeError on the em-dashes in these headings.
Run from the repo root.
"""

import io
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

CHANGELOG = "CHANGELOG.md"
TABLE_MD = "README.assert-iq.md"
TABLE_HT = "README.assert-iq.html"
VERSION_FILE = "VERSION"

# Below this, the release record is deliberately condensed -- see the module
# docstring. Raise it when old rows are cleaned up; never loosen a check to
# accommodate them.
MODERN_FLOOR = (2, 0, 0)

# Released-section headings: "## [2.3.0] — 2026-11-17". The em-dash is
# required: it is what distinguishes a RELEASED section from "## [Unreleased]".
SECTION = re.compile(r"(?m)^## \[(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\]\s+—")
LINK_REF = re.compile(r"(?m)^\[(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\]:")
ROW_MD = re.compile(r"(?m)^\|\s*\*\*([0-9][^*|]*?)\*\*\s*\|")
ROW_HT = re.compile(r"<tr><td><strong>([0-9][^<]*)</strong></td>")

passed = 0
failed = 0
notes = []


def ok(msg):
    global passed
    print("PASS %s" % msg)
    passed += 1


def bad(msg, detail=""):
    global failed
    print("FAIL %s" % msg)
    if detail:
        for line in detail.rstrip().split("\n"):
            print("       %s" % line)
    failed += 1


def key(v):
    """Sort key for a version string; None if it is not a plain x.y.z."""
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", v.strip())
    return tuple(int(x) for x in m.groups()) if m else None


def modern(versions):
    """The subset at or above MODERN_FLOOR, as a set."""
    return set(v for v in versions if key(v) and key(v) >= MODERN_FLOOR)


def read(path):
    return io.open(path, encoding="utf-8").read()


def sections(text):
    """version -> full section body, including its own heading line."""
    out = {}
    marks = list(SECTION.finditer(text))
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        out[m.group(1)] = text[m.start():end].strip()
    return out


def git(*args):
    """Run git; return stdout, or None on any failure. Never raises."""
    try:
        p = subprocess.run(["git"] + list(args), capture_output=True,
                           text=True, encoding="utf-8", errors="replace")
    except (OSError, ValueError):
        return None
    return p.stdout if p.returncode == 0 else None


def main():
    print("=== UNIT: release record integrity ===")

    # The pack checkout ships a top-level scripts/ tree; an installed
    # workspace never does. Same probe as e2e-agent-parity.sh.
    if not os.path.isdir("scripts"):
        print("")
        print("⏭️  NOT APPLICABLE — this is an installed workspace, not the "
              "pack checkout.")
        print("   The pack's release record (CHANGELOG.md, README.assert-iq.*, "
              "VERSION)")
        print("   is deliberately not copied into a workspace, and the git tags "
              "here are")
        print("   yours, not the pack's. Nothing is wrong with this checkout.")
        return 2

    for path in (CHANGELOG, TABLE_MD, TABLE_HT, VERSION_FILE):
        if not os.path.isfile(path):
            bad("required file missing from the pack checkout: %s" % path)
            print("")
            print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
            return 1


    print("   modern floor: %s" % ".".join(str(n) for n in MODERN_FLOOR))
    print("")

    changelog = read(CHANGELOG)
    secs = sections(changelog)
    sec_modern = modern(secs)

    rows_md = [v.strip() for v in ROW_MD.findall(read(TABLE_MD))]
    rows_ht = [v.strip() for v in ROW_HT.findall(read(TABLE_HT))]

    # --- C1: a released section is frozen at its tag -------------------------
    #
    # Sections written AFTER their own tag have no baseline to compare
    # against -- v2.0.0 was tagged before its section existed, and CHANGELOG.md
    # did not exist at all at v0.9.0. Those are reported as notes, not
    # failures: there is nothing to compare, which is different from a
    # mismatch. Reporting them keeps the gap visible instead of silently
    # shrinking the check's reach.
    tags = git("tag", "--list", "v*")
    if tags is None:
        notes.append("C1 NOT APPLICABLE: not a git work tree (no tags readable). "
                     "Frozen-section checking needs the tags.")
        print("SKIP C1 released sections frozen (no git tags available here)")
    else:
        have = set(t.strip().lstrip("v") for t in tags.split())
        drifted = []
        compared = 0
        for ver in sorted(secs, key=lambda v: key(v) or (0, 0, 0), reverse=True):
            if ver not in have:
                continue
            old = git("show", "v%s:%s" % (ver, CHANGELOG))
            if old is None:
                notes.append("C1 no baseline for %s: %s did not exist at tag v%s"
                             % (ver, CHANGELOG, ver))
                continue
            was = sections(old).get(ver)
            if was is None:
                notes.append("C1 no baseline for %s: the section was written after "
                             "tag v%s was cut" % (ver, ver))
                continue
            compared += 1
            if was != secs[ver]:
                drifted.append((ver, was.count("\n") + 1, secs[ver].count("\n") + 1))
        if drifted:
            detail = "\n".join(
                "[%s] changed since it shipped: %d lines at tag v%s, %d now.\n"
                "  A released section must not grow or change. If new content "
                "landed here,\n  it belongs under its own heading -- see "
                "`git diff v%s -- %s`."
                % (v, a, v, b, v, CHANGELOG) for v, a, b in drifted)
            bad("C1 released sections are frozen (%d compared)" % compared, detail)
        else:
            ok("C1 released sections are frozen (%d compared against their tags)"
               % compared)

    # --- C2: every modern section has a link reference -----------------------
    refs = modern(LINK_REF.findall(changelog))
    missing = sorted(sec_modern - refs, key=key)
    if missing:
        bad("C2 every released section has a link reference",
            "no [x.y.z]: line for %s -- the heading renders as plain text "
            "instead of a diff link." % ", ".join(missing))
    else:
        ok("C2 every released section has a link reference (%d checked)"
           % len(sec_modern))

    # --- C3: the two version-history tables agree ----------------------------
    md_modern, ht_modern = modern(rows_md), modern(rows_ht)
    only_md = sorted(md_modern - ht_modern, key=key)
    only_ht = sorted(ht_modern - md_modern, key=key)
    if only_md or only_ht:
        detail = ""
        if only_md:
            detail += ("in %s but not %s: %s\n" % (TABLE_MD, TABLE_HT, ", ".join(only_md)))
        if only_ht:
            detail += ("in %s but not %s: %s\n" % (TABLE_HT, TABLE_MD, ", ".join(only_ht)))
        detail += ("make-release.sh promotes an `Unreleased` row in BOTH files; a "
                   "missing\nrow in one of them means that file had none to promote.")
        bad("C3 version-history tables agree", detail)
    else:
        ok("C3 version-history tables agree (%d rows each at or above the floor)"
           % len(md_modern))

    # --- C4: every modern table row has a section behind it ------------------
    orphans = sorted(md_modern - sec_modern, key=key)
    if orphans:
        bad("C4 every version-history row has a CHANGELOG section",
            "rows with no `## [x.y.z] — <date>` section: %s" % ", ".join(orphans))
    else:
        ok("C4 every version-history row has a CHANGELOG section (%d checked)"
           % len(md_modern))

    # --- C5: the newest version agrees everywhere ----------------------------
    #
    # By version order, never by position: the markdown table is not sorted,
    # and reading "the last row" reports 2.1.1 as newest on this repo today.
    current = read(VERSION_FILE).strip()
    newest = {
        VERSION_FILE: current,
        CHANGELOG: max(sec_modern, key=key) if sec_modern else None,
        TABLE_MD: max(md_modern, key=key) if md_modern else None,
        TABLE_HT: max(ht_modern, key=key) if ht_modern else None,
    }
    distinct = set(v for v in newest.values() if v is not None)
    if len(distinct) != 1:
        bad("C5 newest version agrees across the release record",
            "\n".join("%-26s %s" % (k, v) for k, v in newest.items()))
    else:
        ok("C5 newest version agrees across the release record (%s)" % current)

    # --- C6: every modern section has a tag ----------------------------------
    if tags is None:
        print("SKIP C6 every released section has a tag (no git tags available here)")
    else:
        have = set(t.strip().lstrip("v") for t in tags.split())
        untagged = sorted(sec_modern - have, key=key)
        if untagged:
            bad("C6 every released section has a git tag",
                "dated in %s but never tagged: %s\nEither the release did not "
                "finish, or the section was dated too early."
                % (CHANGELOG, ", ".join(untagged)))
        else:
            ok("C6 every released section has a git tag (%d checked)" % len(sec_modern))

    if notes:
        print("")
        print("Notes (not failures):")
        for n in notes:
            print("  - %s" % n)

    print("")
    print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
