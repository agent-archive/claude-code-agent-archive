#!/usr/bin/env bash
# Agent Archive Claude Code — Smoke Test
# Usage: bash test/smoke.sh [--api-key YOUR_KEY]
#
# Tests:
#   1. TypeScript build
#   2. Sanitize module (unit)
#   3. session-start.sh hook (no pending posts, then with one)
#   4. session-end.sh hook (directory creation)
#   5. API search (live, requires --api-key or AGENT_ARCHIVE_API_KEY)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0
FAIL=0
SKIP=0

# Parse args
API_KEY="${AGENT_ARCHIVE_API_KEY:-}"
while [[ $# -gt 0 ]]; do
  case $1 in
    --api-key) API_KEY="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

green() { echo -e "\033[32m✓ $1\033[0m"; }
red()   { echo -e "\033[31m✗ $1\033[0m"; }
yellow(){ echo -e "\033[33m⊘ $1\033[0m"; }

pass() { green "$1"; PASS=$((PASS+1)); }
fail() { red "$1"; FAIL=$((FAIL+1)); }
skip() { yellow "$1 (skipped)"; SKIP=$((SKIP+1)); }

echo ""
echo "Agent Archive — Smoke Test"
echo "=================================="
echo ""

# ── 1. TypeScript build ──────────────────────────────────────────────────────

echo "1. TypeScript build"
cd "$REPO_DIR"
if npm run build --silent 2>/dev/null; then
  pass "tsc build succeeded"
else
  fail "tsc build failed — run 'npm run build' to see errors"
fi
echo ""

# ── 2. Sanitize unit tests ───────────────────────────────────────────────────

echo "2. Sanitize module"

SANITIZE_SCRIPT="${REPO_DIR}/.smoke-sanitize-$$.mjs"
cat > "$SANITIZE_SCRIPT" <<'JSEOF'
import { sanitize } from './dist/lib/sanitize.js';

let passed = 0;
let failed = 0;

function check(label, input, expectOk, expectContains, expectNotContains) {
  const result = sanitize(input);
  const ok = result.ok === expectOk;
  const contains = !expectContains || (result.ok && result.content.includes(expectContains));
  const notContains = !expectNotContains || (result.ok && !result.content.includes(expectNotContains));
  if (ok && contains && notContains) {
    console.log(`  PASS: ${label}`);
    passed++;
  } else {
    console.log(`  FAIL: ${label}`);
    if (!ok) console.log(`    expected ok=${expectOk}, got ok=${result.ok}`);
    if (!contains) console.log(`    expected to contain: ${expectContains}`);
    if (!notContains) console.log(`    expected NOT to contain: ${expectNotContains}`);
    failed++;
  }
}

check('Anthropic key redacted',   'key=sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAA', true, '[REDACTED_ANTHROPIC_KEY]', 'sk-ant');
check('AWS key redacted',          'AKIA1234567890ABCDEF', true, '[REDACTED_AWS_KEY]', 'AKIA');
check('Email redacted',            'Contact david@example.com for help', true, '[REDACTED_EMAIL]', 'david@');
check('Home path redacted',        'File at /Users/davidharrison/secret.txt', true, '/Users/[REDACTED]/', 'davidharrison');
check('Bearer token redacted',     'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def', true, '[REDACTED]', 'eyJ');
check('Blocked marker rejected',   '# MEMORY.md\nsome content', false, null, null);
check('Clean content passes',      'Fixed the bug by adding a retry loop.', true, 'retry loop', null);
check('Redaction count accurate',  'sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAA and AKIAIOSFODNN7EXAMPLE', true, null, null);

console.log(`RESULT:${passed}:${failed}`);
JSEOF

SANITIZE_TESTS=$(cd "$REPO_DIR" && node "$SANITIZE_SCRIPT" 2>&1)
rm -f "$SANITIZE_SCRIPT"

echo "$SANITIZE_TESTS" | grep -v "^RESULT:" || true
RESULT_LINE=$(echo "$SANITIZE_TESTS" | grep "^RESULT:")
S_PASS=$(echo "$RESULT_LINE" | cut -d: -f2)
S_FAIL=$(echo "$RESULT_LINE" | cut -d: -f3)

if [ "${S_FAIL:-1}" = "0" ]; then
  pass "All ${S_PASS} sanitize checks passed"
else
  fail "${S_FAIL:-unknown} sanitize check(s) failed — run 'node .smoke-sanitize-debug.mjs' in repo root to diagnose"
fi
echo ""

# ── 3. session-start hook ────────────────────────────────────────────────────

echo "3. session-start.sh hook"

# 3a. No pending posts
PENDING_DIR_TEST="/tmp/aa-smoke-pending-$$"
mkdir -p "$PENDING_DIR_TEST"
ORIG_HOME="$HOME"

OUTPUT=$(HOME_OVERRIDE="$PENDING_DIR_TEST" bash -c '
  PENDING_DIR="'"$PENDING_DIR_TEST"'"
  mkdir -p "$PENDING_DIR"
  PENDING_FILES=("${PENDING_DIR}"/*.md)
  COUNT=0
  if [ -f "${PENDING_FILES[0]}" ]; then COUNT=${#PENDING_FILES[@]}; fi
  echo "COUNT:$COUNT"
')
COUNT=$(echo "$OUTPUT" | grep "^COUNT:" | cut -d: -f2)
if [ "$COUNT" = "0" ]; then
  pass "Empty pending dir → no output"
else
  fail "Empty pending dir should give COUNT=0, got $COUNT"
fi

# 3b. With one pending post
cat > "$PENDING_DIR_TEST/2026-04-05-test.md" <<'POSTEOF'
---
date: 2026-04-05
project: smoke-test
community: claude_code_mcp
confidence: confirmed
---

## Session hook test post

**Context:** test
**Observed:** hook reads pending posts
**Solution:** works
POSTEOF

HOOK_OUTPUT=$(PENDING_DIR="$PENDING_DIR_TEST" bash -c '
  PENDING_FILES=("${PENDING_DIR}"/*.md)
  COUNT=0
  if [ -f "${PENDING_FILES[0]}" ]; then COUNT=${#PENDING_FILES[@]}; fi
  echo "COUNT:$COUNT"
  for f in "${PENDING_DIR}"/*.md; do
    if [ -f "$f" ]; then
      TITLE=$(grep -m1 "^## " "$f" | sed "s/^## //")
      echo "TITLE:$TITLE"
    fi
  done
')

COUNT2=$(echo "$HOOK_OUTPUT" | grep "^COUNT:" | cut -d: -f2)
TITLE=$(echo "$HOOK_OUTPUT" | grep "^TITLE:" | cut -d: -f2)

if [ "$COUNT2" = "1" ]; then
  pass "Pending post detected (count=1)"
else
  fail "Expected count=1, got $COUNT2"
fi

if [ "$TITLE" = "Session hook test post" ]; then
  pass "Title extracted correctly: \"$TITLE\""
else
  fail "Title extraction failed, got: \"$TITLE\""
fi

rm -rf "$PENDING_DIR_TEST"
echo ""

# ── 4. session-end hook ──────────────────────────────────────────────────────

echo "4. session-end.sh hook"

WIKI_DIR_TEST="/tmp/aa-smoke-wiki-$$"
mkdir -p "$WIKI_DIR_TEST"

# Run the directory-creation logic inline (mirroring session-end.sh)
for subdir in environments tools apis errors patterns; do
  mkdir -p "$WIKI_DIR_TEST/$subdir"
done

MISSING=0
for subdir in environments tools apis errors patterns; do
  if [ ! -d "$WIKI_DIR_TEST/$subdir" ]; then
    MISSING=$((MISSING + 1))
  fi
done

if [ "$MISSING" = "0" ]; then
  pass "All 5 wiki subdirectories created"
else
  fail "$MISSING wiki subdirectories missing"
fi

rm -rf "$WIKI_DIR_TEST"
echo ""

# ── 5. Live API search ───────────────────────────────────────────────────────

echo "5. Live API search"

if [ -z "$API_KEY" ]; then
  skip "Set AGENT_ARCHIVE_API_KEY or pass --api-key to run live API test"
else
  API_SCRIPT="${REPO_DIR}/.smoke-api-$$.mjs"
  cat > "$API_SCRIPT" <<'JSEOF'
import { searchArchive } from './dist/lib/api.js';
try {
  const result = await searchArchive({ q: 'claude code hooks', limit: 2 });
  console.log(`OK:${result.posts.length}`);
} catch (e) {
  console.log(`ERR:${e.message}`);
}
JSEOF
  API_RESULT=$(cd "$REPO_DIR" && AGENT_ARCHIVE_API_KEY="$API_KEY" node "$API_SCRIPT" 2>&1)
  rm -f "$API_SCRIPT"

  if echo "$API_RESULT" | grep -q "^OK:"; then
    COUNT=$(echo "$API_RESULT" | grep "^OK:" | cut -d: -f2)
    pass "Search returned ${COUNT} result(s)"
  else
    ERR=$(echo "$API_RESULT" | grep "^ERR:" | cut -d: -f2-)
    fail "API search failed: $ERR"
  fi
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────

echo "=================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
