#!/usr/bin/env python3
"""
UNIT: the generated HTML doc set under docs/html/ must be current.

WHY THIS EXISTS

docs/html/ is GENERATED from the markdown sources by
scripts/generate-documentation-html.py, and nothing verified it. It silently
rotted: by the time anyone looked it still advertised "Skills (22)" when the
pack shipped 30, said v2.0.0 when VERSION was 2.0.2, and was missing the
specialist-agents row entirely -- stale since before the 2.0.0 release.

This is the same class of problem as the generated Copilot specialist agents,
which are protected by check P5 in e2e-agent-parity.sh: a generated artifact
with no freshness check drifts from its source and nobody notices, because
everything still "passes".

HOW IT CHECKS

Regenerate into a throwaway copy of the repo and compare against the committed
output, ignoring only the timestamp line the generator stamps on every run
("Generated: <date>"), which is volatile by design. Any other difference means
someone edited a markdown source without re-running the generator.

To fix a failure:  python scripts/generate-documentation-html.py

PORTABILITY: stdlib only; resolves its own interpreter for the child run.
Run from the repo root.
"""

import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

GENERATOR = os.path.join("scripts", "generate-documentation-html.py")
OUT_DIR = os.path.join("docs", "html")
# The one line that legitimately differs on every run.
VOLATILE = re.compile(r'<div class="meta">Generated:[^<]*</div>')

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


def normalize(text):
    return VOLATILE.sub('<div class="meta">Generated: STAMP</div>', text)


def read(path):
    return io.open(path, encoding="utf-8", errors="replace").read()


print("=== UNIT: generated HTML doc set is current ===")
print("")

if not os.path.isfile(GENERATOR):
    bad("missing generator: %s" % GENERATOR)
elif not os.path.isdir(OUT_DIR):
    bad("missing generated output dir: %s" % OUT_DIR)
else:
    work = tempfile.mkdtemp(prefix="aiq-gendocs-")
    try:
        repo = os.path.join(work, "repo")
        # Copy only what the generator reads plus its output dir. Copying the
        # whole repo would drag .git and the temp fixtures other suites leave.
        shutil.copytree(".", repo, symlinks=True, ignore=shutil.ignore_patterns(
            ".git", "node_modules", "__pycache__", ".snapshots", "transcripts"))

        rc = subprocess.call([sys.executable, GENERATOR], cwd=repo,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if rc != 0:
            bad("generator exited %d when re-run (it must be runnable on this "
                "platform, from a clean tree)" % rc)
        else:
            ok("generator runs cleanly")

            committed_dir = OUT_DIR
            fresh_dir = os.path.join(repo, OUT_DIR)
            names = sorted(n for n in os.listdir(fresh_dir) if n.endswith(".html"))
            if not names:
                bad("generator produced no HTML files")

            stale = []
            missing = []
            for name in names:
                committed = os.path.join(committed_dir, name)
                if not os.path.isfile(committed):
                    missing.append(name)
                    continue
                if normalize(read(committed)) != normalize(read(os.path.join(fresh_dir, name))):
                    stale.append(name)

            if missing:
                bad("generated but not committed: %s -- run: python %s"
                    % (", ".join(missing), GENERATOR))
            if stale:
                bad("%d committed file(s) differ from a fresh generation: %s "
                    "-- a markdown source changed without re-running the "
                    "generator. Fix with: python %s"
                    % (len(stale), ", ".join(stale), GENERATOR))
            if not missing and not stale and names:
                ok("all %d generated HTML file(s) match their markdown sources" % len(names))
    finally:
        shutil.rmtree(work, ignore_errors=True)

print("")
print("=== Results: %d PASS, %d FAIL ===" % (passed, failed))
sys.exit(1 if failed else 0)
