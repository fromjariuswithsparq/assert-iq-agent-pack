#!/usr/bin/env python3
"""Verdict recorder must work on a stdlib-only Python 3.

README > Environment requirements lists "Python 3" as the pack's only Python
dependency, and no installer ever runs pip. A module-scope `import yaml` in
verdict-recorder.py therefore broke the whole module on a stock interpreter --
on Windows, macOS, Claude Code and Copilot alike -- taking VerdictRecorder and
compute_memory_hash down with it even though neither touches YAML.
"""

import sys
import builtins
import importlib.util
import tempfile
from pathlib import Path

# Windows consoles default to cp1252, which cannot encode the ✅/❌ markers
# below; force UTF-8 so a failing assertion reports the assertion rather than
# a UnicodeEncodeError.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# This file lives at .assert-iq/tests/_qi/automated/, so reaching .assert-iq/
# needs four parents (automated -> _qi -> tests -> .assert-iq).
ASSERT_IQ = Path(__file__).resolve().parent.parent.parent.parent
RECORDER = ASSERT_IQ / "analysis" / "verdict-recorder.py"
CONFIG = ASSERT_IQ / "config.yaml"


class _NoYaml:
    """Context manager that makes `import yaml` fail, whether or not it exists."""

    def __enter__(self):
        self._real_import = builtins.__import__
        self._stashed = sys.modules.pop("yaml", None)

        def guarded(name, *args, **kwargs):
            if name == "yaml" or name.startswith("yaml."):
                raise ImportError("No module named 'yaml' (simulated)")
            return self._real_import(name, *args, **kwargs)

        builtins.__import__ = guarded
        return self

    def __exit__(self, *exc):
        builtins.__import__ = self._real_import
        if self._stashed is not None:
            sys.modules["yaml"] = self._stashed
        return False


def _load_recorder():
    """Load verdict-recorder.py by path (the hyphen bars a normal import)."""
    spec = importlib.util.spec_from_file_location("aiq_recorder_under_test", RECORDER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_module_imports_without_pyyaml():
    """Regression: the module must import when PyYAML is absent."""
    with _NoYaml():
        module = _load_recorder()
    for name in ("VerdictRecorder", "compute_memory_hash", "get_layer_state",
                 "load_config", "are_verdicts_enabled"):
        assert hasattr(module, name), f"missing public name after import: {name}"
    print("✅ Test 1: verdict-recorder imports without PyYAML")
    return True


def test_recording_works_without_pyyaml():
    """VerdictRecorder and compute_memory_hash never needed YAML at all."""
    with _NoYaml():
        module = _load_recorder()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".assert-iq" / "memory").mkdir(parents=True)
            (root / ".assert-iq" / "memory" / "MEMORY.md").write_text("- pointer\n")

            digest = module.compute_memory_hash(str(root / ".assert-iq" / "memory"))
            # Format is asserted in unit-memory-hash-portability.py; here we
            # only care that a real digest came back rather than an error tag.
            assert digest.startswith("sha256"), digest
            assert "error" not in digest and "uninitialized" not in digest, digest

            result = module.VerdictRecorder(str(root)).record_verdict({
                "verdict_type": "pr_risk_assessment",
                "verdict_band": "green",
                "verdict_score": 0.95,
                "layer_scores": {"change": {"state": "strong", "score": 0.9}},
                "memory_version": digest,
                "issued_by": "unit-verdict-recorder-stdlib",
            })
            assert result["success"], result["message"]
            assert (root / ".assert-iq" / "verdicts" / "VERDICTS.md").exists(), \
                "audit trail was not written"
    print("✅ Test 2: verdict recording works without PyYAML")
    return True


def test_gate_still_reads_config_without_pyyaml():
    """Regression: a missing PyYAML must not silently disable the audit trail.

    Returning {} here would make are_verdicts_enabled() False, turning off
    verdict recording with no error -- the failure mode regulated clients
    (SOX, ISO 27001) would discover only during an audit.
    """
    with _NoYaml():
        module = _load_recorder()
        config = module.load_config(str(CONFIG))
        assert config, "fallback reader returned an empty config"
        assert config.get("verdicts", {}).get("enabled") is True, \
            f"verdicts.enabled did not resolve: {config.get('verdicts')!r}"
        assert module.are_verdicts_enabled(config) is True
    print("✅ Test 3: verdicts gate resolves without PyYAML")
    return True


def test_fallback_never_invents_values():
    """The fallback may omit what it cannot represent, but must not guess.

    A block sequence must not masquerade as a mapping: `servers:` holding
    `- name: x / enabled: true` once produced a bogus `servers.enabled`.
    """
    module = _load_recorder()
    parsed = module._parse_config_subset(
        "mcp:\n"
        "  enabled: true\n"
        "  servers:\n"
        '    - name: "github"\n'
        "      enabled: false\n"
        "notes: |\n"
        "  swallowed block body\n"
        "after: 7\n"
    )
    assert parsed["mcp"]["enabled"] is True
    assert "enabled" not in parsed.get("mcp", {}).get("servers", {}), \
        f"sequence child leaked into a mapping: {parsed['mcp']!r}"
    assert "notes" not in parsed, "block scalar should be skipped, not guessed"
    assert parsed["after"] == 7, f"parser lost its place after a block: {parsed!r}"
    print("✅ Test 4: fallback omits rather than invents values")
    return True


def test_fallback_scalar_fidelity():
    """Scalar coercion must match YAML semantics on the forms configs use."""
    module = _load_recorder()
    parsed = module._parse_config_subset(
        "s:\n"
        "  yes_flag: true\n"
        "  no_flag: false\n"
        "  count: 730\n"
        "  weight: 0.25\n"
        "  nothing: null\n"
        '  regex: "(AB#\\\\d+|[A-Z]+-\\\\d+)"\n'
        "  plain: .assert-iq/verdicts\n"
        '  flow: { oracle_weight: 0.5, mode: "can_block_merge" }\n'
    )["s"]
    assert parsed["yes_flag"] is True and parsed["no_flag"] is False
    assert parsed["count"] == 730 and parsed["weight"] == 0.25
    assert parsed["nothing"] is None
    assert parsed["regex"] == r"(AB#\d+|[A-Z]+-\d+)", parsed["regex"]
    assert parsed["plain"] == ".assert-iq/verdicts"
    assert parsed["flow"] == {"oracle_weight": 0.5, "mode": "can_block_merge"}
    print("✅ Test 5: fallback scalar/flow coercion matches YAML semantics")
    return True


if __name__ == "__main__":
    tests = [test_module_imports_without_pyyaml,
             test_recording_works_without_pyyaml,
             test_gate_still_reads_config_without_pyyaml,
             test_fallback_never_invents_values,
             test_fallback_scalar_fidelity]
    passed = 0
    failed = 0

    print("=== Verdict Recorder stdlib-only Tests ===")
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"❌ {test.__name__} FAILED: {e}")
            failed += 1

    print(f"\nResults: {passed} PASS, {failed} FAIL")
    sys.exit(0 if failed == 0 else 1)
