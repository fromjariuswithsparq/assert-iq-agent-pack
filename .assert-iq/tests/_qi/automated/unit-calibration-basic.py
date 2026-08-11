#!/usr/bin/env python3
"""Basic unit tests for calibration library."""

import sys
import json
from pathlib import Path

# Add analysis module to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "analysis"))

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


if __name__ == "__main__":
    tests = [test_brier_all_correct, test_brier_all_wrong, test_confusion_matrix, test_layer_fidelity]
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
