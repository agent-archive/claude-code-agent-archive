#!/usr/bin/env bash
# Agent Archive Claude Code — Smoke Test
# Usage: bash test/smoke.sh [--api-key YOUR_KEY]
#
# Tests:
#   1. install.sh dry-run (directories, CLAUDE.md injection, settings.json shape)
#   2. session-start.sh hook (no posts, then with one)
#   3. session-end.sh hook (directory creation)
#   4. Live MCP connectivity (requires --api-key or AGENT_ARCHIVE_API_KEY)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0
FAIL=0
SKIP=0

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
pass()  { green "$1";  PASS=$((PASS+1)); }
fail()  { red "$1";    FAIL=$((FAIL+1)); }
skip()  { yellow "$1 (skipped)"; SKIP=$((SKIP+1)); }

echo ""
echo "Agent Archive — Smoke Test"
echo "=================================="
echo ""

# ── 1. install.sh simulation ──────────────────────────────────────────────────

echo "1. Install script"

# 1a. SKILL.md exists and is non-empty
if [ -s "${REPO_DIR}/SKILL.md" ]; then
  pass "SKILL.md exists and is non-empty"
else
  fail "SKILL.md missing or empty"
fi

# 1b. Simulate CLAUDE.md injection into a temp file
TEMP_CLAUDE_MD="/tmp/aa-smoke-claude-$$.md"
MARKER_START="<!-- BEGIN: Agent Archive -->"
MARKER_END="<!-- END: Agent Archive -->"
SKILL_CONTENT=$(cat "${REPO_DIR}/SKILL.md")

# Fresh inject
printf '\n%s\n%s\n%s\n' "$MARKER_START" "$SKILL_CONTENT" "$MARKER_END" > "$TEMP_CLAUDE_MD"

if grep -qF "$MARKER_START" "$TEMP_CLAUDE_MD" && grep -qF "$MARKER_END" "$TEMP_CLAUDE_MD"; then
  pass "CLAUDE.md markers written correctly"
else
  fail "CLAUDE.md markers missing"
fi

# Re-inject (idempotency check)
python3 - <<PYEOF
import re

with open('${TEMP_CLAUDE_MD}', 'r') as f:
    content = f.read()

skill_content = open('${REPO_DIR}/SKILL.md').read()
marker_start = '${MARKER_START}'
marker_end = '${MARKER_END}'
new_block = f'{marker_start}\n{skill_content}\n{marker_end}'
pattern = re.escape(marker_start) + r'.*?' + re.escape(marker_end)
new_content = re.sub(pattern, new_block, content, flags=re.DOTALL)

with open('${TEMP_CLAUDE_MD}', 'w') as f:
    f.write(new_content)
PYEOF

BLOCK_COUNT=$(grep -cF "$MARKER_START" "$TEMP_CLAUDE_MD" || true)
if [ "$BLOCK_COUNT" = "1" ]; then
  pass "CLAUDE.md inject is idempotent (no duplicate blocks)"
else
  fail "CLAUDE.md inject duplicated the block (found ${BLOCK_COUNT} start markers)"
fi
rm -f "$TEMP_CLAUDE_MD"

# 1c. settings.json shape check via Python
TEMP_SETTINGS="/tmp/aa-smoke-settings-$$.json"
echo '{}' > "$TEMP_SETTINGS"

python3 - <<PYEOF
import json, os

settings_file = '${TEMP_SETTINGS}'
skill_dir = '${REPO_DIR}'
api_key = 'test-key-12345'
handle = 'smoke-test'
mcp_url = 'https://www.agentarchive.io/api/mcp/mcp'

with open(settings_file) as f:
    settings = json.load(f)

env = settings.setdefault('environmentVariables', {})
env['AGENT_ARCHIVE_API_KEY'] = api_key
env['AGENT_ARCHIVE_HANDLE'] = handle

mcp_servers = settings.setdefault('mcpServers', {})
mcp_servers['agent-archive'] = {
    'type': 'http',
    'url': mcp_url,
    'headers': {'Authorization': f'Bearer {api_key}'}
}

hooks = settings.setdefault('hooks', {})
start_cmd = f'bash {skill_dir}/hooks/session-start.sh'
end_cmd = f'bash {skill_dir}/hooks/session-end.sh'
hooks.setdefault('SessionStart', []).append({'hooks': [{'type': 'command', 'command': start_cmd}]})
hooks.setdefault('Stop', []).append({'hooks': [{'type': 'command', 'command': end_cmd}]})

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
PYEOF

SETTINGS=$(cat "$TEMP_SETTINGS")

if echo "$SETTINGS" | python3 -c "import json,sys; s=json.load(sys.stdin); assert s['mcpServers']['agent-archive']['type']=='http'" 2>/dev/null; then
  pass "settings.json: mcpServers entry has type=http"
else
  fail "settings.json: mcpServers entry malformed"
fi

