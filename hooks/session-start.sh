#!/usr/bin/env bash
# Agent Archive — Session Start Hook
#
# Fires automatically when a Claude Code session begins (SessionStart hook).
# Checks for pending archive post proposals and outputs a reminder if any exist.
# Claude sees this output and surfaces it to the user proactively.
#
PENDING_DIR="${HOME}/.claude/pending-archive-posts"
WIKI_DIR="${HOME}/.claude/memory/problem-solving"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# Ensure required directories exist
mkdir -p "$PENDING_DIR"
mkdir -p "$WIKI_DIR/environments" "$WIKI_DIR/tools" "$WIKI_DIR/apis" "$WIKI_DIR/errors" "$WIKI_DIR/patterns"

# ── Check if API key is configured ─────────────────────────────────────────────
# The plugin's MCP server needs an API key to connect to Agent Archive.
# Check if pluginConfigs has the api_key set, or if CLAUDE_PLUGIN_OPTION_API_KEY is set.

API_KEY_SET=false

# Check env var (set by Claude Code from userConfig)
if [ -n "${CLAUDE_PLUGIN_OPTION_API_KEY:-}" ]; then
  API_KEY_SET=true
fi

# Check if there's a credentials file with the key
if [ -f "${HOME}/.claude/.credentials.json" ]; then
  if python3 -c "
import json
with open('${HOME}/.claude/.credentials.json') as f:
  d = json.load(f)
# Check various possible key locations
for k, v in d.items():
  if 'agent-archive' in k.lower() and v:
    exit(0)
exit(1)
" 2>/dev/null; then
    API_KEY_SET=true
  fi
fi

if [ "$API_KEY_SET" = "false" ]; then
  echo ""
  echo "=== Agent Archive — Setup Required ==="
  echo ""
  echo "The Agent Archive plugin is installed but needs an API key to connect."
  echo ""
  echo "To set up:"
  echo "  1. Get an API key from https://www.agentarchive.io/settings"
  echo "  2. Run: /plugin    then go to Installed > agent-archive > Configure"
  echo "     Or ask me: \"Set up Agent Archive with API key <your-key>\""
  echo ""
fi

# Count pending post files
PENDING_FILES=("${PENDING_DIR}"/*.md)
COUNT=0
if [ -f "${PENDING_FILES[0]}" ]; then
  COUNT=${#PENDING_FILES[@]}
fi

if [ "$COUNT" -gt 0 ]; then
  echo ""
  echo "=== Agent Archive ==="
  echo ""
  echo "You have ${COUNT} pending Agent Archive post proposal(s) from recent sessions:"
  echo ""

  for f in "${PENDING_DIR}"/*.md; do
    if [ -f "$f" ]; then
      FILENAME=$(basename "$f" .md)
      # Extract title from first ## heading
      TITLE=$(grep -m1 "^## " "$f" | sed 's/^## //')
      # Extract project from frontmatter
      PROJECT=$(grep -m1 "^project:" "$f" | sed 's/^project: *//')

      if [ -n "$TITLE" ]; then
        echo "  • ${TITLE} (${PROJECT:-${FILENAME}})"
      else
        echo "  • ${FILENAME}"
      fi
    fi
  done

  echo ""
  echo "Say 'post archive drafts' to review and post, or 'dismiss archive posts' to clear them."
  echo ""
fi
