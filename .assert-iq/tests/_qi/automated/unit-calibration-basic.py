#!/usr/bin/env python3
"""Basic unit tests for calibration library."""

import sys
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Windows consoles default to cp1252, which cannot encode the ✅/❌ markers
# below; force UTF-8 so a failing assertion reports the assertion rather than
# a UnicodeEncodeError.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Add analysis module to path. This file lives at
# .assert-iq/tests/_qi/automated/, so reaching .assert-iq/analysis/ needs four
# parents (automated -> _qi -> tests -> .assert-iq), not three.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent.parent / "analysis"))

def test_brier_all_correct():
    """Test Brier score when all verdicts are correct (no escapes)."""
    from calibration import compute_brier_score
    
    verdicts = [
        {"verdict_band": "green", "verdict_score": 0.95, "linked_escape": None, "issued_at": "2026-08-11T10:00:00Z"},
        {"verdict_band": "green", "verdict_score": 0.92, "linked_escape": None, "issued_at": "2026-08-11T10:00:00Z"},
    ]
    
    result = compute_brier_score(verdicts)
    green_score = result["per_band"]["green"]["score"]
    
    # All correct → score close to 0.0
    assert green_score is not None and green_score < 0.1, f"Expected ~0.0, got {green_score}"
    print("✅ Test 1: Brier score all correct (≈0.0)")
    return True


def test_brier_all_wrong():
    """Test Brier score when all verdicts are wrong (escapes)."""
    from calibration import compute_brier_score
    
    verdicts = [
        {"verdict_band": "green", "verdict_score": 0.95, "linked_escape": {"defect_id": "BUG-1"}, "issued_at": "2026-08-11T10:00:00Z"},
        {"verdict_band": "green", "verdict_score": 0.92, "linked_escape": {"defect_id": "BUG-2"}, "issued_at": "2026-08-11T10:00:00Z"},
    ]
    
    result = compute_brier_score(verdicts)
    green_score = result["per_band"]["green"]["score"]
    
    # All wrong → high score
    assert green_score is not None and green_score > 0.5, f"Expected >0.5, got {green_score}"
    print("✅ Test 2: Brier score all wrong (>0.5)")
    return True


def test_confusion_matrix():
    """Test confusion matrix generation."""
    from calibration import confusion_matrix
    
    verdicts = [
        {"verdict_band": "green", "linked_escape": None},
        {"verdict_band": "green", "linked_escape": None},
        {"verdict_band": "amber", "linked_escape": {"defect_id": "BUG-1"}},
    ]
    
    result = confusion_matrix(verdicts)
    assert result["green"]["correct"] == 2, f"Expected 2 green correct, got {result['green']['correct']}"
    assert result["amber"]["escaped"] == 1, f"Expected 1 amber escaped, got {result['amber']['escaped']}"
    print("✅ Test 3: Confusion matrix generation")
    return True


def test_layer_fidelity():
    """Test per-layer signal fidelity scoring."""
    from calibration import layer_fidelity
    
    verdicts = [
        {
            "linked_escape": None,
            "layer_scores": {
                "change": {"state": "weak", "score": 0.4},
                "protection": {"state": "strong", "score": 0.8}
            }
        },
        {
            "linked_escape": {"defect_id": "BUG-1"},
            "layer_scores": {
                "change": {"state": "weak", "score": 0.3},
                "protection": {"state": "strong", "score": 0.9}
            }
        },
    ]
    
    result = layer_fidelity(verdicts)
    assert result["change"]["weak_fidelity"] == 0.5, f"Expected 0.5, got {result['change']['weak_fidelity']}"
    print("✅ Test 4: Layer fidelity computation")
    return True


def _iso_days_ago(days, suffix="Z"):
    """Timestamp `days` in the past, written the way verdict-recorder writes them."""
    stamp = datetime.now(timezone.utc) - timedelta(days=days)
    if suffix == "Z":
        return stamp.replace(tzinfo=None).isoformat() + "Z"
    return stamp.astimezone(timezone(timedelta(hours=-5))).isoformat()


def test_brier_window_excludes_old_verdicts():
    """--window-days must actually filter. Regression: naive/aware datetime
    comparison raised TypeError, which was swallowed, so every verdict was
    counted regardless of age."""
    from calibration import compute_brier_score

    verdicts = [
        {"verdict_band": "green", "verdict_score": 0.95, "linked_escape": None,
         "issued_at": _iso_days_ago(5)},
        {"verdict_band": "green", "verdict_score": 0.95,
         "linked_escape": {"defect_id": "BUG-OLD"}, "issued_at": _iso_days_ago(400)},
    ]

    result = compute_brier_score(verdicts, window_days=90)
    count = result["aggregate"]["count"]
    escaped = result["per_band"]["green"]["escaped_count"]

    assert count == 1, f"Expected 1 verdict inside the 90-day window, got {count}"
    assert escaped == 0, f"400-day-old escape leaked into the window: {escaped}"
    print("\u2705 Test 5: Brier window excludes out-of-window verdicts")
    return True


def test_brier_window_handles_offset_timestamps():
    """Timestamps carrying a non-UTC offset are normalized, not dropped."""
    from calibration import compute_brier_score

    verdicts = [
        {"verdict_band": "green", "verdict_score": 0.9, "linked_escape": None,
         "issued_at": _iso_days_ago(2, suffix="offset")},
        {"verdict_band": "green", "verdict_score": 0.9, "linked_escape": None,
         "issued_at": _iso_days_ago(200, suffix="offset")},
    ]

    result = compute_brier_score(verdicts, window_days=30)
    count = result["aggregate"]["count"]

    assert count == 1, f"Expected 1 verdict inside the 30-day window, got {count}"
    print("\u2705 Test 6: Brier window normalizes offset-bearing timestamps")
    return True


def test_drift_detection_buckets_verdicts():
    """Drift detection must populate rolling windows. Regression: the same
    datetime comparison failure left `windows` permanently empty, so drift
    could never be detected."""
    from calibration import drift_detection

    def verdict(days, escaped):
        return {
            "verdict_band": "green", "verdict_score": 0.95,
            "linked_escape": {"defect_id": "BUG-1"} if escaped else None,
            "issued_at": _iso_days_ago(days),
        }

    # Recent window degraded (escapes); oldest window clean.
    verdicts = [verdict(5, True), verdict(10, True),
                verdict(70, False), verdict(75, False)]

    result = drift_detection(verdicts, window_days=30)

    assert len(result["windows"]) >= 2, f"Expected >=2 populated windows, got {result['windows']}"
    assert result["drift_detected"] is True, "Expected drift on a degrading recent window"
    print("\u2705 Test 7: Drift detection buckets verdicts into rolling windows")
    return True


if __name__ == "__main__":
    tests = [test_brier_all_correct, test_brier_all_wrong, test_confusion_matrix,
             test_layer_fidelity, test_brier_window_excludes_old_verdicts,
             test_brier_window_handles_offset_timestamps,
             test_drift_detection_buckets_verdicts]
    passed = 0
    failed = 0
    
    print("=== Calibration Unit Tests ===")
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"❌ {test.__name__} FAILED: {e}")
            failed += 1
    
    print(f"\nResults: {passed} PASS, {failed} FAIL")
    sys.exit(0 if failed == 0 else 1)
