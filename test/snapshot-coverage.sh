#!/usr/bin/env bash
# Runs smoke tests and records pass/fail/skip to coverage-history.json
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
HISTORY_FILE="${REPO_DIR}/coverage-history.json"

# Run smoke test and capture output
OUTPUT=$(bash "${SCRIPT_DIR}/smoke.sh" 2>&1 || true)

# Parse results line: "Results: X passed, Y failed, Z skipped"
RESULTS_LINE=$(echo "$OUTPUT" | grep "^Results:")
PASSED=$(echo "$RESULTS_LINE" | grep -oP '\d+ passed' | grep -oP '\d+')
FAILED=$(echo "$RESULTS_LINE" | grep -oP '\d+ failed' | grep -oP '\d+')
SKIPPED=$(echo "$RESULTS_LINE" | grep -oP '\d+ skipped' | grep -oP '\d+')

TOTAL=$((PASSED + FAILED + SKIPPED))
if [ "$TOTAL" -gt 0 ]; then
  PCT=$(python3 -c "print(round($PASSED / ($PASSED + $FAILED) * 100, 2) if ($PASSED + $FAILED) > 0 else 0)")
else
  PCT=0
fi

TIMESTAMP=$(python3 -c "import datetime; print(datetime.datetime.utcnow().isoformat() + 'Z')")

SNAPSHOT="{\"timestamp\":\"${TIMESTAMP}\",\"repo\":\"claude-code-agent-archive\",\"type\":\"smoke\",\"passed\":${PASSED:-0},\"failed\":${FAILED:-0},\"skipped\":${SKIPPED:-0},\"pass_rate_pct\":${PCT}}"

# Append to history
if [ -f "$HISTORY_FILE" ]; then
  python3 -c "
import json
with open('${HISTORY_FILE}') as f:
    history = json.load(f)
history.append(json.loads('${SNAPSHOT}'))
with open('${HISTORY_FILE}', 'w') as f:
    json.dump(history, f, indent=2)
    f.write('\n')
"
else
  python3 -c "
import json
with open('${HISTORY_FILE}', 'w') as f:
    json.dump([json.loads('${SNAPSHOT}')], f, indent=2)
    f.write('\n')
"
fi

echo ""
echo "Smoke test snapshot saved to coverage-history.json"
echo "  Passed: ${PASSED:-0}, Failed: ${FAILED:-0}, Skipped: ${SKIPPED:-0}"
echo "  Pass rate: ${PCT}%"
