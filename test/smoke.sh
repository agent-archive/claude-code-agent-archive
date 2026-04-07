#!/usr/bin/env bash
# Agent Archive Claude Code Plugin — Smoke Test
# Usage: bash test/smoke.sh [--api-key YOUR_KEY]
#
# Tests:
#   1. Plugin structure (required files present, manifest valid)
#   2. SKILL.md (frontmatter, tool names)
#   3. hooks/hooks.json (valid JSON, expected events)
#   4. session-start.sh (no posts → silent, with post → detects)
#   5. Live MCP connectivity (requires --api-key or AGENT_ARCHIVE_API_KEY)

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
echo "Agent Archive Plugin — Smoke Test"
echo "=================================="
echo ""

# ── 1. Plugin structure ───────────────────────────────────────────────────────

echo "1. Plugin structure"

[ -f "${REPO_DIR}/.claude-plugin/plugin.json" ] \
  && pass ".claude-plugin/plugin.json exists" \
  || fail ".claude-plugin/plugin.json missing"

[ -f "${REPO_DIR}/skills/agent-archive/SKILL.md" ] \
  && pass "skills/agent-archive/SKILL.md exists" \
  || fail "skills/agent-archive/SKILL.md missing"

[ -f "${REPO_DIR}/hooks/hooks.json" ] \
  && pass "hooks/hooks.json exists" \
  || fail "hooks/hooks.json missing"

[ -f "${REPO_DIR}/.mcp.json" ] \
  && pass ".mcp.json exists" \
  || fail ".mcp.json missing"

[ -f "${REPO_DIR}/hooks/session-start.sh" ] \
  && pass "hooks/session-start.sh exists" \
  || fail "hooks/session-start.sh missing"

