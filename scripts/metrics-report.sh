#!/usr/bin/env bash
# metrics-report.sh — Daily summary report generator for Total Recall pipeline
# Aggregates pipeline metrics, quality scores, and dream logs into a markdown dashboard
# Usage: bash metrics-report.sh [--days N | --week | --today]
#
# Reads:
#   memory/metrics/YYYY-MM-DD.jsonl          (pipeline performance metrics)
#   memory/metrics/quality/*.json            (quality scores)
#   memory/dream-logs/*.md                   (existing dream cycle logs)
# Outputs:
#   memory/metrics/daily-report-YYYY-MM-DD.md

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/scripts/_compat.sh"

WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_DIR/../.." && pwd)}"
METRICS_DIR="$WORKSPACE/memory/metrics"
QUALITY_DIR="$METRICS_DIR/quality"
DREAM_LOG_DIR="$WORKSPACE/memory/dream-logs"

mkdir -p "$METRICS_DIR"

# ─── Parse flags ─────────────────────────────────────────────────────────────

DAYS=1
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --today) DAYS=1; shift ;;
        --week) DAYS=7; shift ;;
        --days) DAYS="${2:-1}"; shift 2 ;;
        *) POSITIONAL_ARGS+=("$1"); shift ;;
    esac
done

END_DATE="$(date -u +%Y-%m-%d)"
START_DATE="$(date -u -d "-$((DAYS - 1)) days" +%Y-%m-%d 2>/dev/null || echo "$END_DATE")"

REPORT_FILE="$METRICS_DIR/daily-report-$(date -u +%Y-%m-%d).md"

# ─── Helpers ─────────────────────────────────────────────────────────────────

collect_metric_data() {
    local out=""
    local d
    for d in $(seq 0 $((DAYS - 1))); do
        local day_file="$METRICS_DIR/$(date -u -d "-${d} days" +%Y-%m-%d).jsonl"
        [[ -f "$day_file" ]] && cat "$day_file"
    done
}

safe_jq_count() {
    # Count matching records safely (handles empty/null input)
    local filter="${1:-.}"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | jq -r "$filter" 2>/dev/null || true
    done | grep -c '.' 2>/dev/null || echo 0
}

safe_jq_values() {
    # Extract values safely
    local filter="${1:-.}"
    echo "$METRIC_DATA" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | jq -r "$filter" 2>/dev/null || true
    done | grep -E '^[0-9.-]+$' 2>/dev/null || true
}

calc_avg() {
    local values="$1"
    [[ -z "$values" ]] && echo "—" && return
    echo "$values" | python3 -c "
import sys
vals = [float(l) for l in sys.stdin if l.strip()]
print(f'{sum(vals)/len(vals):.0f}ms' if vals else '—')
" 2>/dev/null || echo "—"
}

calc_min() {
    local values="$1"
    [[ -z "$values" ]] && echo "—" && return
    sort -n <<< "$values" | head -1
}

calc_max() {
    local values="$1"
    [[ -z "$values" ]] && echo "—" && return
    sort -n <<< "$values" | tail -1
}

calc_sum() {
    local values="$1"
    [[ -z "$values" ]] && echo 0 && return
    echo "$values" | python3 -c "import sys; print(int(sum(float(l) for l in sys.stdin)))" 2>/dev/null || echo 0
}

# ─── Collect data ────────────────────────────────────────────────────────────

METRIC_DATA="$(collect_metric_data)"

HAS_DATA=false
[[ -n "$METRIC_DATA" ]] && HAS_DATA=true

