#!/usr/bin/env python3
"""
UNIT: cross-platform script portability (Windows PowerShell 5.1 + bash on
macOS/Linux/WSL).

WHY THIS EXISTS

Two encoding defects made the pack fail on Windows in ways that looked like
unrelated bugs. Both are invisible on macOS, which is where the pack was built.

1. NON-ASCII IN .ps1 WITHOUT A BOM
   Windows PowerShell 5.1 -- the only PowerShell guaranteed present on a
   Windows box -- reads a BOM-less file as the system ANSI code page, NOT as
   UTF-8. PowerShell 7+ reads it as UTF-8. So an em dash written on macOS
   (U+2014, bytes E2 80 94) arrives at 5.1 as three cp1252 characters, the
   third of which is a QUOTE:

       "... already tracked by git -- using --skip-worktree"
                                  ^ becomes  a"..."  and the string literal ends here

   scripts/bootstrap.ps1 held 43 em dashes and 9 box-drawing characters. Under
   5.1 it did not merely misprint: it failed to PARSE ("Unexpected token
   'using' in expression or statement", then cascading "Missing statement
   block" errors) and installed nothing at all, while the README advertised
   PowerShell 5.1 as a supported host.

   Rule: a shipped .ps1 must be pure ASCII, or carry a UTF-8 BOM. ASCII is
   preferred -- it survives every editor and every host.

2. CRLF IN .sh
   With Git's Windows default core.autocrlf=true and no .gitattributes, every
   shell script in a Windows clone gets CRLF. Git Bash tolerates it; bash on
   Linux, WSL, and macOS does not ("$'\\r': command not found", or
   "/usr/bin/env: 'bash\\r': No such file or directory"). The pack documents a
   macOS/Linux/WSL bash path, so the checkout must be LF regardless of the
   user's autocrlf setting. That is what .gitattributes pins.

PORTABILITY: stdlib only. Run from the repo root.
"""

import io
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BOM = b"\xef\xbb\xbf"
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".snapshots"}

passed = 0
failed = 0


def ok(m):
    global passed
    print("PASS " + m)
    passed += 1


def bad(m):
    global failed
    print("FAIL " + m)
    failed += 1


def walk(ext):
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name.endswith(ext):
                # relpath, not lstrip("./") -- lstrip is a character set and
                # would eat the leading dot of ".assert-iq".
                yield os.path.relpath(os.path.join(root, name), ".").replace(os.sep, "/")


