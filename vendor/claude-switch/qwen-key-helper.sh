#!/usr/bin/env bash
# Shared API-key reader for the claude-switch endpoints. Prints ONLY the token to
# stdout, nothing else. Reads the named variable from a consolidated per-provider
# env file (base url + token + lineup; gitignored, chmod 600).
#   $1 = env var name to read (default: API_KEYS — the provider token).
# Used by BOTH:
#   - claude-switch.sh (claude-qwen / claude-deepseek on Linux/mac), and
#   - the Windows fleet settings.json `apiKeyHelper` (via `bash "<this>"`, default var).
# NON-SECRET (safe to commit). The secret lives in the consolidated env file.
# Default env file: env/models-qwen.env (two dirs up). Honour a pre-exported
# CLAUDE_QWEN_ENV to read a different provider's file.
set -euo pipefail

VAR="${1:-API_KEYS}"
ENV_FILE="${CLAUDE_QWEN_ENV:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../env" && pwd)/models-qwen.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "key-helper: $ENV_FILE missing — copy ${ENV_FILE}.example to it and fill $VAR" >&2
  exit 1
fi

# Extract VAR=... tolerating spaces around '=' and optional single/double quotes.
token="$(sed -n "s/^[[:space:]]*${VAR}[[:space:]]*=[[:space:]]*//p" "$ENV_FILE" | head -n1)"
token="${token%\"}"; token="${token#\"}"
token="${token%\'}"; token="${token#\'}"

# Reject empty or any unfilled .example placeholder (they all carry an x-run).
if [ -z "$token" ] || printf '%s' "$token" | grep -q 'xxxxxxxx'; then
  echo "key-helper: $VAR empty or still the placeholder in $ENV_FILE — fill it with the real token" >&2
  exit 1
fi

printf '%s' "$token"