# ─── Generate report ─────────────────────────────────────────────────────────
{
echo "# Total Recall Pipeline Report"
echo ""
echo "**Period**: $START_DATE → $END_DATE ($DAYS day(s))"
echo "**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""
echo "---"
echo ""

# ── Pipeline Summary ──────────────────────────────────────────────────────
echo "## Pipeline Summary"
echo ""
echo "| Component | Runs | Avg Latency | Min | Max |"
echo "|-----------|------|-------------|-----|-----|"

if [[ "$HAS_DATA" == "true" ]]; then
    for comp in observer reflector sensor_sweep rumination preconscious; do
        run_count=$(echo "$METRIC_DATA" | jq -r 'select(.metric == "run_complete" and .component == "'$comp'") | .value' 2>/dev/null | wc -l | tr -d ' ')
        [[ "$run_count" -eq 0 ]] && continue

        latencies="$(safe_jq_values '.value | select(type == "number")')"
        avg_lat="$(calc_avg "$latencies")"
        min_lat="$(calc_min "$latencies")"
        max_lat="$(calc_max "$latencies")"

        echo "| $comp | $run_count | $avg_lat | ${min_lat}ms | ${max_lat}ms |"
    done
    echo ""

    # Check if any runs at all
    total_runs=$(echo "$METRIC_DATA" | jq -r 'select(.metric == "run_complete") | .value' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$total_runs" -eq 0 ]]; then
        echo "_No pipeline runs recorded in this period._"
        echo ""
    fi
else
    echo "_No metrics data available yet. Pipeline agents will record metrics on each run._"
    echo ""
fi

# ── Observer Detail ───────────────────────────────────────────────────────
echo "## Observer Detail"
echo ""

if [[ "$HAS_DATA" == "true" ]]; then
    obs_runs=$(echo "$METRIC_DATA" | jq -r 'select(.metric == "run_complete" and .component == "observer") | .value' 2>/dev/null | wc -l | tr -d ' ')
    transcripts=$(safe_jq_values 'select(.metric == "transcripts_found") | .value' | paste -sd+ | python3 -c "import sys; v=sys.stdin.read().strip(); print(sum(int(x) for x in v.split('+')) if v else 0)" 2>/dev/null || echo 0)
    lines_ext=$(safe_jq_values 'select(.metric == "lines_extracted") | .value' | paste -sd+ | python3 -c "import sys; v=sys.stdin.read().strip(); print(sum(int(x) for x in v.split('+')) if v else 0)" 2>/dev/null || echo 0)
    llm_ok_count=$(echo "$METRIC_DATA" | jq -r 'select(.component == "observer" and .metric == "latency_ms" and .extra.status == "ok") | .value' 2>/dev/null | wc -l | tr -d ' ')
    llm_fail_count=$(echo "$METRIC_DATA" | jq -r 'select(.component == "observer" and .metric == "latency_ms" and .extra.status == "failed") | .value' 2>/dev/null | wc -l | tr -d ' ')

    echo "- **Runs**: $obs_runs"
    echo "- **Transcripts processed**: $transcripts"
    echo "- **Lines extracted**: $lines_ext"
    echo "- **LLM calls**: $llm_ok_count succeeded, $llm_fail_count failed"

    # Model usage
    models_used=$(echo "$METRIC_DATA" | jq -r 'select(.component == "observer" and .extra.model) | .extra.model' 2>/dev/null | sort -u | head -10)
    if [[ -n "$models_used" ]]; then
        echo "- **Models used**:"
        echo "$models_used" | while IFS= read -r m; do
            [[ -n "$m" ]] && echo "  - $m"
        done
    fi
else
    echo "_No observer data._"
fi

echo ""

# ── Reflector Detail ──────────────────────────────────────────────────────
echo "## Reflector Detail"
echo ""

if [[ "$HAS_DATA" == "true" ]]; then
    ref_runs=$(echo "$METRIC_DATA" | jq -r 'select(.metric == "run_complete" and .component == "reflector") | .value' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$ref_runs" -gt 0 ]]; then
        words_before_vals=$(safe_jq_values 'select(.metric == "words_before") | .value')
        words_after_vals=$(safe_jq_values 'select(.metric == "words_after") | .value')
        red_vals=$(safe_jq_values 'select(.metric == "reduction_pct") | .value')

        wb_total=$(calc_sum "$words_before_vals")
        wa_total=$(calc_sum "$words_after_vals")
        red_avg=$(calc_avg "$red_vals")

        echo "- **Runs**: $ref_runs"
        echo "- **Total words before → after**: $wb_total → $wa_total"
        echo "- **Avg reduction**: $red_avg"
    else
        echo "- No reflection runs in this period"
    fi
else
    echo "- No reflector data. Runs automatically when observations exceed word threshold."
fi

echo ""

# ── Memory Quality ────────────────────────────────────────────────────────
echo "## Memory Quality"
echo ""

latest_quality=$(ls -1t "$QUALITY_DIR"/*.json 2>/dev/null | head -1 || true)
if [[ -n "$latest_quality" && -f "$latest_quality" ]]; then
    q_score=$(jq -r '.score // "N/A"' "$latest_quality" 2>/dev/null || echo "N/A")
    q_grade=$(jq -r '.grade // "N/A"' "$latest_quality" 2>/dev/null || echo "N/A")
    q_obs=$(jq -r '.breakdown.type_metadata.total // "N/A"' "$latest_quality" 2>/dev/null || echo "N/A")
    echo "- **Latest quality score**: $q_score/100 ($q_grade)"
    echo "- **Total observations**: $q_obs"
    echo "- **Snapshot**: $(basename "$latest_quality")"
else
    echo "- No quality data available. Run:"
    echo '  ```bash'
    echo '  bash scripts/metrics-quality.sh score'
    echo '  ```'
fi

echo ""

# ── Sensor Sweep ──────────────────────────────────────────────────────────
echo "## Sensor Sweep"
echo ""

if [[ "$HAS_DATA" == "true" ]]; then
    sweep_runs=$(echo "$METRIC_DATA" | jq -r 'select(.metric == "run_complete" and .component == "sensor_sweep") | .value' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$sweep_runs" -gt 0 ]]; then
        events_vals=$(safe_jq_values 'select(.metric == "events_emitted") | .value')
        pruned_vals=$(safe_jq_values 'select(.metric == "events_pruned") | .value')
        ev_total=$(calc_sum "$events_vals")
        pr_total=$(calc_sum "$pruned_vals")

        echo "- **Sweeps**: $sweep_runs"
        echo "- **Events emitted**: $ev_total"
        echo "- **Events pruned**: $pr_total"

        # Per-connector detail
        conn_data=$(echo "$METRIC_DATA" | jq -r 'select(.metric == "connector_duration_ms") | "\(.extra.connector // "unknown"): \(.value)ms (exit: \(.extra.exit_code // "n/a"))"' 2>/dev/null | sort -u | head -20)
        if [[ -n "$conn_data" ]]; then
            echo "- **Connectors**:"
            echo "$conn_data" | while IFS= read -r line; do
                echo "  - $line"
            done
        fi
    else
        echo "- No sensor sweep data in this period"
    fi
else
    echo "- No sensor sweep data. Runs via cron or manually."
fi

echo ""

# ── Dream Cycle ───────────────────────────────────────────────────────────
echo "## Dream Cycle"
echo ""

dc_runs=0
for d in $(seq 0 $((DAYS - 1))); do
    local_day="$(date -u -d "-${d} days" +%Y-%m-%d 2>/dev/null || echo "")"
    dc_log="$DREAM_LOG_DIR/${local_day}.md"
    [[ -f "$dc_log" ]] && dc_runs=$((dc_runs + 1))
done

echo "- **Nightly runs**: $dc_runs / $DAYS"
echo "- **Log directory**: \`$DREAM_LOG_DIR/\`"
echo ""

# ── Error Summary ─────────────────────────────────────────────────────────
echo "## Error Summary"
echo ""

if [[ "$HAS_DATA" == "true" ]]; then
    errors=$(echo "$METRIC_DATA" | jq -r 'select(.extra.status == "failed") | "\(.ts) | \(.component) | \(.metric) | \(.extra.stage // "—")"' 2>/dev/null | head -20 || true)
    if [[ -n "$errors" ]]; then
        echo "| Timestamp | Component | Metric | Stage |"
        echo "|-----------|-----------|--------|-------|"
        echo "$errors" | while IFS='|' read -r ts comp metric stage; do
            echo "| $ts | $comp | $metric | $stage |"
        done
    else
        echo "No errors recorded in this period."
    fi
else
    echo "No data to check for errors."
fi

echo ""
echo "---"
echo ""
echo "_Report generated by total-recall metrics-report.sh_"
echo ""
echo '## How to Use'
echo ""
echo '| Command | Description |'
echo '|---------|-------------|'
echo '| `bash scripts/metrics-report.sh` | Today report |'
echo '| `bash scripts/metrics-report.sh --week` | Last 7 days |'
echo '| `bash scripts/metrics-report.sh --days 14` | Last N days |'
echo '| `bash scripts/metrics-quality.sh score` | Score memory quality |'
echo '| `bash scripts/metrics-quality.sh snapshot` | Create snapshot |'
echo '| `bash tests/metrics-recall-test.sh` | Run recall tests |'

} > "$REPORT_FILE"

echo "Report written to: $REPORT_FILE"
echo ""
cat "$REPORT_FILE"