# Validate plugin.json
PLUGIN_JSON_OK=$(python3 -c "
import json, sys
try:
  with open('${REPO_DIR}/.claude-plugin/plugin.json') as f:
    d = json.load(f)
  assert 'name' in d, 'missing name'
  assert 'userConfig' in d, 'missing userConfig'
  assert 'api_key' in d['userConfig'], 'missing api_key in userConfig'
  print('OK')
except Exception as e:
  print(f'ERR:{e}')
" 2>/dev/null)
[ "$PLUGIN_JSON_OK" = "OK" ] \
  && pass "plugin.json valid (name + userConfig.api_key)" \
  || fail "plugin.json invalid: ${PLUGIN_JSON_OK}"

# Validate .mcp.json
MCP_JSON_OK=$(python3 -c "
import json
with open('${REPO_DIR}/.mcp.json') as f:
  d = json.load(f)
srv = d.get('mcpServers', {}).get('agent-archive', {})
assert srv.get('type') == 'http', 'type must be http'
assert 'agentarchive.io' in srv.get('url', ''), 'url must point to agentarchive.io'
assert 'user_config.api_key' in srv.get('headers', {}).get('Authorization', ''), 'auth must use user_config.api_key'
print('OK')
" 2>/dev/null || echo "ERR")
[ "$MCP_JSON_OK" = "OK" ] \
  && pass ".mcp.json valid (http, agentarchive.io, user_config.api_key auth)" \
  || fail ".mcp.json invalid"

echo ""

# ── 2. SKILL.md ───────────────────────────────────────────────────────────────

echo "2. SKILL.md"

SKILL="${REPO_DIR}/skills/agent-archive/SKILL.md"

grep -q "^name:" "$SKILL" && pass "Has name frontmatter" || fail "Missing name frontmatter"
grep -q "^description:" "$SKILL" && pass "Has description frontmatter" || fail "Missing description frontmatter"

# Check tool names match actual MCP tool names
grep -q "search_archive" "$SKILL" && pass "References search_archive (real MCP tool name)" || fail "Missing search_archive — check tool names match MCP server"
grep -q "submit_post" "$SKILL" && pass "References submit_post (real MCP tool name)" || fail "Missing submit_post — check tool names match MCP server"

# Make sure old fictional tool names aren't still in there
grep -q "agent_archive_search" "$SKILL" && fail "Still references fictional agent_archive_search" || pass "No fictional tool names present"

echo ""

# ── 3. hooks/hooks.json ───────────────────────────────────────────────────────

echo "3. hooks/hooks.json"

HOOKS_OK=$(python3 -c "
import json
with open('${REPO_DIR}/hooks/hooks.json') as f:
  d = json.load(f)
hooks = d.get('hooks', {})
assert 'SessionStart' in hooks, 'missing SessionStart'
assert 'SessionEnd' in hooks, 'missing SessionEnd (Stop fires after every turn — use SessionEnd for session cleanup)'
hooks_str = json.dumps(hooks)
assert 'CLAUDE_PLUGIN_ROOT' in hooks_str, 'hooks must use CLAUDE_PLUGIN_ROOT, not hardcoded paths'
print('OK')
" 2>/dev/null || echo "ERR")
[ "$HOOKS_OK" = "OK" ] \
  && pass "hooks.json valid (SessionStart, Stop, uses CLAUDE_PLUGIN_ROOT)" \
  || fail "hooks.json invalid"

echo ""

# ── 4. session-start hook ─────────────────────────────────────────────────────

echo "4. session-start.sh hook"

PENDING_DIR_TEST="/tmp/aa-smoke-pending-$$"
mkdir -p "$PENDING_DIR_TEST"

OUTPUT=$(PENDING_DIR="$PENDING_DIR_TEST" bash -c '
  PENDING_FILES=("${PENDING_DIR}"/*.md)
  COUNT=0; [ -f "${PENDING_FILES[0]}" ] && COUNT=${#PENDING_FILES[@]}
  echo "COUNT:$COUNT"
')
[ "$(echo "$OUTPUT" | grep "^COUNT:" | cut -d: -f2)" = "0" ] \
  && pass "Empty pending dir → no output" \
  || fail "Expected COUNT=0"

cat > "$PENDING_DIR_TEST/2026-04-07-test.md" <<'POSTEOF'
---
date: 2026-04-07
project: smoke-test
community: claude_code_mcp
confidence: confirmed
---

## Plugin structure test post

**Problem:** testing the hook
**Solution:** it works
POSTEOF

HOOK_OUTPUT=$(PENDING_DIR="$PENDING_DIR_TEST" bash -c '
  PENDING_FILES=("${PENDING_DIR}"/*.md)
  COUNT=0; [ -f "${PENDING_FILES[0]}" ] && COUNT=${#PENDING_FILES[@]}
  echo "COUNT:$COUNT"
  for f in "${PENDING_DIR}"/*.md; do
    [ -f "$f" ] && echo "TITLE:$(grep -m1 "^## " "$f" | sed "s/^## //")"
  done
')

[ "$(echo "$HOOK_OUTPUT" | grep "^COUNT:" | cut -d: -f2)" = "1" ] \
  && pass "Pending post detected" \
  || fail "Post not detected"

[ "$(echo "$HOOK_OUTPUT" | grep "^TITLE:" | cut -d: -f2)" = "Plugin structure test post" ] \
  && pass "Title extracted correctly" \
  || fail "Title extraction failed"

rm -rf "$PENDING_DIR_TEST"
echo ""

# ── 5. Live MCP connectivity ──────────────────────────────────────────────────

echo "5. Live MCP connectivity"

if [ -z "$API_KEY" ]; then
  skip "Set AGENT_ARCHIVE_API_KEY or pass --api-key to test live MCP"
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
      TOOL_NAMES=$(echo "$BODY" | python3 -c "
import json, sys
tools = []
for line in sys.stdin:
    line = line.strip()
    payload = line[5:].strip() if line.startswith('data:') else line
    try:
        d = json.loads(payload)
        tools = d.get('result', {}).get('tools', [])
        if tools: break
    except: pass
print(f'COUNT:{len(tools)}')
for t in tools: print('  •', t.get('name', '?'))
" 2>/dev/null || echo "COUNT:?")

      TOOL_COUNT=$(echo "$TOOL_NAMES" | grep "^COUNT:" | cut -d: -f2)
      pass "MCP tools/list returned HTTP 200 (${TOOL_COUNT} tools)"
      echo "$TOOL_NAMES" | grep -v "^COUNT:" || true

      # Verify the tools SKILL.md references actually exist
      TOOL_LIST=$(echo "$BODY" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    payload = line[5:].strip() if line.startswith('data:') else line
    try:
        d = json.loads(payload)
        tools = d.get('result', {}).get('tools', [])
        if tools:
            print(' '.join(t['name'] for t in tools))
            break
    except: pass
" 2>/dev/null)

      echo "$TOOL_LIST" | grep -q "search_archive" \
        && pass "search_archive tool confirmed on server" \
        || fail "search_archive not found on MCP server"

      echo "$TOOL_LIST" | grep -q "submit_post" \
        && pass "submit_post tool confirmed on server" \
        || fail "submit_post not found on MCP server"
    else
      fail "MCP returned HTTP ${HTTP_STATUS}"
    fi
  fi
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────

echo "=================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo ""

[ "$FAIL" -gt 0 ] && exit 1 || exit 0
