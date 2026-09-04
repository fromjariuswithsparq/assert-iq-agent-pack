#!/usr/bin/env python3
"""The pre/post-dream safety procedure must actually run.

qi-foundation.instructions.md > Memory Poisoning Prevention promises four
things around /dream: sanity checks, a memory snapshot, an append-only
provenance record, and a post-dream regression check. For most of the pack's
life none of them were wired to anything -- and integration-dream-provenance.sh
passed the whole time, because it only asserted that provenance.json existed
and parsed.

The most load-bearing assertion here is test 3: restoring a snapshot must
reproduce the exact memory_version recorded for that cycle. That is step 1 of
the reproducibility contract, and it could never have worked before, since no
snapshot was ever written.
"""

import json
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

# Windows consoles default to cp1252 and cannot encode the markers below.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ASSERT_IQ = Path(__file__).resolve().parent.parent.parent.parent
SAFETY = ASSERT_IQ / "analysis" / "dream-safety.py"

CONFIG = """maturity:
  tier: "{tier}"

dreaming:
  enabled: true
  memory_dir: ".assert-iq/memory"

dreaming_provenance:
  enabled: true
  snapshot_retention: {retention}
  snapshot_path: ".assert-iq/dreaming/.snapshots"

memory_sanity:
  enabled: true

regression_testing:
  enabled: {reg_enabled}
  golden_corpus_path: ".assert-iq/tests/_qi/regression/golden-corpus.jsonl"
  block_dream_on_regression: {block}
  max_verdict_divergence_pct: 5
"""


def make_workspace(tier="early", retention=10, reg_enabled="false", block="false",
                   poisoned=False):
    """A minimal workspace: config + memory store + dreaming dir."""
    root = Path(tempfile.mkdtemp()) / "ws"
    (root / ".assert-iq" / "memory" / "topics").mkdir(parents=True)
    (root / ".assert-iq" / "dreaming").mkdir(parents=True)
    (root / ".assert-iq" / "config.yaml").write_text(
        CONFIG.format(tier=tier, retention=retention, reg_enabled=reg_enabled, block=block),
        encoding="utf-8")
    (root / ".assert-iq" / "memory" / "MEMORY.md").write_text(
        "- [Flake](topics/flake.md)\n", encoding="utf-8")
    (root / ".assert-iq" / "memory" / "topics" / "flake.md").write_text(
        "# Flake\nquarantine history\n", encoding="utf-8")
    if poisoned:
        # A -> B -> A reference cycle, which memory-sanity flags.
        (root / ".assert-iq" / "memory" / "topics" / "a.md").write_text(
            "# A\nsee [[b]]\n", encoding="utf-8")
        (root / ".assert-iq" / "memory" / "topics" / "b.md").write_text(
            "# B\nsee [[a]]\n", encoding="utf-8")
    return root


