#!/usr/bin/env python3
"""Unit tests for memory sanity checker.

Two things make this file non-obvious:

1. The module under test is `.assert-iq/analysis/memory-sanity.py`. A hyphen is
   not a legal Python identifier, so `import memory_sanity` can never resolve
   it. It is loaded by file path via importlib — the same pattern the pack
   documents in `.assert-iq/SKILL_VERDICT_QUICKSTART.md` for
   `verdict-recorder.py`.

2. Every detector takes `Dict[str, Path]` and `open()`s the values. Passing
   raw content strings makes each one raise OSError internally, which the
   detectors swallow via `except IOError: pass` — so they silently return
   empty results and the assertions never exercise real logic. These tests
   therefore write real topic files into a temp directory.
"""

import sys
import importlib.util
import tempfile
from pathlib import Path
from typing import Dict

# Windows consoles default to cp1252, which cannot encode the ✅/❌ markers
# below; force UTF-8 so a failing assertion reports the assertion rather than
# a UnicodeEncodeError.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# This file lives at .assert-iq/tests/_qi/automated/, so .assert-iq/analysis/
# is four parents up (automated -> _qi -> tests -> .assert-iq).
ANALYSIS_DIR = Path(__file__).resolve().parent.parent.parent.parent / "analysis"
MODULE_PATH = ANALYSIS_DIR / "memory-sanity.py"


def _load_memory_sanity():
    """Load the hyphenated module by path (importable name is impossible)."""
    if not MODULE_PATH.is_file():
        raise FileNotFoundError(f"module under test not found: {MODULE_PATH}")
    spec = importlib.util.spec_from_file_location("memory_sanity", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


memory_sanity = _load_memory_sanity()


def write_topics(tmpdir: str, topics: Dict[str, str]) -> Dict[str, Path]:
    """Materialize {name: content} as real .md files, returning {name: Path}.

    The detectors expect the mapping produced by find_topics(), i.e. topic
    stem -> file path.
    """
    written = {}
    for name, content in topics.items():
        path = Path(tmpdir) / f"{name}.md"
        path.write_text(content, encoding="utf-8")
        written[name] = path
    return written


def test_cycle_detection_simple():
    """Test cycle detection with simple A->B->A cycle."""
    with tempfile.TemporaryDirectory() as tmp:
        topics = write_topics(tmp, {
            "topic-a": "Content with [[topic-b]]",
            "topic-b": "Content with [[topic-a]]",
        })
        cycles = memory_sanity.detect_cycles(topics)
        assert len(cycles) > 0, "Should detect A->B->A cycle"
    print("✅ Test 1: Simple cycle detection (A->B->A)")
    return True


def test_cycle_detection_no_cycle():
    """Test cycle detection with no cycles."""
    with tempfile.TemporaryDirectory() as tmp:
        topics = write_topics(tmp, {
            "topic-a": "Content with [[topic-b]]",
            "topic-b": "Content (no refs)",
        })
        cycles = memory_sanity.detect_cycles(topics)
        assert len(cycles) == 0, f"Should not detect cycles when none exist, got {cycles}"
    print("✅ Test 2: No false positives on acyclic graph")
    return True


def test_staleness_detection():
    """Test fact staleness checking.

    detect_staleness only inspects lines that begin with '-' or '*', so the
    fixture facts must be bullets.
    """
    with tempfile.TemporaryDirectory() as tmp:
        topics = write_topics(tmp, {
            "topic-a": "- Updated 2024-01-01: this fact is stale.\n",
            "topic-b": "- Updated 2026-08-10: this fact is recent.\n",
        })
        stale_facts = memory_sanity.detect_staleness(topics, threshold_days=180)
        assert len(stale_facts) > 0, "Should detect stale facts"
        assert "topic-a" in stale_facts, f"Expected topic-a flagged, got {dict(stale_facts)}"
        assert "topic-b" not in stale_facts, "Recent fact must not be flagged as stale"
    print("✅ Test 3: Staleness detection (>180 days)")
    return True


def test_contradiction_detection():
    """Test contradiction detection.

    detect_contradictions does a case-sensitive substring match for the exact
    strings 'critical' and 'low priority', so the fixture must use the spaced
    form (not 'low-priority').
    """
    with tempfile.TemporaryDirectory() as tmp:
        topics = write_topics(tmp, {
            "topic-critical": "Service X is critical to operations.",
            "topic-secondary": "Service X is low priority for this quarter.",
        })
        contradictions = memory_sanity.detect_contradictions(topics)
        assert len(contradictions) > 0, "Should detect contradictions"
    print("✅ Test 4: Contradiction detection")
    return True


def test_granularity_no_issues():
    """Test granularity check on good content."""
    with tempfile.TemporaryDirectory() as tmp:
        topics = write_topics(tmp, {
            "topic-a": "This is synthesized content about a pattern we observed.\n",
        })
        issues = memory_sanity.detect_granularity_issues(topics)
        assert len(issues) == 0, f"Should not flag synthesized content, got {dict(issues)}"
    print("✅ Test 5: Granularity check (no false positives)")
    return True


def test_granularity_flags_copy_paste():
    """Copy-paste indicators (very long lines, block quotes) must be flagged.

    Without this, test 5 alone would pass even if the detector never flagged
    anything at all.
    """
    with tempfile.TemporaryDirectory() as tmp:
        topics = write_topics(tmp, {
            "topic-dump": "x" * 600 + "\n",
            "topic-quote": "> pasted transcript line\n",
        })
        issues = memory_sanity.detect_granularity_issues(topics)
        assert "topic-dump" in issues, "Should flag >500-char line as copy-paste"
        assert "topic-quote" in issues, "Should flag block quote"
    print("✅ Test 6: Granularity check flags copy-paste and block quotes")
    return True


if __name__ == "__main__":
    tests = [
        test_cycle_detection_simple,
        test_cycle_detection_no_cycle,
        test_staleness_detection,
        test_contradiction_detection,
        test_granularity_no_issues,
        test_granularity_flags_copy_paste,
    ]

    passed = 0
    failed = 0

    print("=== Memory Sanity Unit Tests ===")
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"❌ {test.__name__} FAILED: {type(e).__name__}: {e}")
            failed += 1

    print(f"\nResults: {passed} PASS, {failed} FAIL")
    sys.exit(0 if failed == 0 else 1)
