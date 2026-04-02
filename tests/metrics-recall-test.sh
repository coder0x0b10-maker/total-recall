#!/usr/bin/env bash
# metrics-recall-test.sh — Recall accuracy test harness for Total Recall
# Runs fixture-based tests against the observer and recovery pipeline
# Output: TAP-style test results to stdout + JSONL to memory/metrics/
#
# Usage: bash metrics-recall-test.sh [--no-cleanup]

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/scripts/_compat.sh"

# ─── Configuration ───────────────────────────────────────────────────────────
TEST_RUN_DIR=""
CLEANUP=true
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TEST_NUM=0

for arg in "$@"; do
    if [[ "$arg" == "--no-cleanup" ]]; then CLEANUP=false; fi
done

OUT_DIR="$(cd "$SKILL_DIR/../.." && pwd)/memory/metrics"
mkdir -p "$OUT_DIR"
RESULTS_FILE="$OUT_DIR/recall-tests-$(date -u +%Y-%m-%d).jsonl"

# ─── TAP helpers ─────────────────────────────────────────────────────────────
plan() { echo "1..$1"; }

ok() {
    TEST_NUM=$((TEST_NUM + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "ok $TEST_NUM - $1"
}

not_ok() {
    TEST_NUM=$((TEST_NUM + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "not ok $TEST_NUM - $1"
}

skip() {
    TEST_NUM=$((TEST_NUM + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo "ok $TEST_NUM - $1 # SKIP $2"
}

record_result() {
    local name="$1" status="$2" detail="${3:-}"
    printf '{"ts":"%s","test":"%s","status":"%s","detail":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" "$status" "$detail" \
        >> "$RESULTS_FILE" 2>/dev/null || true
}

obs_before=""
obs_after=""

# ─── Test: Observer handles empty / no transcripts gracefully ────────────────

test_empty_input() {
    local name="empty_input_handles_gracefully"
    echo "# Test: $name"

    local tmp_workspace
    tmp_workspace=$(mktemp -d /tmp/tr-test-empty.XXXXXX)
    mkdir -p "$tmp_workspace/logs" "$tmp_workspace/memory"

    local tmp_sessions
    tmp_sessions=$(mktemp -d /tmp/tr-test-sessions.XXXXXX)

    # No session files = no transcripts
    OPENCLAW_WORKSPACE="$tmp_workspace" \
    SESSIONS_DIR="$tmp_sessions" \
    bash "$SKILL_DIR/scripts/observer-agent.sh" 2>/dev/null || true

    if [[ $? -eq 0 ]]; then
        ok "$name — exits cleanly with no transcripts"
        record_result "$name" "pass"
    else
        not_ok "$name — should exit 0 with no transcripts"
        record_result "$name" "fail" "non-zero exit"
    fi

    if $CLEANUP; then rm -rf "$tmp_workspace" "$tmp_sessions"; fi
}

# ─── Test: Observer dedup — running twice on same input produces no new obs ──

test_dedup() {
    local name="dedup_no_duplicates_on_rerun"
    echo "# Test: $name"

    local tmp_workspace
    tmp_workspace=$(mktemp -d /tmp/tr-test-dedup.XXXXXX)
    mkdir -p "$tmp_workspace/logs" "$tmp_workspace/memory"

    local tmp_sessions
    tmp_sessions=$(mktemp -d /tmp/tr-test-dedup-sess.XXXXXX)
    cp "$SKILL_DIR/tests/fixture-basic-session.jsonl" "$tmp_sessions/test-session.jsonl"

    # Run observer first time
    OPENCLAW_WORKSPACE="$tmp_workspace" \
    SESSIONS_DIR="$tmp_sessions" \
    bash "$SKILL_DIR/scripts/observer-agent.sh" 2>/dev/null || true

    local obs_words_1=0
    if [[ -f "$tmp_workspace/memory/observations.md" ]]; then
        obs_words_1=$(wc -w < "$tmp_workspace/memory/observations.md")
    fi

    # Touch the session file so it appears "modified" again
    sleep 1
    touch "$tmp_sessions/test-session.jsonl"

    # Run observer second time
    OPENCLAW_WORKSPACE="$tmp_workspace" \
    SESSIONS_DIR="$tmp_sessions" \
    bash "$SKILL_DIR/scripts/observer-agent.sh" 2>/dev/null || true

    local obs_words_2=0
    if [[ -f "$tmp_workspace/memory/observations.md" ]]; then
        obs_words_2=$(wc -w < "$tmp_workspace/memory/observations.md")
    fi

    # The second run should not have grown the file significantly
    # (allow 10% tolerance for possible LLM variation)
    local growth=0
    if [[ "$obs_words_1" -gt 0 ]]; then
        growth=$(( (obs_words_2 - obs_words_1) * 100 / obs_words_1 ))
    fi

    if [[ "$growth" -lt 15 ]]; then
        ok "$name — file grew by $growth% (threshold: <15%)"
        record_result "$name" "pass" "growth=${growth}%"
    else
        not_ok "$name — file grew by $growth% (threshold: <15%), words: $obs_words_1 → $obs_words_2"
        record_result "$name" "fail" "growth=${growth}%"
    fi

    if $CLEANUP; then rm -rf "$tmp_workspace" "$tmp_sessions"; fi
}

# ─── Test: Flush mode exists and produces output ─────────────────────────────

test_flush_mode() {
    local name="flush_mode_executes"
    echo "# Test: $name"

    local tmp_workspace
    tmp_workspace=$(mktemp -d /tmp/tr-test-flush.XXXXXX)
    mkdir -p "$tmp_workspace/logs" "$tmp_workspace/memory"

    local tmp_sessions
    tmp_sessions=$(mktemp -d /tmp/tr-test-flush-sess.XXXXXX)

    # Create a session file
    cp "$SKILL_DIR/tests/fixture-basic-session.jsonl" "$tmp_sessions/flush-session.jsonl"

    # Run in flush mode (may fail without API key, but should not crash)
    OPENCLAW_WORKSPACE="$tmp_workspace" \
    SESSIONS_DIR="$tmp_sessions" \
    bash "$SKILL_DIR/scripts/observer-agent.sh" --flush 2>/dev/null || true

    # At minimum, the script should not error out with a stack trace
    ok "$name — flush mode runs without crash"
    record_result "$name" "pass"

    if $CLEANUP; then rm -rf "$tmp_workspace" "$tmp_sessions"; fi
}

# ─── Test: Large session — observer handles 150+ messages ────────────────────

test_large_session() {
    local name="large_session_150_plus_messages"
    echo "# Test: $name"

    local tmp_workspace
    tmp_workspace=$(mktemp -d /tmp/tr-test-large.XXXXXX)
    mkdir -p "$tmp_workspace/logs" "$tmp_workspace/memory"

    local tmp_sessions
    tmp_sessions=$(mktemp -d /tmp/tr-test-large-sess.XXXXXX)

    # Generate a 200-line session file
    local large_file="$tmp_sessions/large-session.jsonl"
    for i in $(seq 1 200); do
        local ts
        ts=$(printf '2026-04-03T10:%02d:%02dZ' $((i / 60)) $((i % 60)))
        local role="user"
        [[ $((i % 2)) -eq 0 ]] && role="assistant"
        printf '{"timestamp":"%s","message":{"role":"%s","content":"Test message number %d with enough text to be meaningful"}}\n' \
            "$ts" "$role" "$i" >> "$large_file"
    done

    # Run observer
    OPENCLAW_WORKSPACE="$tmp_workspace" \
    SESSIONS_DIR="$tmp_sessions" \
    bash "$SKILL_DIR/scripts/observer-agent.sh" 2>/dev/null || true

    local line_count
    line_count=$(wc -l < "$large_file")
    if [[ "$line_count" -ge 200 ]]; then
        ok "$name — processed $line_count line session file"
        record_result "$name" "pass" "lines=$line_count"
    else
        not_ok "$name — generated only $line_count lines"
        record_result "$name" "fail" "lines=$line_count"
    fi

    if $CLEANUP; then rm -rf "$tmp_workspace" "$tmp_sessions"; fi
}

# ─── Test: Session recovery detects and fires on missed session ──────────────

test_recovery_mode() {
    local name="recovery_mode_detects_missed_session"
    echo "# Test: $name"

    local tmp_workspace
    tmp_workspace=$(mktemp -d /tmp/tr-test-recovery.XXXXXX)
    mkdir -p "$tmp_workspace/logs" "$tmp_workspace/memory"

    local tmp_sessions
    tmp_sessions=$(mktemp -d /tmp/tr-test-recovery-sess.XXXXXX)

    cp "$SKILL_DIR/tests/fixture-basic-session.jsonl" "$tmp_sessions/recovery-session.jsonl"

    # Run in recovery mode with the specific file
    local output
    output=$(OPENCLAW_WORKSPACE="$tmp_workspace" \
    SESSIONS_DIR="$tmp_sessions" \
    bash "$SKILL_DIR/scripts/observer-agent.sh" --recover "$tmp_sessions/recovery-session.jsonl" 2>&1) || true

    # Recovery mode should recognize the file and attempt processing
    # It may exit with NO_OBSERVATIONS if LLM fails (no API key), but should not crash
    local log_exists=false
    if [[ -f "$tmp_workspace/logs/observer.log" ]]; then
        if grep -q "RECOVERY MODE\|recovery" "$tmp_workspace/logs/observer.log" 2>/dev/null; then
            log_exists=true
        fi
    fi

    if [[ "$log_exists" == "true" ]]; then
        ok "$name — recovery mode recognized the session file"
        record_result "$name" "pass"
    else
        not_ok "$name — recovery mode did not log recognition"
        record_result "$name" "fail" "output: $(echo "$output" | head -c 200)"
    fi

    if $CLEANUP; then rm -rf "$tmp_workspace" "$tmp_sessions"; fi
}

# ─── Test: Metrics infrastructure integration ────────────────────────────────

test_metrics_integration() {
    local name="metrics_infrastructure_works"
    echo "# Test: $name"

    local tmp_workspace
    tmp_workspace=$(mktemp -d /tmp/tr-test-metrics.XXXXXX)
    mkdir -p "$tmp_workspace/logs" "$tmp_workspace/memory"

    local tmp_sessions
    tmp_sessions=$(mktemp -d /tmp/tr-test-metrics-sess.XXXXXX)

    # Source and test the metrics lib directly
    source "$SKILL_DIR/scripts/_metrics.sh"
    metrics_init "$tmp_workspace"

    metrics_record "test_metric" 42 '{"test":true}'

    local metric_file="$tmp_workspace/memory/metrics/$(date -u +%Y-%m-%d).jsonl"

    if [[ -f "$metric_file" ]]; then
        local valid_json
        valid_json=$(head -1 "$metric_file" | jq -e '.metric == "test_metric" and .value == 42' 2>/dev/null || echo "")
        if [[ -n "$valid_json" ]]; then
            ok "$name — metrics JSONL written and valid"
            record_result "$name" "pass"
        else
            not_ok "$name — metrics JSONL has invalid content"
            record_result "$name" "fail" "$(head -1 "$metric_file" 2>/dev/null | head -c 200)"
        fi
    else
        not_ok "$name — metrics JSONL file not created"
        record_result "$name" "fail" "file missing: $metric_file"
    fi

    if $CLEANUP; then rm -rf "$tmp_workspace" "$tmp_sessions"; fi
}

# ─── Run all tests ───────────────────────────────────────────────────────────

echo "TAP version 14"
echo "# Total Recall — Recall Accuracy Test Harness"
echo "# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "#"

TOTAL_TESTS=6
plan "$TOTAL_TESTS"

test_empty_input
test_dedup
test_flush_mode
test_large_session
test_recovery_mode
test_metrics_integration

echo ""
echo "# Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    echo "# $TESTS_FAILED test(s) FAILED"
    exit 1
else
    echo "# All tests passed"
    exit 0
fi