def run(root, *args):
    proc = subprocess.run(
        [sys.executable, str(SAFETY), "--workspace", str(root)] + list(args),
        capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def cycle_id_from(out):
    for line in out.splitlines():
        if line.startswith("CYCLE_ID="):
            return line.split("=", 1)[1].strip()
    raise AssertionError("pre did not print a CYCLE_ID line:\n" + out)


def provenance(root):
    return json.loads(
        (root / ".assert-iq" / "dreaming" / "provenance.json").read_text(encoding="utf-8-sig"))


def test_pre_snapshots_and_opens_a_cycle():
    root = make_workspace()
    code, out = run(root, "pre")
    assert code == 0, out

    snaps = list((root / ".assert-iq" / "dreaming" / ".snapshots").glob("mem-*.tar.gz"))
    assert len(snaps) == 1, f"expected one snapshot, got {snaps}"

    cycles = provenance(root)["dream_cycles"]
    assert len(cycles) == 1, cycles
    rec = cycles[0]
    assert rec["status"] == "in_progress"
    assert rec["memory_version_before"].startswith("sha256"), rec
    assert rec["snapshot"].endswith(".tar.gz")
    assert rec["completed_at"] is None
    print("✅ Test 1: pre snapshots memory and opens a provenance cycle")
    return True


def test_post_closes_the_cycle():
    root = make_workspace()
    cid = cycle_id_from(run(root, "pre")[1])

    # Simulate consolidation.
    (root / ".assert-iq" / "memory" / "topics" / "auth.md").write_text(
        "# Auth\nrotation\n", encoding="utf-8")

    code, out = run(root, "post", "--cycle-id", cid)
    assert code == 0, out
    rec = provenance(root)["dream_cycles"][0]
    assert rec["status"] == "completed", rec
    assert rec["completed_at"], rec
    assert rec["memory_version_after"] != rec["memory_version_before"]
    assert rec["memory_changed"] is True
    print("✅ Test 2: post closes the cycle and records the after-version")
    return True


def test_snapshot_restores_to_the_recorded_version():
    """The reproducibility contract, end to end."""
    root = make_workspace()
    cid = cycle_id_from(run(root, "pre")[1])
    rec = provenance(root)["dream_cycles"][0]
    recorded = rec["memory_version_before"]

    # Consolidate destructively, then restore exactly as the contract documents.
    memory = root / ".assert-iq" / "memory"
    (memory / "topics" / "auth.md").write_text("# Auth\n", encoding="utf-8")
    (memory / "topics" / "flake.md").unlink()
    import shutil
    shutil.rmtree(memory)
    with tarfile.open(root / rec["snapshot"], "r:gz") as tar:
        tar.extractall(root / ".assert-iq")

    sys.path.insert(0, str(ASSERT_IQ))
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "aiq_dream_hash", ASSERT_IQ / "analysis" / "verdict-recorder.py")
    recorder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(recorder)

    restored = recorder.compute_memory_hash(str(memory))
    assert restored == recorded, (
        "restoring the snapshot did not reproduce the recorded memory_version:\n"
        f"  recorded {recorded}\n  restored {restored}")
    print("✅ Test 3: snapshot restores to the exact recorded memory_version")
    return True


def test_higher_tier_blocks_on_sanity_failure():
    root = make_workspace(tier="higher", poisoned=True)
    code, out = run(root, "pre")
    assert code == 1, f"expected exit 1 (blocked), got {code}:\n{out}"
    assert "BLOCKED" in out, out
    # A blocked run must still leave a restore point.
    snaps = list((root / ".assert-iq" / "dreaming" / ".snapshots").glob("mem-*.tar.gz"))
    assert len(snaps) == 1, "a blocked run left no snapshot to restore from"
    print("✅ Test 4: higher tier blocks on sanity failure, snapshot still taken")
    return True


def test_lower_tiers_warn_but_do_not_block():
    for tier in ("early", "mid"):
        root = make_workspace(tier=tier, poisoned=True)
        code, out = run(root, "pre")
        assert code == 0, f"tier {tier} should warn, not block; got {code}:\n{out}"
        assert "sanity:" in out and "issue" in out, out
    print("✅ Test 5: early/mid tiers warn on sanity issues without blocking")
    return True


def test_cycle_ids_stay_unique():
    """Two dreams inside the same second must not collide.

    The stamp is second-resolution and find_cycle() returns the first match,
    so a duplicate id would make the audit log ambiguous and let the second
    run overwrite the first one's snapshot.
    """
    root = make_workspace()
    first = cycle_id_from(run(root, "pre")[1])
    second = cycle_id_from(run(root, "pre")[1])
    assert first != second, f"duplicate cycle id: {first}"

    ids = [c["cycle_id"] for c in provenance(root)["dream_cycles"]]
    assert len(ids) == len(set(ids)) == 2, ids
    snaps = sorted(p.name for p in
                   (root / ".assert-iq" / "dreaming" / ".snapshots").glob("mem-*.tar.gz"))
    assert len(snaps) == 2, f"second run overwrote the first snapshot: {snaps}"
    print("✅ Test 6: cycle ids and snapshots stay unique within one second")
    return True


def test_provenance_is_append_only():
    root = make_workspace()
    for _ in range(3):
        run(root, "pre")
    cycles = provenance(root)["dream_cycles"]
    assert len(cycles) == 3, f"earlier cycles were lost: {len(cycles)}"
    log = provenance(root)
    assert log["schema_version"] == "1.0"
    print("✅ Test 7: provenance keeps every prior cycle")
    return True


def test_snapshot_retention_prunes_oldest():
    root = make_workspace(retention=3)
    for _ in range(6):
        run(root, "pre")
    snaps = sorted(p.name for p in
                   (root / ".assert-iq" / "dreaming" / ".snapshots").glob("mem-*.tar.gz"))
    assert len(snaps) == 3, f"retention not honored: {snaps}"
    # Every cycle stays in the log even when its archive is pruned.
    assert len(provenance(root)["dream_cycles"]) == 6
    print("✅ Test 8: snapshot retention prunes oldest, log keeps all cycles")
    return True


