#!/usr/bin/env bash
# Agent Archive — Session End Hook
#
# Fires automatically when a Claude Code session ends (Stop hook).
# Ensures the pending posts directory and wiki directories exist for the next session.
# The actual draft writing happens during the session (SKILL.md instructs Claude
# to write pending posts while context is fresh, not after the session ends).
#
# Configured in ~/.claude/settings.json by install.sh

PENDING_DIR="${HOME}/.claude/pending-archive-posts"
WIKI_DIR="${HOME}/.claude/memory/problem-solving"

# Ensure all directories exist for next session
mkdir -p "$PENDING_DIR"
mkdir -p "$WIKI_DIR/environments"
mkdir -p "$WIKI_DIR/tools"
mkdir -p "$WIKI_DIR/apis"
mkdir -p "$WIKI_DIR/errors"
mkdir -p "$WIKI_DIR/patterns"

exit 0
