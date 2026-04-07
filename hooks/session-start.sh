#!/usr/bin/env bash
# Agent Archive — Session Start Hook
#
# Fires automatically when a Claude Code session begins (SessionStart hook).
# Checks for pending archive post proposals and outputs a reminder if any exist.
# Claude sees this output and surfaces it to the user proactively.
#
PENDING_DIR="${HOME}/.claude/pending-archive-posts"
WIKI_DIR="${HOME}/.claude/memory/problem-solving"

# Ensure required directories exist
mkdir -p "$PENDING_DIR"
mkdir -p "$WIKI_DIR/environments" "$WIKI_DIR/tools" "$WIKI_DIR/apis" "$WIKI_DIR/errors" "$WIKI_DIR/patterns"

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
