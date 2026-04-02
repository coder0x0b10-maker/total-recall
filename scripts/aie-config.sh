#!/usr/bin/env bash
# Shared configuration loader for AIE scripts.

if [[ -n "${AIE_CONFIG_SH_LOADED:-}" ]]; then
  return 0
fi
readonly AIE_CONFIG_SH_LOADED=1

AIE_CONFIG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIE_REPO_ROOT="$(cd "${AIE_CONFIG_SCRIPT_DIR}/.." && pwd)"
AIE_DEFAULT_WORKSPACE="${OPENCLAW_WORKSPACE:-$AIE_REPO_ROOT}"
AIE_CONFIG_FILE="${AIE_CONFIG_FILE:-${AIE_DEFAULT_WORKSPACE}/config/aie.yaml}"

aie__load_json() {
  local workspace="$1"
  local config_file="$2"
  local python_output
  if ! python_output="$(
    WORKSPACE="$workspace" CONFIG_FILE="$config_file" python3 <<'PY'
import json
import os
from copy import deepcopy
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    raise SystemExit(
        "Missing Python dependency: PyYAML. Install it with: pip install pyyaml"
    )

workspace = os.path.abspath(os.path.expanduser(os.environ["WORKSPACE"]))
config_file = os.environ["CONFIG_FILE"]
home = os.path.expanduser("~")

defaults = {
    "workspace": workspace,
    "paths": {
        "workspace": workspace,
        "memory_dir": f"{workspace}/memory",
        "events_bus": f"{workspace}/memory/events/bus.jsonl",
        "sensor_state_dir": f"{workspace}/memory/sensor-state",
        "rumination_dir": f"{workspace}/memory/rumination",
        "followups_file": f"{workspace}/memory/rumination/follow-ups.jsonl",
        "observations_file": f"{workspace}/memory/observations.md",
        "preconscious_buffer": f"{workspace}/memory/preconscious-buffer.md",
        "logs_dir": f"{workspace}/logs",
        "health_data_dir": f"{workspace}/health/data",
        "env_file": f"{workspace}/.env",
        "perplexity_search_script": "",
        "openclaw_config": f"{home}/.openclaw/openclaw.json",
    },
    "profile": {
        "assistant_name": "Max",
        "primary_user_name": "the user",
        "household_context": "their household",
        "family_labels": [],
        "timezone": "UTC",
        "location_label": "",
    },
    "api": {
        "http_referer": "https://github.com/gavdalf/total-recall",
    },
    "models": {
        "rumination": "google/gemini-2.5-flash",
        "classification": "google/gemini-2.5-flash",
        "enrichment": "google/gemini-2.5-flash",
        "ambient_actions": "google/gemini-2.5-flash",
        "observer": "google/gemini-2.5-flash",
        "reflector": "google/gemini-2.5-flash",
        "dream": "google/gemini-2.5-flash",
    },
    "connectors": {
        "high_importance_senders": [],  # empty by default; users add their own
        "retry": {
            "max_attempts": 3,
            "base_delay": 1.0,
            "max_delay": 10.0,
            "jitter": true,
            "log_retries": true,
            "label": "total-recall",
        },
        "calendar": {
            "enabled": False,
            "provider": "gog",
            "account": "",
            "calendar_id": "primary",
            "lookahead_days": 2,
            "max_events": 50,
            "keyring_password": "",
        },
        "todoist": {
            "enabled": False,
        },
        "ionos": {
            "enabled": False,
            "account": "ionos",
            "unread_limit": 10,
        },
        "gmail": {
            "enabled": False,
            "provider": "gog",
            "account": "",
            "unread_query": "is:unread",
            "max_messages": 10,
            "keyring_password": "",
        },
        "fitbit": {
            "enabled": False,
            "sleep_target_hours": 7.5,
            "short_sleep_minutes": 360,
            "great_sleep_minutes": 480,
            "watch_off_minutes": 180,
            "watch_uncertain_minutes": 300,
            "resting_hr_threshold": 65,
            "weight_target_lbs": 157,
            "steps_milestone": 10000,
        },
        "filewatch": {
            "enabled": True,
            "watch_files": [
                "{memory_dir}/observations.md",
                "{memory_dir}/{today}.md",
                "{memory_dir}/favorites.md",
            ],
        },
    },
    "notifications": {
        "quiet_hours": {
            "enabled": True,
            "timezone": "UTC",
            "start_hour": 22,
            "end_hour": 7,
        },
        "telegram": {
            "enabled": False,
            "bot_token": "",
            "chat_id": "",
        },
        "discord": {
            "enabled": False,
            "webhook_url": "",
        },
        "webhook": {
            "enabled": False,
            "url": "",
            "headers": {},
        },
    },
    "thresholds": {
        "rumination_cooldown_seconds": 1800,
        "rumination_staleness_seconds": 14400,
        "sensor_prune_hours": 48,
        "emergency": {
            "importance": 0.85,
            "expires_within_seconds": 14400,
            "max_alerts_per_day": 2,
        },
    },
    "ambient_actions": {
        "enabled": True,
        "max_actions": 5,
        "action_budget_seconds": 60,
        "weather_url": "https://wttr.in",
        "places": {
            "enabled": False,
            "default_lat": 0.0,
            "default_lng": 0.0,
            "default_limit": 3,
        },
        "tool_settings": {
            "calendar_lookup": {
                "gog_account": "",
                "gog_keyring_password": "",
            },
            "gmail_search": {
                "gog_account": "",
                "gog_keyring_password": "",
            },
            "gmail_read": {
                "gog_account": "",
                "gog_keyring_password": "",
            },
            "ionos_search": {
                "account": "ionos",
            },
            "fitbit_data": {
                "enabled": True,
            },
            "openrouter_balance": {
                "enabled": True,
            },
            "web_search": {
                "enabled": False,
                "script": "",
            },
            "places_lookup": {
                "enabled": False,
            },
        },
    },
}


def merge(base, override):
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value
    return base


config = deepcopy(defaults)
if os.path.exists(config_file):
    with open(config_file, "r", encoding="utf-8") as fh:
        loaded = yaml.safe_load(fh) or {}
    if not isinstance(loaded, dict):
        raise SystemExit("AIE config must be a YAML mapping at the top level")
    merge(config, loaded)

today = __import__("datetime").datetime.now(__import__("datetime").UTC).strftime("%Y-%m-%d")
config["workspace"] = os.path.abspath(os.path.expanduser(str(config.get("workspace") or workspace)))

def expand_path(value, base_dir):
    text = os.path.expandvars(os.path.expanduser(str(value)))
    candidate = Path(text)
    if not candidate.is_absolute():
        candidate = Path(base_dir) / candidate
    return str(candidate.resolve())

config["paths"]["workspace"] = expand_path(config["paths"].get("workspace", config["workspace"]), workspace)
config["workspace"] = config["paths"]["workspace"]
path_context = {
    "workspace": config["paths"]["workspace"],
    "memory_dir": expand_path(config["paths"]["memory_dir"], config["workspace"]),
    "today": today,
}

def format_value(value):
    if isinstance(value, str):
        return value.format(**path_context)
    if isinstance(value, list):
        return [format_value(item) for item in value]
    if isinstance(value, dict):
        return {key: format_value(item) for key, item in value.items()}
    return value

config = format_value(config)
for key, value in list(config["paths"].items()):
    if isinstance(value, str):
        formatted = value
        if key.endswith("_script") and not formatted:
            config["paths"][key] = ""
        else:
            config["paths"][key] = expand_path(formatted, config["workspace"])

print(json.dumps(config))
PY
  )"; then
    echo "$python_output" >&2
    return 1
  fi
  printf '%s\n' "$python_output"
}

