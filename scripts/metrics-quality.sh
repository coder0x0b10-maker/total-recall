#!/usr/bin/env bash
# metrics-quality.sh — Memory quality evaluator for Total Recall
# Evaluates observations.md quality via snapshot, diff, and scoring
# Usage: bash metrics-quality.sh {snapshot|diff|score} [args...]
#
# snapshot  — create a snapshot of current observations state
# diff      — compare two snapshots (or snapshot vs current)
# score     — score current observations.md quality (0-100)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/scripts/_compat.sh"
source "$SKILL_DIR/scripts/_metrics.sh"

WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_DIR/../.." && pwd)}"
MEMORY_DIR="${MEMORY_DIR:-$WORKSPACE/memory}"
OBSERVATIONS_FILE="$MEMORY_DIR/observations.md"
SNAPSHOTS_DIR="$WORKSPACE/memory/metrics/snapshots"
QUALITY_DIR="$WORKSPACE/memory/metrics/quality"

mkdir -p "$SNAPSHOTS_DIR" "$QUALITY_DIR"

# ─── Helpers ─────────────────────────────────────────────────────────────────

count_obs_lines() {
    # Count observation lines (emoji-prefixed bullets)
    grep -cE '^\s*-\s*[🔴🟡🟢]' "$1" 2>/dev/null || echo 0
}

count_type() {
    # Count observations of a given dc:type
    grep -oP 'dc:type=\K\w+' "$1" 2>/dev/null | grep -c "^$1$" 2>/dev/null || echo 0
}

json_file() {
    printf '%s/%s.json' "$QUALITY_DIR" "$(date -u +%Y-%m-%d)"
}

# ─── Snapshot command ────────────────────────────────────────────────────────

cmd_snapshot() {
    if [[ ! -f "$OBSERVATIONS_FILE" ]]; then
        echo "ERROR: observations.md not found at $OBSERVATIONS_FILE" >&2
        exit 1
    fi

    local stamp
    stamp="$(date -u +%Y-%m-%d-%H%M)"
    local snap_file="$SNAPSHOTS_DIR/${stamp}.md"

    cp "$OBSERVATIONS_FILE" "$snap_file"

    # Collect stats
    local total_lines word_count obs_count
    total_lines=$(wc -l < "$OBSERVATIONS_FILE")
    word_count=$(wc -w < "$OBSERVATIONS_FILE")
    obs_count=$(count_obs_lines "$OBSERVATIONS_FILE")

    # Type distribution
    local type_fact type_pref type_goal type_habit type_event type_rule type_context type_untagged
    type_fact=$(grep -oP 'dc:type=\Kfact\b' "$OBSERVATIONS_FILE" 2>/dev/null | wc -l || echo 0)
    type_pref=$(grep -oP 'dc:type=\Kpreference\b' "$OBSERVATIONS_FILE" 2>/dev/null | wc -l || echo 0)
    type_goal=$(grep -oP 'dc:type=\Kgoal\b' "$OBSERVATIONS_FILE" 2>/dev/null | wc -l || echo 0)
    type_habit=$(grep -oP 'dc:type=\Khabit\b' "$OBSERVATIONS_FILE" 2>/dev/null | wc -l || echo 0)
    type_event=$(grep -oP 'dc:type=\Kevent\b' "$OBSERVATIONS_FILE" 2>/dev/null | wc -l || echo 0)
    type_rule=$(grep -oP 'dc:type=\Krule\b' "$OBSERVATIONS_FILE" 2>/dev/null | wc -l || echo 0)
    type_context=$(grep -oP 'dc:type=\Kcontext\b' "$OBSERVATIONS_FILE" 2>/dev/null | wc -l || echo 0)
    type_untagged=$(( obs_count - type_fact - type_pref - type_goal - type_habit - type_event - type_rule - type_context ))

    # Importance distribution
    local imp_tagged
    imp_tagged=$(grep -cP 'dc:importance=\d' "$OBSERVATIONS_FILE" 2>/dev/null || echo 0)

    local snap_json="$QUALITY_DIR/snapshot-${stamp}.json"
    jq -cn \
        --arg file "$snap_file" \
        --arg stamp "$stamp" \
        --argjson total_lines "$total_lines" \
        --argjson word_count "$word_count" \
        --argjson obs_count "$obs_count" \
        --argjson type_fact "$type_fact" \
        --argjson type_pref "$type_pref" \
        --argjson type_goal "$type_goal" \
        --argjson type_habit "$type_habit" \
        --argjson type_event "$type_event" \
        --argjson type_rule "$type_rule" \
        --argjson type_context "$type_context" \
        --argjson type_untagged "$type_untagged" \
        --argjson imp_tagged "$imp_tagged" \
        '{
            type: "snapshot",
            timestamp: $stamp,
            file: $file,
            total_lines: $total_lines,
            word_count: $word_count,
            observations: $obs_count,
            types: {
                fact: $type_fact,
                preference: $type_pref,
                goal: $type_goal,
                habit: $type_habit,
                event: $type_event,
                rule: $type_rule,
                context: $type_context,
                untagged: $type_untagged
            },
            importance_tagged: $imp_tagged
        }' > "$snap_json"

    echo "Snapshot created:"
    echo "  File: $snap_file"
    echo "  Stats: $snap_json"
    echo "  Observations: $obs_count | Words: $word_count | Types tagged: $((obs_count - type_untagged))/$obs_count"
}

