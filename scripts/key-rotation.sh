#!/usr/bin/env bash
# Key rotation script for Total Recall
# Rotates API keys securely with backup and validation

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/scripts/_compat.sh"

WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_DIR/../.." && pwd)}"

echo "🔑 Total Recall — Key Rotation"
echo "=============================="
echo "Workspace: $WORKSPACE"
echo ""

# --- Parse arguments ---
ROTATE_OPENROUTER=false
NEW_KEY=""
BACKUP_ONLY=false
ROLLBACK=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --openrouter)
      ROTATE_OPENROUTER=true
      shift
      ;;
    --key=*)
      NEW_KEY="${1#*=}"
      shift
      ;;
    --backup-only)
      BACKUP_ONLY=true
      shift
      ;;
    --rollback)
      ROLLBACK=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --openrouter     Rotate OpenRouter API key"
      echo "  --key=KEY        Provide new key (otherwise prompts)"
      echo "  --backup-only    Only backup current keys, don't rotate"
      echo "  --rollback       Rollback to previous key from backup"
      echo "  --help           Show this help"
      echo ""
      echo "Supported credential stores:"
      echo "  - pass (password-store)"
      echo "  - systemd-credentials"
      echo "  - .env file"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage"
      exit 1
      ;;
  esac
done

# --- Detect credential store ---
detect_credential_store() {
  if command -v pass &>/dev/null && pass ls total-recall &>/dev/null 2>&1; then
    echo "pass"
  elif [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -f "$CREDENTIALS_DIRECTORY/openrouter-api-key" ]; then
    echo "systemd-credentials"
  elif [ -f "$WORKSPACE/.env" ]; then
    echo "env-file"
  else
    echo "none"
  fi
}

# --- Backup current key ---
backup_key() {
  local store="$1"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_dir="$WORKSPACE/security-backups"
  mkdir -p "$backup_dir"

  case "$store" in
    pass)
      if pass ls total-recall/openrouter-api-key &>/dev/null; then
        pass show total-recall/openrouter-api-key > "$backup_dir/openrouter-key_$timestamp.bak"
        echo "✅ Backed up OpenRouter key to $backup_dir/openrouter-key_$timestamp.bak"
      fi
      ;;
    systemd-credentials)
      if [ -f "$CREDENTIALS_DIRECTORY/openrouter-api-key" ]; then
        cp "$CREDENTIALS_DIRECTORY/openrouter-api-key" "$backup_dir/openrouter-key_$timestamp.bak"
        echo "✅ Backed up OpenRouter key to $backup_dir/openrouter-key_$timestamp.bak"
      fi
      ;;
    env-file)
      if [ -f "$WORKSPACE/.env" ] && grep -q "LLM_API_KEY\|OPENROUTER_API_KEY" "$WORKSPACE/.env"; then
        cp "$WORKSPACE/.env" "$backup_dir/env_$timestamp.bak"
        echo "✅ Backed up .env file to $backup_dir/env_$timestamp.bak"
      fi
      ;;
  esac
}

# --- Get current key ---
get_current_key() {
  local store="$1"
  case "$store" in
    pass)
      pass show total-recall/openrouter-api-key 2>/dev/null || echo ""
      ;;
    systemd-credentials)
      cat "$CREDENTIALS_DIRECTORY/openrouter-api-key" 2>/dev/null || echo ""
      ;;
    env-file)
      grep "^LLM_API_KEY=" "$WORKSPACE/.env" | cut -d'=' -f2- || \
      grep "^OPENROUTER_API_KEY=" "$WORKSPACE/.env" | cut -d'=' -f2- || echo ""
      ;;
    *)
      echo ""
      ;;
  esac
}