aie_init() {
  export AIE_WORKSPACE="${AIE_WORKSPACE:-$AIE_DEFAULT_WORKSPACE}"
  export OPENCLAW_WORKSPACE="$AIE_WORKSPACE"

  if [[ -z "${AIE_CONFIG_JSON:-}" ]]; then
    AIE_CONFIG_JSON="$(aie__load_json "$AIE_WORKSPACE" "$AIE_CONFIG_FILE")"
    export AIE_CONFIG_JSON
  fi

  AIE_WORKSPACE="$(aie_get "workspace" "$AIE_WORKSPACE")"
  export AIE_WORKSPACE OPENCLAW_WORKSPACE="$AIE_WORKSPACE"

  AIE_MEMORY_DIR="$(aie_get "paths.memory_dir" "$AIE_WORKSPACE/memory")"
  AIE_ENV_FILE="$(aie_get "paths.env_file" "$AIE_WORKSPACE/.env")"
  AIE_LOGS_DIR="$(aie_get "paths.logs_dir" "$AIE_WORKSPACE/logs")"
  AIE_SENSOR_STATE_DIR="$(aie_get "paths.sensor_state_dir" "$AIE_WORKSPACE/memory/sensor-state")"
  export AIE_MEMORY_DIR AIE_ENV_FILE AIE_LOGS_DIR AIE_SENSOR_STATE_DIR
}

