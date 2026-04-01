#!/usr/bin/env bash
# Session Recovery — catches missed sessions on /new or /reset
# Part of Total Recall skill

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/scripts/_compat.sh"

WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_DIR/../.." && pwd)}"
MEMORY_DIR="${MEMORY_DIR:-$WORKSPACE/memory}"
SESSIONS_DIR="${SESSIONS_DIR:-$HOME/.openclaw/agents/main/sessions}"
HASH_FILE="$MEMORY_DIR/.observer-last-hash"
RECOVERY_LOG="$WORKSPACE/logs/session-recovery.log"

mkdir -p "$WORKSPACE/logs"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$RECOVERY_LOG"
}

log "Session recovery check starting"

# Find most recent session file by modification time (filter out subagent/cron/topic)
LAST_SESSION=""
while IFS= read -r f; do
  BASENAME=$(basename "$f" .jsonl)
  if echo "$BASENAME" | grep -qE "(topic|subagent|cron)"; then
    continue
  fi
  LAST_SESSION="$f"
  break
done < <(find "$SESSIONS_DIR" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null | xargs ls -1t 2>/dev/null)

if [ -z "$LAST_SESSION" ]; then
  log "No main session files found"
  exit 0
fi

# Check if session was already observed using timestamp comparison
# instead of hash (which is unreliable due to different filtering)
MARKER_FILE="$MEMORY_DIR/.observer-last-run"
if [ -f "$MARKER_FILE" ]; then
  LAST_OBSERVER_RUN=$(cat "$MARKER_FILE" 2>/dev/null || echo 0)
  SESSION_MTIME=$(stat -c %Y "$LAST_SESSION" 2>/dev/null || echo 0)
  # If session file is not newer than the last observer update, skip
  if [ "$SESSION_MTIME" -le "$LAST_OBSERVER_RUN" ]; then
    log "Session already observed (session mtime <= last observer run). Skipping."
    exit 0
  fi
fi

log "Unobserved session detected: $(basename "$LAST_SESSION")"
log "Triggering emergency observer capture..."

bash "$SKILL_DIR/scripts/observer-agent.sh" --recover "$LAST_SESSION" >/dev/null 2>&1 || {
  log "Observer recovery failed, skipping (will retry later)"
}

log "Session recovery complete"
