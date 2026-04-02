# _metrics.sh — Centralized metrics collector for Total Recall pipeline
# Sourced by agents, never executed directly.
# Writes JSONL to $WORKSPACE/memory/metrics/YYYY-MM-DD.jsonl
#
# Functions:
#   _metrics_init              — ensure metrics directory exists
#   _metrics_record <metric> [value] [extra_json]
#   _time_now_ms               — portable millisecond timestamp
#   _stage_start <label>       — begin timing a stage
#   _stage_end <label> [extra_json] — end timing, writes latency metric
#   _metrics_flush <component> [extra_json] — end-of-run summary

_METRICS_COMPONENT="${_METRICS_COMPONENT:-unknown}"

# ─── Portable millisecond timestamp ─────────────────────────────────────────
# GNU date: %s%3N → 1709500000123
# macOS date: %s%3N → literal %3N suffix, so we multiply epoch by 1000

time_now_ms() {
    local raw
    raw="$(date +%s%3N 2>/dev/null || true)"
    if [[ "$raw" =~ ^[0-9]{13}$ ]]; then
        printf '%s' "$raw"
    else
        # Fallback: epoch seconds * 1000 (lower precision)
        printf '%d' $(( $(date +%s) * 1000 ))
    fi
}

# ─── Internal helpers ─────────────────────────────────────────────────────────

_metrics_dir() {
    printf '%s' "${_METRICS_DIR:-${_METRICS_WORKSPACE:-.}/memory/metrics}"
}

_metrics_file() {
    printf '%s/%s.jsonl' "$(_metrics_dir)" "$(date -u +%Y-%m-%d)"
}

# Sanitize a string for safe JSON embedding (escape backslash, quote, control chars)
_json_safe() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\r\n'
}

# ─── Public API ───────────────────────────────────────────────────────────────

# Initialize metrics infrastructure. Call once per agent startup.
# Accepts optional workspace path; defaults to $WORKSPACE or current dir.
metrics_init() {
    local ws="${1:-${WORKSPACE:-.}}"
    _METRICS_WORKSPACE="$ws"
    # Derive component name from the sourcing script filename
    if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
        _METRICS_COMPONENT="$(basename "${BASH_SOURCE[1]}" | sed 's/\.sh$//')"
    fi
    mkdir -p "$(_metrics_dir)"
}

# Record a single metric value.
# Usage: metrics_record <metric_name> [value] [extra_json]
#   metric_name — e.g. "llm_latency_ms", "words_before"
#   value       — numeric value (default: 0)
#   extra_json  — optional JSON object string for context fields
#
# Examples:
#   metrics_record "llm_latency_ms" 3200 '{"model":"gemini-2.5-flash","attempt":1,"status":"ok"}'
#   metrics_record "reflector_reduction_pct" 45
metrics_record() {
    local metric="${1:-}"
    local value="${2:-0}"
    local extra="${3:-}"

    [[ -z "$metric" ]] && return

    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local extra_field="null"
    if [[ -n "$extra" ]]; then
        # Validate extra is valid JSON object
        if printf '%s' "$extra" | jq -e 'type == "object"' >/dev/null 2>&1; then
            extra_field="$extra"
        else
            extra_field="{\"detail\":\"$(_json_safe "$extra")\"}"
        fi
    fi

    printf '{"ts":"%s","component":"%s","metric":"%s","value":%s,"extra":%s}\n' \
        "$ts" "$_METRICS_COMPONENT" "$metric" "$value" "$extra_field" \
        >> "$(_metrics_file)" 2>/dev/null || true
}

# Begin timing a named stage. Call _stage_end with the same label to record latency.
# Usage: stage_start <label>
stage_start() {
    local label="$1"
    local var="_ms_${label//[^a-zA-Z0-9_]/_}"
    eval "$var=$(time_now_ms)"
}

# End timing a named stage. Records a latency_ms metric.
# Usage: stage_end <label> [extra_json]
#   extra_json — optional JSON for additional fields (e.g. model, attempt)
stage_end() {
    local label="${1:-}"
    local extra="${2:-}"
    [[ -z "$label" ]] && return

    local var="_ms_${label//[^a-zA-Z0-9_]/_}"
    local end_ms
    end_ms="$(time_now_ms)"

    eval local start_ms=\${$var:-$end_ms}

    local latency=$(( end_ms - start_ms ))
    [[ $latency -lt 0 ]] && latency=0

    # Build merged extra with stage label
    local merged_extra
    if [[ -n "$extra" ]] && printf '%s' "$extra" | jq -e 'type == "object"' >/dev/null 2>&1; then
        merged_extra="$(printf '%s' "$extra" | jq -c --arg s "$label" '. + {stage: $s}')"
    else
        merged_extra="{\"stage\":\"$(_json_safe "$label")\"}"
    fi

    metrics_record "latency_ms" "$latency" "$merged_extra"

    # Clean up timer variable
    eval "unset $var"
}

# End-of-run summary for the current component.
# Call once per agent execution, after all work is done.
# Usage: metrics_flush [extra_json]
#   extra_json — any final context fields (e.g. total_observations, status)
metrics_flush() {
    local extra="${1:-}"
    local merged_extra
    if [[ -n "$extra" ]] && printf '%s' "$extra" | jq -e 'type == "object"' >/dev/null 2>&1; then
        merged_extra="$extra"
    else
        merged_extra="{}"
    fi
    metrics_record "run_complete" 1 "$merged_extra"
}