def _corpus(root):
    p = root / ".assert-iq" / "tests" / "_qi" / "regression" / "golden-corpus.jsonl"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        '{"pr_id":"a","expected_verdict_band":"green"}\n'
        '{"pr_id":"b","expected_verdict_band":"amber"}\n'
        '{"pr_id":"c","expected_verdict_band":"red"}\n', encoding="utf-8")
    return p


def _results(root, bands):
    p = root / "actual.jsonl"
    p.write_text("".join(
        '{"pr_id":"%s","actual_verdict_band":"%s"}\n' % kv for kv in bands.items()),
        encoding="utf-8")
    return p


def test_regression_is_off_by_default():
    root = make_workspace()
    _corpus(root)
    res = _results(root, {"a": "green", "b": "amber", "c": "red"})
    code, out = run(root, "regression", "--cycle-id", "x", "--results", str(res))
    assert code == 0 and "disabled" in out, out
    print("✅ Test 9: regression check is a no-op while disabled in config")
    return True


def test_regression_computes_divergence_and_gates():
    # Over threshold, but tier/config do not enforce -> warn, exit 0.
    root = make_workspace(tier="mid", reg_enabled="true", block="true")
    _corpus(root)
    cid = cycle_id_from(run(root, "pre")[1])
    res = _results(root, {"a": "green", "b": "amber", "c": "amber"})  # 1 of 3 wrong
    code, out = run(root, "regression", "--cycle-id", cid, "--results", str(res))
    assert code == 0, f"mid tier must not block:\n{out}"
    assert "33.3%" in out, out
    rec = provenance(root)["dream_cycles"][0]["regression"]
    assert rec["diverged"] == 1 and rec["compared"] == 3 and rec["over_threshold"] is True

    # Same divergence at higher tier with blocking on -> exit 1.
    root = make_workspace(tier="higher", reg_enabled="true", block="true")
    _corpus(root)
    cid = cycle_id_from(run(root, "pre")[1])
    res = _results(root, {"a": "green", "b": "amber", "c": "amber"})
    code, out = run(root, "regression", "--cycle-id", cid, "--results", str(res))
    assert code == 1, f"higher tier + block must block; got {code}:\n{out}"
    assert "BLOCKED" in out, out

    # A clean re-run passes.
    root = make_workspace(tier="higher", reg_enabled="true", block="true")
    _corpus(root)
    cid = cycle_id_from(run(root, "pre")[1])
    res = _results(root, {"a": "green", "b": "amber", "c": "red"})
    code, out = run(root, "regression", "--cycle-id", cid, "--results", str(res))
    assert code == 0, out
    print("✅ Test 10: regression divergence computed and gated by tier + config")
    return True


def test_missing_memory_store_is_an_error_not_a_silent_pass():
    root = Path(tempfile.mkdtemp()) / "ws"
    (root / ".assert-iq").mkdir(parents=True)
    (root / ".assert-iq" / "config.yaml").write_text(
        CONFIG.format(tier="early", retention=10, reg_enabled="false", block="false"),
        encoding="utf-8")
    code, out = run(root, "pre")
    assert code == 2, f"expected exit 2 (environment error), got {code}:\n{out}"
    print("✅ Test 11: a missing memory store errors rather than dreaming blind")
    return True


if __name__ == "__main__":
    tests = [test_pre_snapshots_and_opens_a_cycle,
             test_post_closes_the_cycle,
             test_snapshot_restores_to_the_recorded_version,
             test_higher_tier_blocks_on_sanity_failure,
             test_lower_tiers_warn_but_do_not_block,
             test_cycle_ids_stay_unique,
             test_provenance_is_append_only,
             test_snapshot_retention_prunes_oldest,
             test_regression_is_off_by_default,
             test_regression_computes_divergence_and_gates,
             test_missing_memory_store_is_an_error_not_a_silent_pass]
    passed = failed = 0
    print("=== Dream Safety Tests ===")
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"❌ {test.__name__} FAILED: {e}")
            failed += 1
    print(f"\nResults: {passed} PASS, {failed} FAIL")
    sys.exit(0 if failed == 0 else 1)
