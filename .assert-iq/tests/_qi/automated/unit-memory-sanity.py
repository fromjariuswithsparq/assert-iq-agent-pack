#!/usr/bin/env python3
"""Unit tests for memory sanity checker."""

import sys
import json
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "analysis"))

def test_cycle_detection_simple():
    """Test cycle detection with simple A->B->A cycle."""
    from memory_sanity import detect_cycles
    
    topics = {
        "topic-a": "Content with [[topic-b]]",
        "topic-b": "Content with [[topic-a]]",
    }
    
    cycles = detect_cycles(topics)
    assert len(cycles) > 0, "Should detect A->B->A cycle"
    print("✅ Test 1: Simple cycle detection (A->B->A)")
    return True


def test_cycle_detection_no_cycle():
    """Test cycle detection with no cycles."""
    from memory_sanity import detect_cycles
    
    topics = {
        "topic-a": "Content with [[topic-b]]",
        "topic-b": "Content (no refs)",
    }
    
    cycles = detect_cycles(topics)
    assert len(cycles) == 0, "Should not detect cycles when none exist"
    print("✅ Test 2: No false positives on acyclic graph")
    return True


def test_staleness_detection():
    """Test fact staleness checking."""
    from memory_sanity import detect_staleness
    
    topics = {
        "topic-a": "Updated: 2024-01-01. This fact is stale.",
        "topic-b": "Updated: 2026-08-10. This fact is recent.",
    }
    
    stale_facts = detect_staleness(topics, threshold_days=180)
    # Should detect 2024-01-01 as stale
    assert len(stale_facts) > 0, "Should detect stale facts"
    print("✅ Test 3: Staleness detection (>180 days)")
    return True


def test_contradiction_detection():
    """Test contradiction detection."""
    from memory_sanity import detect_contradictions
    
    topics = {
        "topic-critical": "Service X is critical to operations",
        "topic-secondary": "Service X is low-priority",
    }
    
    contradictions = detect_contradictions(topics)
    # Should detect conflicting priority statements
    assert len(contradictions) > 0, "Should detect contradictions"
    print("✅ Test 4: Contradiction detection")
    return True


def test_granularity_no_issues():
    """Test granularity check on good content."""
    from memory_sanity import detect_granularity_issues
    
    topics = {
        "topic-a": "This is synthesized content about a pattern we observed.",
    }
    
    issues = detect_granularity_issues(topics)
    # Well-synthesized content should have no granularity issues
    assert len(issues) == 0, "Should not flag synthesized content"
    print("✅ Test 5: Granularity check (no false positives)")
    return True


if __name__ == "__main__":
    tests = [
        test_cycle_detection_simple,
        test_cycle_detection_no_cycle,
        test_staleness_detection,
        test_contradiction_detection,
        test_granularity_no_issues,
    ]
    
    passed = 0
    failed = 0
    
    print("=== Memory Sanity Unit Tests ===")
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"❌ {test.__name__} FAILED: {e}")
            failed += 1
    
    print(f"\nResults: {passed} PASS, {failed} FAIL")
    sys.exit(0 if failed == 0 else 1)
