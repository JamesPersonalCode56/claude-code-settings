#!/usr/bin/env bash
# Shared Qwen-token reader. Prints ONLY the API token to stdout, nothing else.
# Used by BOTH:
#   - claude-switch.sh `claude-qwen` (Linux/mac), and
#   - the Windows fleet settings.json `apiKeyHelper` (via `bash "<this>"`).
# This script is NON-SECRET (safe to commit). The secret lives in the sibling
# .env (gitignored, chmod 600). Honour a pre-exported CLAUDE_QWEN_ENV.
set -euo pipefail

ENV_FILE="${CLAUDE_QWEN_ENV:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env}"
PLACEHOLDER='sk-sp-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'

if [ ! -f "$ENV_FILE" ]; then
  echo "qwen-key-helper: $ENV_FILE missing — copy .env.example to .env and fill API_KEYS" >&2
  exit 1
fi

# Extract API_KEYS=... tolerating spaces around '=' and optional single/double quotes.
token="$(sed -n "s/^[[:space:]]*API_KEYS[[:space:]]*=[[:space:]]*//p" "$ENV_FILE" | head -n1)"
token="${token%\"}"; token="${token#\"}"
token="${token%\'}"; token="${token#\'}"

if [ -z "$token" ] || [ "$token" = "$PLACEHOLDER" ]; then
  echo "qwen-key-helper: API_KEYS empty or still the placeholder in $ENV_FILE — fill it with the real token" >&2
  exit 1
fi

printf '%s' "$token"
