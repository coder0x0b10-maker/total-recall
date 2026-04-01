# Security Guidelines for Total Recall

## Overview

Total Recall implements a multi-layer memory system for AI agents. This document outlines security best practices, threat models, and hardening procedures.

## Threat Model

### Attack Vectors

1. **API Key Exposure**
   - Leaked OpenRouter API keys could lead to unauthorized usage
   - Keys stored in `.env` files, pass, or systemd-credentials

2. **Memory Data Tampering**
   - Observations and memory files could be modified by malicious actors
   - Memory directory permissions must be restrictive

3. **Log Data Exposure**
   - Logs may contain sensitive information or partial API keys
   - Log files should be monitored for accidental key exposure

4. **Network Interception**
   - API calls to OpenRouter could be intercepted
   - TLS hardening and certificate validation required

5. **Dependency Vulnerabilities**
   - Outdated jq, curl, or Python packages
   - Supply chain attacks on PyPI packages

## Security Controls

### File Permissions

**Critical Files:**
- `.env`: `600` (owner read/write only)
- `memory/`: `700` (owner read/write/execute only)
- `security-backups/`: `700` (owner read/write/execute only)

**Verification:**
```bash
# Check permissions
ls -la .env
ls -ld memory/
ls -ld security-backups/

# Fix permissions
chmod 600 .env
chmod 700 memory/
chmod 700 security-backups/
```

### API Key Management

**Supported Storage Methods:**

1. **Password Store (pass)**
   ```bash
   # Initialize
   pass init your-gpg-key

   # Store key
   pass insert total-recall/openrouter-api-key

   # Retrieve
   pass show total-recall/openrouter-api-key
   ```

2. **systemd Credentials**
   ```bash
   # Create credential directory
   mkdir -p ~/.config/systemd/user/total-recall-watcher.service.d/

   # Create credentials file
   echo "your-api-key" > ~/.config/systemd/user/total-recall-watcher.service.d/openrouter-api-key

   # Set restrictive permissions
   chmod 600 ~/.config/systemd/user/total-recall-watcher.service.d/openrouter-api-key
   ```

3. **Environment File (.env)**
   ```bash
   # Create .env file
   echo "LLM_API_KEY=sk-or-v1-xxxxx" > .env
   chmod 600 .env
   ```

**Key Rotation:**
```bash
# Rotate OpenRouter key
./scripts/key-rotation.sh --openrouter

# Rotate with specific key
./scripts/key-rotation.sh --openrouter --key=sk-or-v1-newkey

# Backup only
./scripts/key-rotation.sh --backup-only

# Rollback
./scripts/key-rotation.sh --rollback
```

### Network Security

**TLS Hardening:**
- All API calls use TLS 1.2 minimum
- Certificate validation enabled
- Retry logic with exponential backoff

**Configuration:**
```yaml
# config/aie.yaml
llm:
  base_url: https://openrouter.ai/api/v1
  tls_min_version: 1.2
  verify_ssl: true
  timeout: 30
  retries: 3
```

### Monitoring and Auditing

**Security Audit:**
```bash
# Run comprehensive security audit
./scripts/security-audit.sh
```

**Checks Performed:**
- File permission validation
- API key exposure detection
- Hardcoded credential scanning
- HTTPS enforcement
- Dependency version monitoring

**Log Monitoring:**
```bash
# Monitor logs for security events
tail -f logs/observer.log | grep -i "error\|fail\|unauthorized"

# Search for potential key exposure
grep -r "sk-or-v1-" logs/
```

## Incident Response

### API Key Compromise

1. **Immediate Actions:**
   ```bash
   # Rotate to new key
   ./scripts/key-rotation.sh --openrouter --key=NEW_KEY

   # Revoke old key in OpenRouter dashboard
   # Monitor usage for unauthorized access
   ```

2. **Investigation:**
   ```bash
   # Check recent backups
   ls -la security-backups/

   # Audit recent log entries
   grep "openrouter\|api" logs/observer.log | tail -20
   ```

### Data Tampering

1. **Detection:**
   ```bash
   # Check file integrity (if checksums implemented)
   find memory/ -type f -exec sha256sum {} \;

   # Review recent observations
   tail -50 memory/observations.md
   ```

2. **Recovery:**
   ```bash
   # Restore from backups
   cp memory/.dream-backups/observations.md.bak memory/observations.md

   # Re-run observer to regenerate recent data
   ./scripts/observer-agent.sh
   ```

## Development Security

### Code Review Checklist

- [ ] No hardcoded API keys or credentials
- [ ] Secure file operations (no race conditions)
- [ ] Input validation on all user inputs
- [ ] Safe shell practices (no eval, proper quoting)
- [ ] Error handling doesn't leak sensitive information

### Dependency Management

```bash
# Update dependencies securely
pip install --upgrade PyYAML
sudo apt update && sudo apt upgrade jq curl

# Audit dependencies
pip audit
# Note: jq and curl don't have built-in audit tools
```

### Testing Security

**Unit Tests:**
```bash
# Test permission checks
chmod 644 .env
./scripts/security-audit.sh  # Should fail

# Test key validation
./scripts/key-rotation.sh --openrouter --key=invalid-key  # Should fail
```

## Compliance Considerations

### Data Protection

- Memory files contain conversation history
- Implement data retention policies
- Consider encryption at rest for sensitive deployments

### Privacy

- Observations may contain personal information
- Implement data minimization principles
- Provide data export/deletion capabilities

## Maintenance

### Regular Tasks

**Weekly:**
- Run security audit: `./scripts/security-audit.sh`
- Review recent logs for anomalies

**Monthly:**
- Rotate API keys proactively
- Update dependencies
- Review backup integrity

**Quarterly:**
- Full security assessment
- Update threat model
- Review access controls

### Monitoring

**Key Metrics:**
- API key usage patterns
- Failed authentication attempts
- File permission changes
- Unusual network activity

**Alerts:**
- Permission changes on critical files
- API rate limit hits
- Authentication failures
- Certificate validation errors

## Emergency Contacts

- **Security Issues:** Report to repository maintainers
- **API Key Issues:** Contact OpenRouter support
- **Data Breaches:** Follow organizational incident response plan

## Version History

- v1.0: Initial security guidelines
- Future: Add encryption at rest, audit logging, etc.