aie_get() {
  local path="$1"
  local default_value="${2-}"
  AIE_PATH="$path" AIE_DEFAULT="$default_value" python3 <<'PY'
import json
import os

data = json.loads(os.environ["AIE_CONFIG_JSON"])
path = os.environ["AIE_PATH"]
default = os.environ.get("AIE_DEFAULT", "")

value = data
for part in path.split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        value = default
        break

if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
elif isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

aie_bool() {
  [[ "$(aie_get "$1" "false")" == "true" ]]
}

aie_load_env() {
  if [[ -f "$AIE_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    if ! source "$AIE_ENV_FILE" 2>/dev/null; then
      echo "WARN: Failed to load $AIE_ENV_FILE; check shell syntax and variable references" >&2
    fi
    set +a
  fi
}

aie_ensure_dirs() {
  mkdir -p "$AIE_MEMORY_DIR" "$AIE_LOGS_DIR" "$AIE_SENSOR_STATE_DIR"
}

aie_notification_channel_enabled() {
  local channel="$1"
  aie_bool "notifications.${channel}.enabled"
}

aie_sender_matches_importance() {
  local sender="$1"
  local senders_json
  senders_json="$(aie_get "connectors.high_importance_senders" "[]")"

  SENDER_TEXT="$sender" SENDERS_JSON="$senders_json" python3 <<'PY'
import json
import os
import sys

sender = os.environ.get("SENDER_TEXT", "").lower()
try:
    patterns = json.loads(os.environ.get("SENDERS_JSON", "[]"))
except json.JSONDecodeError:
    patterns = []

for pattern in patterns:
    if pattern and str(pattern).lower() in sender:
        sys.exit(0)

sys.exit(1)
PY
}

aie_is_quiet_hours() {
  local enabled timezone start_hour end_hour hour
  enabled="$(aie_get "notifications.quiet_hours.enabled" "true")"
  [[ "$enabled" == "true" ]] || return 1

  timezone="$(aie_get "notifications.quiet_hours.timezone" "$(aie_get "profile.timezone" "UTC")")"
  start_hour="$(aie_get "notifications.quiet_hours.start_hour" "22")"
  end_hour="$(aie_get "notifications.quiet_hours.end_hour" "7")"
  hour="$(TZ="$timezone" date +%H)"

  if ((10#$start_hour > 10#$end_hour)); then
    ((10#$hour >= 10#$start_hour || 10#$hour < 10#$end_hour))
  else
    ((10#$hour >= 10#$start_hour && 10#$hour < 10#$end_hour))
  fi
}

# Retry wrapper for external API calls with exponential backoff
# Usage: output=$(aie_retry_call command arg1 arg2...) or ! aie_retry_call ...
# Returns command stdout on success, empty on failure after all retries
# Logs retry attempts if LOG_RETRIES is set to "true" (default from config)
aie_retry_call() {
    local max_attempts base_delay max_delay jitter enable_retry_log label attempt delay exit_code output

    # Try to get config values, fallback to defaults if config system unavailable
    local max_cfg base_cfg maxd_cfg jitter_cfg log_cfg label_cfg
    max_cfg="$(aie_get "connectors.retry.max_attempts" "" 2>/dev/null || echo "")"
    base_cfg="$(aie_get "connectors.retry.base_delay" "" 2>/dev/null || echo "")"
    maxd_cfg="$(aie_get "connectors.retry.max_delay" "" 2>/dev/null || echo "")"
    jitter_cfg="$(aie_get "connectors.retry.jitter" "" 2>/dev/null || echo "")"
    log_cfg="$(aie_get "connectors.retry.log_retries" "" 2>/dev/null || echo "")"
    label_cfg="$(aie_get "connectors.retry.label" "" 2>/dev/null || echo "")"

    max_attempts="${max_cfg:-3}"
    base_delay="${base_cfg:-1.0}"
    max_delay="${maxd_cfg:-10.0}"
    jitter="${jitter_cfg:-true}"
    enable_retry_log="${log_cfg:-true}"
    label="${label_cfg:-total-recall}"

    [[ $# -eq 0 ]] && return 1

    attempt=1

    while true; do
        if [[ $attempt -gt $max_attempts ]]; then
            [[ "$enable_retry_log" == "true" ]] && echo "WARN: $1 failed after $max_attempts attempts" >&2
            return 1
        fi

        # Execute command with current args, capture stdout; stderr will be captured but we also want to show on failure
        # Execute command, capturing only stdout; stderr flows to stderr of script
        output=$("$@")
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            printf '%s\n' "$output"
            return 0
        fi

        if [[ $attempt -eq $max_attempts ]]; then
            [[ "$enable_retry_log" == "true" ]] && echo "WARN: $1 final attempt failed (exit $exit_code)" >&2
            return $exit_code
        fi

        # Calculate exponential backoff: base * 2^(attempt-1)
        delay=$(awk "BEGIN {print $base_delay * (2 ^ ($attempt - 1))}")

        # Apply jitter if enabled: random factor between 0.75 and 1.25
        if [[ "$jitter" == "true" ]]; then
            local jitter_factor
            jitter_factor=$(awk "BEGIN {srand(); print 0.5 + rand()}")
            delay=$(awk "BEGIN {print $delay * $jitter_factor}")
        fi

        # Cap at max_delay
        if awk "BEGIN {exit !($delay > $max_delay)}"; then
            delay=$max_delay
        fi

        [[ "$enable_retry_log" == "true" ]] && echo "[$label] Retry $attempt/$max_attempts for $1 failed (exit $exit_code), retrying in ${delay}s..." >&2
        sleep "$delay"
        attempt=$((attempt + 1))
    done
}

# Model fallback system for agent roles
# Priority: user-specified model -> fallback chain -> original default
RUMINATION_MODEL_DEFAULT="google/gemini-2.5-flash"
RUMINATION_MODEL_FALLBACK_1="qwen/qwen3.6-plus:free"
RUMINATION_MODEL_FALLBACK_2="nvidia/nemotron-3-nano-30b:free"
RUMINATION_MODEL_FALLBACK_3="stepfun/step-3.5-flash:free"

# Check if a model identifier is available on OpenRouter
# Returns 0 if available, 1 if not
aie_model_available() {
    local model="$1"
    local api_key="${LLM_API_KEY:-${OPENROUTER_API_KEY:-}}"
    [[ -z "$api_key" ]] && return 1

    # Use retry for API call
    local response
    response=$(aie_retry_call curl -sS -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        "https://openrouter.ai/api/v1/models" 2>/dev/null) || return 1

    # Check if model appears in the response
    printf '%s' "$response" | grep -q "\"id\":\"$model\"" && return 0
    # Also check for partial matches (some models may have suffixes)
    printf '%s' "$response" | grep -q "\"id\":\"$model" && return 0

    return 1
}

# Get the best available model for rumination
# Priority: 1) user-specified model, 2) fallback_1, 3) fallback_2, 4) fallback_3, 5) original default
aie_get_rumination_model() {
    # Check for user-specified model in config
    local config_model
    config_model="$(aie_get "connectors.rumination.model" "")"
    if [[ -n "$config_model" && "$config_model" != "$RUMINATION_MODEL_DEFAULT" ]]; then
        if aie_model_available "$config_model"; then
            echo "$config_model"
            return 0
        fi
        echo "WARN: Configured rumination model '$config_model' not available, trying fallbacks" >&2
    fi

    # Try fallback chain
    for fallback in "$RUMINATION_MODEL_FALLBACK_1" "$RUMINATION_MODEL_FALLBACK_2" "$RUMINATION_MODEL_FALLBACK_3"; do
        if aie_model_available "$fallback"; then
            echo "$fallback"
            return 0
        fi
    done

    # Finally, try the original default
    if aie_model_available "$RUMINATION_MODEL_DEFAULT"; then
        echo "$RUMINATION_MODEL_DEFAULT"
        return 0
    fi

    # Nothing available - return a generic free model as last resort
    echo "$RUMINATION_MODEL_FALLBACK_1"
    return 1
}

# Observer observer model
# Models optimized for fast, lightweight session summarization
OBSERVER_MODEL_DEFAULT="qwen/qwen3.6-plus:free"
OBSERVER_MODEL_FALLBACK_1="qwen/qwen3-coder:free"
OBSERVER_MODEL_FALLBACK_2="$RUMINATION_MODEL_FALLBACK_1"
OBSERVER_MODEL_FALLBACK_3="$RUMINATION_MODEL_FALLBACK_3"

# Get the best available model for observer
# Priority: 1) user-config 2) observer_default 3) observer fb 4) rumination fb 5) rumination fb 6) return fb 1
aie_get_observer_model() {
    local config_model
    config_model="$(aie_get "connectors.observer.model" "")"
    if [[ -n "$config_model" && "$config_model" != "$OBSERVER_MODEL_DEFAULT" ]]; then
        if aie_model_available "$config_model"; then
            echo "$config_model"
            return 0
        fi
        echo "WARN: Configured observer model '$config_model' not available, trying fallbacks" >&2
    fi

    for fallback in "$OBSERVER_MODEL_DEFAULT" "$OBSERVER_MODEL_FALLBACK_1" "$OBSERVER_MODEL_FALLBACK_2" "$OBSERVER_MODEL_FALLBACK_3" "$RUMINATION_MODEL_FALLBACK_1" "$RUMINATION_MODEL_FALLBACK_2" "$RUMINATION_MODEL_FALLBACK_3"; do
        if aie_model_available "$fallback"; then
            echo "$fallback"
            return 0
        fi
    done

    # Nothing available - return first rumination fallback as last resort
    echo "$RUMINATION_MODEL_FALLBACK_1"
    return 1
}

# Reflector reflector model
# Models optimized for deep reasoning & consolidation
REFLECTOR_MODEL_DEFAULT="nvidia/nemotron-3-super-120b-a12b:free"
REFLECTOR_MODEL_FALLBACK_1="qwen/qwen3-next-80b-a3b-instruct:free"
REFLECTOR_MODEL_FALLBACK_2="$RUMINATION_MODEL_FALLBACK_1"
REFLECTOR_MODEL_FALLBACK_3="$RUMINATION_MODEL_FALLBACK_2"

# Get the best available model for reflector
# Priority: 1) user-config 2) reflector_default 3) reflector fb 4) reflector fb 5) rumination fb 6) rumination fb 7) return fb 1
aie_get_reflector_model() {
    local config_model
    config_model="$(aie_get "connectors.reflector.model" "")"
    if [[ -n "$config_model" && "$config_model" != "$REFLECTOR_MODEL_DEFAULT" ]]; then
        if aie_model_available "$config_model"; then
            echo "$config_model"
            return 0
        fi
        echo "WARN: Configured reflector model '$config_model' not available, trying fallbacks" >&2
    fi

    for fallback in "$REFLECTOR_MODEL_DEFAULT" "$REFLECTOR_MODEL_FALLBACK_1" "$REFLECTOR_MODEL_FALLBACK_2" "$REFLECTOR_MODEL_FALLBACK_3" "$RUMINATION_MODEL_FALLBACK_1" "$RUMINATION_MODEL_FALLBACK_2" "$RUMINATION_MODEL_FALLBACK_3"; do
        if aie_model_available "$fallback"; then
            echo "$fallback"
            return 0
        fi
    done

    # Nothing available - return first rumination fallback as last resort
    echo "$RUMINATION_MODEL_FALLBACK_1"
    return 1
}

# Enrichment enrichment model
# Models optimized for structured data processing
ENRICHMENT_MODEL_DEFAULT="qwen/qwen3-coder:free"
ENRICHMENT_MODEL_FALLBACK_1="qwen/qwen3.6-plus:free"
ENRICHMENT_MODEL_FALLBACK_2="$RUMINATION_MODEL_FALLBACK_3"

# Get the best available model for enrichment
# Priority: 1) user-config 2) enrichment_default 3) enrichment fb 4) enrichment fb 5) rumination fb 6) rumination fb 8) return fb 1
aie_get_enrichment_model() {
    local config_model
    config_model="$(aie_get "connectors.enrichment.model" "")"
    if [[ -n "$config_model" && "$config_model" != "$ENRICHMENT_MODEL_DEFAULT" ]]; then
        if aie_model_available "$config_model"; then
            echo "$config_model"
            return 0
        fi
        echo "WARN: Configured enrichment model '$config_model' not available, trying fallbacks" >&2
    fi

    for fallback in "$ENRICHMENT_MODEL_DEFAULT" "$ENRICHMENT_MODEL_FALLBACK_1" "$ENRICHMENT_MODEL_FALLBACK_2" "$RUMINATION_MODEL_FALLBACK_1" "$RUMINATION_MODEL_FALLBACK_2" "$RUMINATION_MODEL_FALLBACK_3"; do
        if aie_model_available "$fallback"; then
            echo "$fallback"
            return 0
        fi
    done

    # Nothing available - return first rumination fallback as last resort
    echo "$RUMINATION_MODEL_FALLBACK_1"
    return 1
}

# Ambient ambient_actions model
# Models optimized for quick utility calls
AMBIENT_ACTIONS_MODEL_DEFAULT="stepfun/step-3.5-flash:free"
AMBIENT_ACTIONS_MODEL_FALLBACK_1="qwen/qwen3-coder:free"
AMBIENT_ACTIONS_MODEL_FALLBACK_2="$RUMINATION_MODEL_FALLBACK_3"

# Get the best available model for ambient_actions
# Priority: 1) user-config 2) ambient_actions_default 3) ambient_actions_fb 4) ambient_actions_fb 5) rumination fb 6) return fb 1
aie_get_ambient_actions_model() {
    local config_model
    config_model="$(aie_get "connectors.ambient_actions.model" "")"
    if [[ -n "$config_model" && "$config_model" != "$AMBIENT_ACTIONS_MODEL_DEFAULT" ]]; then
        if aie_model_available "$config_model"; then
            echo "$config_model"
            return 0
        fi
        echo "WARN: Configured ambient_actions model '$config_model' not available, trying fallbacks" >&2
    fi

    for fallback in "$AMBIENT_ACTIONS_MODEL_DEFAULT" "$AMBIENT_ACTIONS_MODEL_FALLBACK_1" "$AMBIENT_ACTIONS_MODEL_FALLBACK_2" "$RUMINATION_MODEL_FALLBACK_1" "$RUMINATION_MODEL_FALLBACK_2" "$RUMINATION_MODEL_FALLBACK_3"; do
        if aie_model_available "$fallback"; then
            echo "$fallback"
            return 0
        fi
    done

    # Nothing available - return first rumination fallback as last resort
    echo "$RUMINATION_MODEL_FALLBACK_1"
    return 1
}

# Dream Cycle model - for creative/surreal ideation
DREAM_CYCLE_MODEL_DEFAULT="nousresearch/hermes-3-llama-3.1-405b:free"
DREAM_CYCLE_MODEL_FALLBACK_1="qwen/qwen3-next-80b-a3b-instruct:free"
DREAM_CYCLE_MODEL_FALLBACK_2="nvidia/nemotron-3-super-120b-a12b:free"
DREAM_CYCLE_MODEL_FALLBACK_3="qwen/qwen3.6-plus:free"

aie_get_dream_cycle_model() {
    local config_model
    config_model="$(aie_get "connectors.dream.model" "")"
    if [[ -n "$config_model" && "$config_model" != "$DREAM_CYCLE_MODEL_DEFAULT" ]]; then
        if aie_model_available "$config_model"; then
            echo "$config_model"
            return 0
        fi
        echo "WARN: Configured dream model '$config_model' not available, trying fallbacks" >&2
    fi

    for fallback in "$DREAM_CYCLE_MODEL_DEFAULT" "$DREAM_CYCLE_MODEL_FALLBACK_1" "$DREAM_CYCLE_MODEL_FALLBACK_2" "$DREAM_CYCLE_MODEL_FALLBACK_3"; do
        if aie_model_available "$fallback"; then
            echo "$fallback"
            return 0
        fi
    done

    for fallback in "$RUMINATION_MODEL_FALLBACK_1" "$RUMINATION_MODEL_FALLBACK_2" "$RUMINATION_MODEL_FALLBACK_3"; do
        if aie_model_available "$fallback"; then
            echo "$fallback"
            return 0
        fi
    done

    echo "$DREAM_CYCLE_MODEL_DEFAULT"
    return 1
}

# Generic model getter for any role
aie_get_model_for_role() {
    local role="$1"
    case "$role" in
        observer) aie_get_observer_model ;;
        reflector) aie_get_reflector_model ;;
        rumination|ruminate) aie_get_rumination_model ;;
        enrichment) aie_get_enrichment_model ;;
        ambient_actions|ambient) aie_get_ambient_actions_model ;;
        dream|dream_cycle) aie_get_dream_cycle_model ;;
        classification) aie_get_classification_model ;;
        *) echo "google/gemini-2.5-flash" ;;
    esac
}