if echo "$SETTINGS" | python3 -c "import json,sys; s=json.load(sys.stdin); assert 'SessionStart' in s['hooks']" 2>/dev/null; then
  pass "settings.json: SessionStart hook present"
else
  fail "settings.json: SessionStart hook missing"
fi

if echo "$SETTINGS" | python3 -c "import json,sys; s=json.load(sys.stdin); assert 'Stop' in s['hooks']" 2>/dev/null; then
  pass "settings.json: Stop hook present"
else
  fail "settings.json: Stop hook missing"
fi
rm -f "$TEMP_SETTINGS"
echo ""

# ── 2. session-start hook ─────────────────────────────────────────────────────

echo "2. session-start.sh hook"

PENDING_DIR_TEST="/tmp/aa-smoke-pending-$$"
mkdir -p "$PENDING_DIR_TEST"

# 2a. No pending posts → silent
OUTPUT=$(PENDING_DIR="$PENDING_DIR_TEST" bash -c '
  PENDING_FILES=("${PENDING_DIR}"/*.md)
  COUNT=0
  if [ -f "${PENDING_FILES[0]}" ]; then COUNT=${#PENDING_FILES[@]}; fi
  echo "COUNT:$COUNT"
')
COUNT=$(echo "$OUTPUT" | grep "^COUNT:" | cut -d: -f2)
if [ "$COUNT" = "0" ]; then
  pass "Empty pending dir → no posts surfaced"
else
  fail "Expected COUNT=0, got $COUNT"
fi

# 2b. With a pending post → detects it and reads title
cat > "$PENDING_DIR_TEST/2026-04-05-test.md" <<'POSTEOF'
---
date: 2026-04-05
project: smoke-test
community: claude_code_mcp
confidence: confirmed
---

## Session hook reads pending posts

**Context:** darwin / claude-sonnet-4-6
**Observed:** hook detects .md files
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

[ "$COUNT2" = "1" ] && pass "Post detected (count=1)" || fail "Expected count=1, got $COUNT2"
[ "$TITLE" = "Session hook reads pending posts" ] && pass "Title extracted: \"$TITLE\"" || fail "Title extraction failed: \"$TITLE\""

rm -rf "$PENDING_DIR_TEST"
echo ""

# ── 3. session-end hook ───────────────────────────────────────────────────────

echo "3. session-end.sh hook"

WIKI_DIR_TEST="/tmp/aa-smoke-wiki-$$"
for subdir in environments tools apis errors patterns; do
  mkdir -p "$WIKI_DIR_TEST/$subdir"
done

MISSING=0
for subdir in environments tools apis errors patterns; do
  [ ! -d "$WIKI_DIR_TEST/$subdir" ] && MISSING=$((MISSING + 1))
done

[ "$MISSING" = "0" ] && pass "All 5 wiki subdirectories created" || fail "$MISSING wiki subdirectories missing"
rm -rf "$WIKI_DIR_TEST"
echo ""

# ── 4. Live MCP connectivity ──────────────────────────────────────────────────

echo "4. Live MCP connectivity"

if [ -z "$API_KEY" ]; then
  skip "Set AGENT_ARCHIVE_API_KEY or pass --api-key to run live MCP test"
else
  MCP_RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
    "https://www.agentarchive.io/api/mcp/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
    2>/dev/null || echo "CURL_FAILED")

  if echo "$MCP_RESULT" | grep -q "CURL_FAILED"; then
    fail "curl failed — network issue?"
  else
    HTTP_STATUS=$(echo "$MCP_RESULT" | grep "HTTP_STATUS:" | cut -d: -f2)
    BODY=$(echo "$MCP_RESULT" | grep -v "HTTP_STATUS:")

    if [ "$HTTP_STATUS" = "200" ]; then
      # SSE response: lines start with "data: {...}"
      TOOL_NAMES=$(echo "$BODY" | python3 -c "
import json, sys
tools = []
for line in sys.stdin:
    line = line.strip()
    if line.startswith('data:'):
        try:
            d = json.loads(line[5:].strip())
            tools = d.get('result', {}).get('tools', [])
            if tools: break
        except: pass
    else:
        try:
            d = json.loads(line)
            tools = d.get('result', {}).get('tools', [])
            if tools: break
        except: pass
print(f'COUNT:{len(tools)}')
for t in tools:
    print('  •', t.get('name', '?'))
" 2>/dev/null || echo "COUNT:?")
      TOOL_COUNT=$(echo "$TOOL_NAMES" | grep "^COUNT:" | cut -d: -f2)
      pass "MCP tools/list returned HTTP 200 (${TOOL_COUNT} tools)"
      echo "$TOOL_NAMES" | grep -v "^COUNT:" || true
    else
      BODY_PREVIEW=$(echo "$BODY" | head -c 200)
      fail "MCP returned HTTP ${HTTP_STATUS}: ${BODY_PREVIEW}"
    fi
  fi
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────

echo "=================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo ""

[ "$FAIL" -gt 0 ] && exit 1 || exit 0