# --- Set new key ---
set_new_key() {
  local store="$1"
  local key="$2"

  case "$store" in
    pass)
      pass insert -f total-recall/openrouter-api-key <<< "$key"
      echo "✅ Updated OpenRouter key in pass"
      ;;
    systemd-credentials)
      echo "$key" > "$CREDENTIALS_DIRECTORY/openrouter-api-key"
      chmod 600 "$CREDENTIALS_DIRECTORY/openrouter-api-key"
      echo "✅ Updated OpenRouter key in systemd-credentials"
      ;;
    env-file)
      if [ -f "$WORKSPACE/.env" ]; then
        # Remove old key lines
        sed -i '/^LLM_API_KEY=/d; /^OPENROUTER_API_KEY=/d' "$WORKSPACE/.env"
      fi
      echo "LLM_API_KEY=$key" >> "$WORKSPACE/.env"
      chmod 600 "$WORKSPACE/.env"
      echo "✅ Updated OpenRouter key in .env file"
      ;;
  esac
}

# --- Validate key ---
validate_key() {
  local key="$1"
  if [ -z "$key" ]; then
    echo "❌ Key is empty"
    return 1
  fi

  # Basic format check for OpenRouter keys
  if [[ "$key" != sk-or-v1-* ]]; then
    echo "⚠️  Key doesn't start with 'sk-or-v1-' — may not be an OpenRouter key"
  fi

  # Test API call (minimal request)
  if curl -s -H "Authorization: Bearer $key" \
          -H "Content-Type: application/json" \
          --max-time 10 \
          "https://openrouter.ai/api/v1/models" \
          -o /dev/null -w "%{http_code}" | grep -q "200"; then
    echo "✅ Key validation successful"
    return 0
  else
    echo "❌ Key validation failed — API call unsuccessful"
    return 1
  fi
}

# --- Rollback ---
rollback_key() {
  local store="$1"
  local backup_file="$2"

  if [ ! -f "$backup_file" ]; then
    echo "❌ Backup file not found: $backup_file"
    return 1
  fi

  case "$store" in
    pass)
      pass insert -f total-recall/openrouter-api-key < "$backup_file"
      ;;
    systemd-credentials)
      cp "$backup_file" "$CREDENTIALS_DIRECTORY/openrouter-api-key"
      chmod 600 "$CREDENTIALS_DIRECTORY/openrouter-api-key"
      ;;
    env-file)
      cp "$backup_file" "$WORKSPACE/.env"
      chmod 600 "$WORKSPACE/.env"
      ;;
  esac

  echo "✅ Rolled back to previous key from $backup_file"
}

# --- Main logic ---
STORE=$(detect_credential_store)
echo "Detected credential store: $STORE"

if [ "$STORE" = "none" ]; then
  echo "❌ No credential store detected. Set up credentials first."
  echo "   Options:"
  echo "   - Install pass and run: pass init; pass insert total-recall/openrouter-api-key"
  echo "   - Use systemd-credentials (systemd user service)"
  echo "   - Create .env file with LLM_API_KEY=your-key"
  exit 1
fi

if [ "$ROLLBACK" = true ]; then
  # Find latest backup
  LATEST_BACKUP=$(ls -t "$WORKSPACE/security-backups"/openrouter-key_*.bak 2>/dev/null | head -1 || \
                  ls -t "$WORKSPACE/security-backups"/env_*.bak 2>/dev/null | head -1 || echo "")
  if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No backup found for rollback"
    exit 1
  fi

  echo "Rolling back using: $LATEST_BACKUP"
  rollback_key "$STORE" "$LATEST_BACKUP"
  exit 0
fi

if [ "$BACKUP_ONLY" = true ]; then
  backup_key "$STORE"
  exit 0
fi

if [ "$ROTATE_OPENROUTER" = false ]; then
  echo "❌ Specify --openrouter to rotate OpenRouter key"
  exit 1
fi

# Backup current key
backup_key "$STORE"

# Get new key
if [ -n "$NEW_KEY" ]; then
  KEY_TO_SET="$NEW_KEY"
else
  echo "Enter new OpenRouter API key:"
  read -rs KEY_TO_SET
  echo ""
fi

# Validate new key
if ! validate_key "$KEY_TO_SET"; then
  echo "❌ Key validation failed. Rotation aborted."
  echo "   Your original key is still in place."
  exit 1
fi

# Set new key
set_new_key "$STORE" "$KEY_TO_SET"

echo ""
echo "🎉 Key rotation complete!"
echo "   Old key backed up, new key validated and set."