# ─── Diff command ────────────────────────────────────────────────────────────

cmd_diff() {
    local snap_a="${1:-}"
    local snap_b="${2:-}"

    if [[ -z "$snap_a" ]]; then
        # Find two most recent snapshots
        local snaps
        snaps=$(ls -1 "$SNAPSHOTS_DIR"/*.md 2>/dev/null | tail -2)
        local count
        count=$(echo "$snaps" | grep -c . || echo 0)
        if [[ "$count" -lt 2 ]]; then
            echo "ERROR: Need at least 2 snapshots to diff. Run 'snapshot' twice first." >&2
            exit 1
        fi
        snap_a=$(echo "$snaps" | head -1)
        snap_b=$(echo "$snaps" | tail -1)
    fi

    if [[ ! -f "$snap_a" ]]; then
        echo "ERROR: Snapshot not found: $snap_a" >&2
        exit 1
    fi
    if [[ ! -f "$snap_b" ]]; then
        echo "ERROR: Snapshot not found: $snap_b" >&2
        exit 1
    fi

    local obs_a obs_b wc_a wc_b
    obs_a=$(count_obs_lines "$snap_a")
    obs_b=$(count_obs_lines "$snap_b")
    wc_a=$(wc -w < "$snap_a")
    wc_b=$(wc -w < "$snap_b")

    local added=$(( obs_b - obs_a ))
    local word_diff=$(( wc_b - wc_a ))

    # Extract observation bodies for comparison
    local bodies_a bodies_b
    bodies_a=$(grep -E '^\s*-\s*[🔴🟡🟢]' "$snap_a" | sed 's/^[[:space:]]*-[[:space:]]*[🔴🟡🟢][[:space:]]*[0-9:]*[[:space:]]*//' | sed 's/\*\*//g' | sort -u || true)
    bodies_b=$(grep -E '^\s*-\s*[🔴🟡🟢]' "$snap_b" | sed 's/^[[:space:]]*-[[:space:]]*[🔴🟡🟢][[:space:]]*[0-9:]*[[:space:]]*//' | sed 's/\*\*//g' | sort -u || true)

    local common new removed
    common=$(comm -12 <(echo "$bodies_a") <(echo "$bodies_b") | wc -l || echo 0)
    new=$(comm -13 <(echo "$bodies_a") <(echo "$bodies_b") | wc -l || echo 0)
    removed=$(comm -23 <(echo "$bodies_a") <(echo "$bodies_b") | wc -l || echo 0)

    # Type distribution changes
    for t in fact preference goal habit event rule context; do
        local ta tb
        ta=$(grep -oP "dc:type=\K${t}\b" "$snap_a" 2>/dev/null | wc -l || echo 0)
        tb=$(grep -oP "dc:type=\K${t}\b" "$snap_b" 2>/dev/null | wc -l || echo 0)
        if [[ "$ta" != "$tb" ]]; then
            local delta=$(( tb - ta ))
            echo "  $t: $ta → $tb ($([ $delta -gt 0 ] && echo +$delta || echo $delta))"
        fi
    done

    echo "=== Snapshot Diff ==="
    echo "  A: $(basename "$snap_a") — $obs_a observations, $wc_a words"
    echo "  B: $(basename "$snap_b") — $obs_b observations, $wc_b words"
    echo ""
    echo "  New observations: $new"
    echo "  Removed observations: $removed"
    echo "  Common (unchanged): $common"
    echo "  Net change: $added observations, $word_diff words"
    echo ""
    echo "  Type changes:"
}

# ─── Score command ───────────────────────────────────────────────────────────

cmd_score() {
    if [[ ! -f "$OBSERVATIONS_FILE" ]]; then
        echo "ERROR: observations.md not found at $OBSERVATIONS_FILE" >&2
        exit 1
    fi

    jq -nc \
        --argjson score 0 \
        '{score: 0, breakdown: {}}' | python3 - "$OBSERVATIONS_FILE" "$(json_file)" << 'PYEOF'
import sys, re, json

obs_file = sys.argv[1]
out_file = sys.argv[2]

with open(obs_file, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
score = 0
breakdown = {}

# 1. Type metadata ratio (0-25 points)
obs_lines = [l for l in lines if re.match(r'\s*-\s*[🔴🟡🟢]', l)]
total_obs = len(obs_lines)
meta_lines = [l for l in obs_lines if 'dc:type=' in l]
meta_ratio = len(meta_lines) / max(total_obs, 1)
score += int(meta_ratio * 25)
breakdown['type_metadata'] = {"score": int(meta_ratio * 25), "max": 25, "ratio": round(meta_ratio, 2), "tagged": len(meta_lines), "total": total_obs}

# 2. Type diversity (0-20 points)
known_types = {'fact', 'preference', 'goal', 'habit', 'event', 'rule', 'context'}
found_types = set(re.findall(r'dc:type=(\w+)', content))
found_known = found_types & known_types
diversity = len(found_known) / len(known_types)
score += int(diversity * 20)
breakdown['type_diversity'] = {"score": int(diversity * 20), "max": 20, "types_found": sorted(list(found_known))}

# 3. Importance distribution balance (0-20 points)
importances = [float(m) for m in re.findall(r'dc:importance=([\d.]+)', content)]
if importances:
    avg_imp = sum(importances) / len(importances)
    has_high = any(i >= 7.0 for i in importances)
    has_low = any(i <= 3.0 for i in importances)
    has_mid = any(3.0 < i < 7.0 for i in importances)
    spread = sum(1 for b in [has_high, has_low, has_mid] if b)
    spread_score = int((spread / 3) * 20)
else:
    spread_score = 0
score += spread_score
breakdown['importance_balance'] = {"score": spread_score, "max": 20, "avg_importance": round(avg_imp, 2) if importances else None, "has_high": has_high if importances else False, "has_low": has_low if importances else False, "has_mid": has_mid if importances else False}

# 4. Word count vs target (0-15 points)
word_count = len(content.split())
ideal_min, ideal_max = 1000, 5000
if ideal_min <= word_count <= ideal_max:
    wc_score = 15
elif word_count < ideal_min:
    wc_score = int((word_count / ideal_min) * 15)
else:
    wc_score = max(0, int(15 - (word_count - ideal_max) / ideal_max * 15))
score += wc_score
breakdown['size_appropriate'] = {"score": wc_score, "max": 15, "word_count": word_count, "ideal_range": f"{ideal_min}-{ideal_max}"}

# 5. Content quality — non-trivial observations (0-20 points)
non_trivial = 0
for ol in obs_lines:
    body = re.sub(r'\*\*.*?\*\*', '', ol)
    body = re.sub(r'^\s*-\s*[🔴🟡🟢]\s*\d{2}:\d{2}\s*', '', body)
    if len(body.strip()) > 15:
        non_trivial += 1
non_trivial_ratio = non_trivial / max(total_obs, 1)
nt_score = int(non_trivial_ratio * 20)
score += nt_score
breakdown['content_quality'] = {"score": nt_score, "max": 20, "non_trivial": non_trivial, "total": total_obs, "ratio": round(non_trivial_ratio, 2)}

# 6. Structure integrity (0-20 points)
has_header = 1 if '# Observations Log' in content or '# observations' in content.lower() else 0
has_separator = 1 if '---' in content and (content.index('---') > content.find('\n') + 1) else 0
has_obs_content = 1 if any(re.match(r'\s*-\s*[🔴🟡🟢]', l) for l in obs_lines) else 0

struct_score = int(((has_header + has_separator + has_obs_content) / 3) * 10)
# Bonus for having section dates
date_sections = len(re.findall(r'\n## .*', content))
if date_sections > 0:
    struct_score = min(20, struct_score + 5)
if len(obs_lines) > 5:
    struct_score = min(20, struct_score + 5)
score += struct_score
breakdown['structure'] = {"score": struct_score, "max": 20, "has_header": bool(has_header), "has_separator": bool(has_separator), "has_observations": bool(has_obs_content), "date_sections": date_sections}

result = {
    "score": score,
    "max": 100,
    "grade": "A" if score >= 85 else "B" if score >= 70 else "C" if score >= 50 else "D" if score >= 30 else "F",
    "breakdown": breakdown,
    "timestamp": __import__('datetime').datetime.utcnow().isoformat() + 'Z'
}

with open(out_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Quality Score: {result['score']}/100 ({result['grade']})")
print(f"  Type metadata: {breakdown['type_metadata']['score']}/25")
print(f"  Type diversity: {breakdown['type_diversity']['score']}/20")
print(f"  Importance balance: {breakdown['importance_balance']['score']}/20")
print(f"  Size appropriate: {breakdown['size_appropriate']['score']}/15")
print(f"  Content quality: {breakdown['content_quality']['score']}/20")
print(f"  Structure: {breakdown['structure']['score']}/20")
print(f"Result: {out_file}")
PYEOF
}

# ─── Main ────────────────────────────────────────────────────────────────────

case "${1:-}" in
    snapshot) cmd_snapshot ;;
    diff)     cmd_diff "${2:-}" "${3:-}" ;;
    score)    cmd_score ;;
    ""|help|--help|-h)
        cat <<'EOF'
Usage: bash metrics-quality.sh {snapshot|diff|score}

Commands:
  snapshot    Create a snapshot of current observations.md state
  diff [A] [B]  Compare two snapshots (defaults: two most recent)
  score       Score current observations quality (0-100)
EOF
        ;;
    *)
        echo "ERROR: Unknown command: $1" >&2
        exit 1
        ;;
esac
