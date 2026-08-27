#!/bin/bash
# ============================================================================
# UNIT: Dreaming enable-gate semantics (bash side)
# ============================================================================
# WHY THIS EXISTS
#
# aiq_enabled() decides whether the waking loop runs. Two bugs lived here:
#
# 1. It executed a python3 snippet and returned ITS exit status, so a missing or
#    stubbed interpreter was indistinguishable from `dreaming.enabled: false`.
#    On Windows `python3` is a Microsoft Store stub that resolves on PATH and
#    fails on invocation, so the hook exited 0, printed {"continue":true} and
#    wrote nothing -- for weeks, silently. The gate is now pure awk.
#
# 2. The first awk rewrite matched `enabled: false` at ANY depth inside the
#    dreaming block. The shipped config.yaml has a NESTED `enabled: false` for
#    the optional background dreamer, so that rule read "dreaming off" and would
#    have disabled the feature for every user. Only the FIRST `enabled:` in the
#    block counts, matching the original python semantics.
#
# These assertions run with an EMPTY interpreter PATH on purpose: the gate must
# depend on config only.
#
# PORTABILITY: bash 3.2 safe. Run from the repo root.
# ============================================================================

LIB=".assert-iq/dreaming/scripts/lib/dream-utils.sh"
CFG=".assert-iq/config.yaml"
PASSED=0
FAILED=0

pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

echo "=== UNIT: Dreaming enable-gate semantics ==="
echo ""

if [ ! -f "$LIB" ]; then
  echo "❌ missing $LIB"
  echo ""
  echo "=== Results: 0 PASS, 1 FAIL ==="
  exit 1
fi

TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/aiqgate.$$")"
mkdir -p "$TMP"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Ask the gate for a verdict with the given config, and with NO python/py on
# PATH, so any interpreter dependency shows up as a wrong answer.
gate_verdict() {
  local cfg="$1"
  env PATH="/usr/bin:/bin" AIQ_CONFIG="$cfg" AIQ_MEMORY_DIR="$TMP/mem" \
      bash -c ". $LIB; if aiq_enabled; then echo enabled; else echo disabled; fi" 2>/dev/null
}

# --- 1. shipped config, no interpreter -> enabled (dreaming is opt-out) -----
v="$(gate_verdict "$CFG")"
if [ "$v" = "enabled" ]; then
  pass "shipped config with no interpreter on PATH -> enabled"
else
  fail "shipped config with no interpreter -> '$v' (expected enabled). A missing"
  echo "      interpreter must not read as 'dreaming disabled' -- that is the"
  echo "      silent-failure mode this gate was rewritten to remove."
fi

# --- 2. nested enabled:false must NOT disable dreaming ---------------------
# Mirrors the real config: dreaming.enabled true, service.enabled false.
cat > "$TMP/nested.yaml" <<'YAML'
dreaming:
  enabled: true

  service:
    # optional background dreamer
    enabled: false
YAML
v="$(gate_verdict "$TMP/nested.yaml")"
if [ "$v" = "enabled" ]; then
  pass "nested 'enabled: false' (background dreamer) does not disable dreaming"
else
  fail "nested 'enabled: false' disabled dreaming -> '$v'. Only the FIRST"
  echo "      'enabled:' inside the dreaming block may count; the shipped"
  echo "      config.yaml has a nested one for the optional service."
fi

# --- 3. dreaming.enabled: false must disable ------------------------------
cat > "$TMP/off.yaml" <<'YAML'
dreaming:
  enabled: false
YAML
v="$(gate_verdict "$TMP/off.yaml")"
if [ "$v" = "disabled" ]; then
  pass "dreaming.enabled: false -> disabled"
else
  fail "dreaming.enabled: false -> '$v' (expected disabled)"
fi

# --- 4. no dreaming block at all -> enabled (default on) ------------------
printf 'maturity: mid\n' > "$TMP/none.yaml"
v="$(gate_verdict "$TMP/none.yaml")"
if [ "$v" = "enabled" ]; then
  pass "config with no dreaming block -> enabled (default)"
else
  fail "config with no dreaming block -> '$v' (expected enabled)"
fi

# --- 5. an unrelated section's enabled:false must not leak ----------------
cat > "$TMP/other.yaml" <<'YAML'
dreaming:
  enabled: true

oracle:
  enabled: false
YAML
v="$(gate_verdict "$TMP/other.yaml")"
if [ "$v" = "enabled" ]; then
  pass "unrelated section's 'enabled: false' does not leak into the gate"
else
  fail "unrelated section disabled dreaming -> '$v'"
fi

# --- 6. kill switch ------------------------------------------------------
v="$(env PATH="/usr/bin:/bin" AIQ_CONFIG="$CFG" AIQ_MEMORY_DIR="$TMP/mem" \
        AIQ_DREAMING_DISABLED=1 \
        bash -c ". $LIB; if aiq_enabled; then echo enabled; else echo disabled; fi" 2>/dev/null)"
if [ "$v" = "disabled" ]; then
  pass "AIQ_DREAMING_DISABLED=1 kill switch honored"
else
  fail "kill switch ignored -> '$v'"
fi

echo ""
echo "=== Results: $PASSED PASS, $FAILED FAIL ==="
[ $FAILED -eq 0 ] && exit 0 || exit 1
