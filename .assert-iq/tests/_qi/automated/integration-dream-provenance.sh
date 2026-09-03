#!/bin/bash

# Shared helpers: Python-interpreter resolution + JSON assertions.
# Sourced by path relative to THIS file so it works from any cwd.
_AIQ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_AIQ_LIB_DIR/lib/aiq-test-lib.sh"
# Integration: Dream cycle provenance tracking

set -e
PASSED=0
FAILED=0

PROVENANCE_FILE=".assert-iq/dreaming/provenance.json"
SNAPSHOTS_DIR=".assert-iq/dreaming/.snapshots"

test_provenance_exists() {
    if [ -f "$PROVENANCE_FILE" ]; then
        echo "✅ Test 1: Provenance log exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 1 FAILED: Missing provenance file"
        ((FAILED++))
        return 1
    fi
}

test_provenance_valid_json() {
    if aiq_json_valid "$PROVENANCE_FILE"; then
        echo "✅ Test 2: Provenance JSON is valid"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 2 FAILED: Invalid JSON"
        ((FAILED++))
        return 1
    fi
}

test_provenance_has_schema() {
    if aiq_json_test "$PROVENANCE_FILE" "d.get('schema_version') is not None and d.get('dream_cycles') is not None"; then
        echo "✅ Test 3: Provenance has schema_version and dream_cycles"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 3 FAILED: Missing schema fields"
        ((FAILED++))
        return 1
    fi
}

test_snapshots_directory_exists() {
    if [ -d "$SNAPSHOTS_DIR" ]; then
        echo "✅ Test 4: Snapshots directory exists"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 4 FAILED: Missing snapshots dir"
        ((FAILED++))
        return 1
    fi
}

test_snapshots_directory_writable() {
    if [ -w "$SNAPSHOTS_DIR" ]; then
        echo "✅ Test 5: Snapshots directory is writable"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 5 FAILED: Snapshots dir not writable"
        ((FAILED++))
        return 1
    fi
}

# The five checks above only prove the sink EXISTS. For most of this pack's
# life that was all they proved, and they passed the entire time while nothing
# on earth wrote to provenance.json and .snapshots/ stayed empty -- the /dream
# skill never invoked any of it. An existence check on an append-only audit log
# is close to worthless on its own, so assert the producer too.
test_producer_exists() {
    if [ -f ".assert-iq/analysis/dream-safety.py" ]; then
        echo "✅ Test 6: dream-safety.py (the producer) is present"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 6 FAILED: no dream-safety.py -- provenance.json can only stay empty"
        ((FAILED++))
        return 1
    fi
}

test_dream_skill_invokes_the_producer() {
    skill=".github/skills/dream/SKILL.md"
    if [ -f "$skill" ] && grep -q "dream-safety.py pre" "$skill" \
       && grep -q "dream-safety.py post" "$skill"; then
        echo "✅ Test 7: /dream invokes the pre and post safety steps"
        ((PASSED++))
        return 0
    else
        echo "❌ Test 7 FAILED: /dream does not call dream-safety.py -- the"
        echo "   qi-foundation Memory Poisoning Prevention procedure is unwired"
        ((FAILED++))
        return 1
    fi
}

echo "=== Integration: Dream Provenance ==="
test_provenance_exists || true
test_provenance_valid_json || true
test_provenance_has_schema || true
test_snapshots_directory_exists || true
test_snapshots_directory_writable || true
test_producer_exists || true
test_dream_skill_invokes_the_producer || true

echo ""
echo "Results: $PASSED PASS, $FAILED FAIL"
[ $FAILED -eq 0 ]