def describe_non_ascii(data):
    """Report the distinct offending characters and the first line each is on."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return ["file is not valid UTF-8 either"]
    seen = {}
    for lineno, line in enumerate(text.splitlines(), 1):
        for ch in line:
            if ord(ch) > 127 and ch not in seen:
                seen[ch] = lineno
    return ["U+%04X %r first on line %d" % (ord(c), c, ln)
            for c, ln in sorted(seen.items(), key=lambda kv: kv[1])]


print("=== UNIT: cross-platform script portability ===")
print("")

# ---- 1. PowerShell files must be ASCII-only or BOM-marked ------------------
ps1_files = sorted(walk(".ps1"))
if not ps1_files:
    bad("no .ps1 files found -- is this being run from the repo root?")
else:
    offenders = []
    for path in ps1_files:
        data = io.open(path, "rb").read()
        if data.startswith(BOM):
            continue  # explicit UTF-8: 5.1 honours the BOM
        if any(b > 0x7F for b in bytearray(data)):
            offenders.append((path, describe_non_ascii(data)))
    if offenders:
        for path, chars in offenders:
            bad("%s: non-ASCII with no UTF-8 BOM -- Windows PowerShell 5.1 will "
                "read these as cp1252 and can fail to PARSE the file: %s"
                % (path, "; ".join(chars)))
    else:
        ok("all %d .ps1 files are ASCII-only or BOM-marked (safe under "
           "Windows PowerShell 5.1)" % len(ps1_files))

# ---- 1b. shipped .ps1 must not write UTF-8 with a BOM ---------------------
# `Set-Content/Add-Content/Out-File -Encoding UTF8` means UTF-8 WITH a BOM on
# Windows PowerShell 5.1, and WITHOUT one on PowerShell 7. The pack's Python
# tooling reads JSON with encoding="utf-8", which rejects a BOM, so on a stock
# Windows box the dream state, verdict archive, install manifest and
# .claude/settings.json written by PowerShell became unparseable to
# calibration.py, memory-sanity.py, the verdict recorder and dreaming_service.py
# -- with json.JSONDecodeError "Expecting value: line 1 column 1" as the only
# clue. `-Encoding utf8NoBOM` would fix it but exists only in PowerShell 6+, so
# the pack writes through .NET UTF8Encoding($false) instead (Write-AiqUtf8).
SHIPPED_PS1_PREFIXES = ("install.ps1", "scripts/", ".assert-iq/")
bom_writers = []
for path in ps1_files:
    if not any(path.startswith(pre) for pre in SHIPPED_PS1_PREFIXES):
        continue  # test drivers may write however they like
    for lineno, line in enumerate(
            io.open(path, encoding="utf-8", errors="replace").read().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if ("-Encoding UTF8" in line or "-Encoding utf8" in line) and any(
                w in line for w in ("Set-Content", "Add-Content", "Out-File")):
            bom_writers.append("%s:%d" % (path, lineno))
if bom_writers:
    bad("shipped PowerShell writes UTF-8 with a BOM under Windows PowerShell 5.1 "
        "(use Write-AiqUtf8): %s" % ", ".join(bom_writers))
else:
    ok("no shipped .ps1 writes a BOM (Python JSON readers stay parseable on 5.1)")

# ---- 1c. `set -e` + top-level ((VAR++)) silently truncates a script -------
# Under `set -e`, an arithmetic command's exit status is the FALSEness of its
# value, and `((VAR++))` evaluates to the PRE-increment value. So the FIRST
# 0 -> 1 increment returns 0, i.e. exit status 1, and `set -e` kills the script
# on the spot -- right after its first successful check.
#
# scripts/validate-documentation-integrity.sh ran 1 of its 10 checks and exited
# 1 on every platform because of this, and two test suites earlier in the pack's
# history reported almost nothing for the same reason. Use VAR=$((VAR+1)).
#
# Increments INSIDE a function are fine when the function is invoked in a
# conditional context (`f || true`, `if f; then`), because `set -e` is suspended
# for the whole function body there -- which is how five integration suites in
# this pack legitimately use `((PASSED++))`. So only TOP-LEVEL increments are
# flagged, tracked by the repo's convention that a function body ends with `}`
# in column 1.
import re as _re2

SET_E_RE = _re2.compile(r"^\s*set\s+-[a-zA-Z]*e")
INCR_RE = _re2.compile(r"\(\(\s*[A-Za-z_][A-Za-z0-9_]*\s*\+\+\s*\)\)")
FUNC_OPEN_RE = _re2.compile(r"^\s*(function\s+)?[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{")

set_e_offenders = []
for path in sorted(walk(".sh")):
    lines = io.open(path, encoding="utf-8", errors="replace").read().splitlines()
    has_set_e = False
    in_func = False
    flagged = []
    for lineno, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        code = line.split("#", 1)[0]
        if FUNC_OPEN_RE.match(code):
            in_func = True
        elif in_func and code.rstrip() == "}":
            in_func = False
        if SET_E_RE.match(code):
            has_set_e = True
        if has_set_e and not in_func and INCR_RE.search(code):
            flagged.append(lineno)
    if flagged:
        set_e_offenders.append((path, flagged))

if set_e_offenders:
    for path, flagged in set_e_offenders:
        bad("%s: `set -e` with top-level ((VAR++)) at line(s) %s -- the first "
            "increment returns 0, so the script dies right after its first "
            "successful check. Use VAR=$((VAR+1))."
            % (path, ", ".join(str(n) for n in flagged[:6])))
else:
    ok("no `set -e` script uses a top-level ((VAR++)) (silent-truncation guard)")

# ---- 2. .gitattributes must pin shell scripts to LF -----------------------
if not os.path.isfile(".gitattributes"):
    bad(".gitattributes is missing -- with Git's Windows default "
        "core.autocrlf=true every .sh in a Windows clone becomes CRLF, which "
        "bash on macOS/Linux/WSL refuses to run")
else:
    attrs = io.open(".gitattributes", encoding="utf-8", errors="replace").read()
    lines = [ln.strip() for ln in attrs.splitlines()
             if ln.strip() and not ln.strip().startswith("#")]

    def pins(pattern, want_eol):
        for ln in lines:
            parts = ln.split()
            if parts and parts[0] == pattern and ("eol=" + want_eol) in parts:
                return True
        return False

    for pattern, want in (("*.sh", "lf"), ("*.py", "lf")):
        if pins(pattern, want):
            ok(".gitattributes pins %s to eol=%s" % (pattern, want))
        else:
            bad(".gitattributes does not pin %s to eol=%s -- a Windows clone "
                "will hand bash a CRLF script" % (pattern, want))

# ---- 3. Shell scripts need a shebang --------------------------------------
sh_files = sorted(walk(".sh"))
if not sh_files:
    bad("no .sh files found -- is this being run from the repo root?")
else:
    missing = [p for p in sh_files
               if not io.open(p, "rb").readline().startswith(b"#!")]
    if missing:
        for p in missing:
            bad("%s: no shebang" % p)
    else:
        ok("all %d .sh files start with a shebang" % len(sh_files))

# ---- 4. What git will hand a fresh clone ----------------------------------
# Assert the INDEX, not the working tree. On Windows with core.autocrlf=true an
# existing checkout legitimately holds CRLF copies; what matters is that the
# committed blob is LF and the attribute forces LF on checkout, so a fresh
# clone -- on any platform -- gets a runnable script. Checking the worktree here
# would fail on every Windows dev box while the repo itself was correct.
import subprocess

try:
    out = subprocess.check_output(
        ["git", "ls-files", "--eol", "--", "*.sh", "*.py"],
        stderr=subprocess.STDOUT).decode("utf-8", "replace")
except Exception as e:
    print("SKIP git ls-files --eol unavailable (%s); index EOL not verified"
          % type(e).__name__)
    out = None

if out is not None:
    wrong_index, wrong_attr, worktree_drift = [], [], []
    for line in out.splitlines():
        if "\t" not in line:
            continue
        flags, path = line.split("\t", 1)
        path = path.strip()
        parts = flags.split()
        idx = next((p for p in parts if p.startswith("i/")), "")
        wtr = next((p for p in parts if p.startswith("w/")), "")
        if idx not in ("i/lf", "i/none"):
            wrong_index.append("%s (%s)" % (path, idx))
        if "eol=lf" not in flags:
            wrong_attr.append(path)
        if wtr == "w/crlf":
            worktree_drift.append(path)

    if wrong_index:
        bad("committed as CRLF, so even a Linux/macOS clone gets an unrunnable "
            "script: %s" % ", ".join(wrong_index[:5]))
    else:
        ok("every tracked .sh/.py is stored LF in the index")

    if wrong_attr:
        bad("%d tracked .sh/.py file(s) are not covered by an eol=lf attribute "
            "(e.g. %s) -- a Windows clone will convert them to CRLF"
            % (len(wrong_attr), wrong_attr[0]))
    else:
        ok("every tracked .sh/.py resolves to eol=lf via .gitattributes")

    if worktree_drift:
        # Informational: this checkout predates .gitattributes. Not a repo fault.
        print("NOTE %d file(s) in THIS working tree are still CRLF (checked out "
              "before .gitattributes existed). A fresh clone is correct; to fix "
              "this copy: git add --renormalize . && git checkout -- ."
              % len(worktree_drift))

print("")
print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
sys.exit(1 if failed else 0)
