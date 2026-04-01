#!/usr/bin/env bash
# Security audit script for Total Recall
# Checks for common security issues and vulnerabilities

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/scripts/_compat.sh"

WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_DIR/../.." && pwd)}"
MEMORY_DIR="${MEMORY_DIR:-$WORKSPACE/memory}"

echo "🔒 Total Recall — Security Audit"
echo "================================"
echo "Workspace: $WORKSPACE"
echo "Memory dir: $MEMORY_DIR"
echo ""

ISSUES_FOUND=0
WARNINGS_FOUND=0

# --- Helper functions ---
check_file_perms() {
  local file="$1"
  local expected="$2"
  local description="$3"

  if [ ! -f "$file" ]; then
    echo "⚠️  $description: File not found ($file)"
    ((WARNINGS_FOUND++))
    return
  fi

  local perms
  perms=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%A' "$file" 2>/dev/null || echo "unknown")

  if [ "$perms" != "$expected" ]; then
    echo "❌ $description: Permissions are $perms, should be $expected ($file)"
    ((ISSUES_FOUND++))
  else
    echo "✅ $description: Secure permissions ($perms)"
  fi
}

check_dir_perms() {
  local dir="$1"
  local expected="$2"
  local description="$3"

  if [ ! -d "$dir" ]; then
    echo "⚠️  $description: Directory not found ($dir)"
    ((WARNINGS_FOUND++))
    return
  fi

  local perms
  perms=$(stat -c '%a' "$dir" 2>/dev/null || stat -f '%A' "$dir" 2>/dev/null || echo "unknown")

  if [ "$perms" != "$expected" ]; then
    echo "❌ $description: Permissions are $perms, should be $expected ($dir)"
    ((ISSUES_FOUND++))
  else
    echo "✅ $description: Secure permissions ($perms)"
  fi
}

check_api_key_exposure() {
  local file="$1"
  local description="$2"

  if [ ! -f "$file" ]; then
    return
  fi

  # Check for API keys in logs or other files
  if grep -q "sk-or-v1-\|sk-\|xoxb-\|xoxp-" "$file" 2>/dev/null; then
    echo "❌ $description: Potential API key exposure in $file"
    ((ISSUES_FOUND++))
  fi
}

# --- File permission checks ---
echo "Checking file permissions..."
check_file_perms "$WORKSPACE/.env" "600" ".env file"
check_dir_perms "$MEMORY_DIR" "700" "Memory directory"

# --- API key exposure checks ---
echo ""
echo "Checking for API key exposure..."
check_api_key_exposure "$WORKSPACE/logs/observer.log" "Observer logs"
check_api_key_exposure "$WORKSPACE/logs/reflector.log" "Reflector logs"
check_api_key_exposure "$MEMORY_DIR/observations.md" "Observations file"

# Find all log files and check them
while IFS= read -r -d '' logfile; do
  check_api_key_exposure "$logfile" "Log file"
done < <(find "$WORKSPACE/logs" -name "*.log" -print0 2>/dev/null || true)

# --- Configuration checks ---
echo ""
echo "Checking configuration security..."

# Check if API key is configured
if [ -f "$WORKSPACE/.env" ]; then
  if ! grep -q "^LLM_API_KEY=\|^OPENROUTER_API_KEY=" "$WORKSPACE/.env"; then
    echo "⚠️  No API key found in .env file"
    ((WARNINGS_FOUND++))
  fi
else
  echo "⚠️  No .env file found"
  ((WARNINGS_FOUND++))
fi

# Check for hardcoded keys in scripts
SCRIPT_DIR="$SKILL_DIR/scripts"
while IFS= read -r -d '' scriptfile; do
  if grep -q "sk-or-v1-\|sk-\|xoxb-\|xoxp-" "$scriptfile" 2>/dev/null; then
    echo "❌ Hardcoded API key found in script: $scriptfile"
    ((ISSUES_FOUND++))
  fi
done < <(find "$SCRIPT_DIR" -name "*.sh" -print0 2>/dev/null || true)

# --- Network security checks ---
echo ""
echo "Checking network security..."

# Check if curl calls use HTTPS
if grep -r "curl.*http://" "$SCRIPT_DIR"/*.sh >/dev/null 2>&1; then
  echo "❌ Insecure HTTP URLs found in scripts"
  ((ISSUES_FOUND++))
else
  echo "✅ Scripts use HTTPS for external calls"
fi

# --- Dependency checks ---
echo ""
echo "Checking dependencies..."

# Check for vulnerable versions (basic check)
if command -v jq >/dev/null 2>&1; then
  JQ_VERSION=$(jq --version 2>/dev/null | sed 's/[^0-9.]*//g' || echo "unknown")
  echo "ℹ️  jq version: $JQ_VERSION"
fi

if command -v curl >/dev/null 2>&1; then
  CURL_VERSION=$(curl --version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
  echo "ℹ️  curl version: $CURL_VERSION"
fi

# --- Backup security ---
echo ""
echo "Checking backup security..."
BACKUP_DIR="$WORKSPACE/security-backups"
if [ -d "$BACKUP_DIR" ]; then
  check_dir_perms "$BACKUP_DIR" "700" "Security backups directory"

  # Check backup file permissions
  while IFS= read -r -d '' backupfile; do
    check_file_perms "$backupfile" "600" "Backup file"
  done < <(find "$BACKUP_DIR" -type f -print0 2>/dev/null || true)
else
  echo "ℹ️  No security backups directory found"
fi

# --- Summary ---
echo ""
echo "================================"
if [ $ISSUES_FOUND -eq 0 ] && [ $WARNINGS_FOUND -eq 0 ]; then
  echo "🎉 Security audit passed! No issues found."
elif [ $ISSUES_FOUND -eq 0 ]; then
  echo "⚠️  Security audit completed with $WARNINGS_FOUND warnings."
  echo "   Review warnings above and address as needed."
else
  echo "❌ Security audit found $ISSUES_FOUND issues and $WARNINGS_FOUND warnings."
  echo "   Address critical issues immediately!"
fi
echo "================================"

exit $ISSUES_FOUND