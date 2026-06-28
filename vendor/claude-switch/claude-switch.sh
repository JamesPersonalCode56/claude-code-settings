# shellcheck shell=bash
# Claude Code — dual-auth switch (subscription vs Qwen API vs DeepSeek API)
# Được source từ ~/.bashrc. Định nghĩa: claude-max, claude-qwen, claude-deepseek, và wrapper `claude` hỏi chọn.
# Upstream TRỰC TIẾP (không proxy) để giữ độ chính xác từng chữ.

# Per-provider env files live in the repo's env/ dir (two dirs up from this script).
# Each holds BASE_URL + API_KEYS (token) + the full model lineup (self-contained).
# Honour pre-exported overrides if set.
CLAUDE_SWITCH_ENV_DIR="${CLAUDE_SWITCH_ENV_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../env" 2>/dev/null && pwd)}"
CLAUDE_QWEN_ENV="${CLAUDE_QWEN_ENV:-$CLAUDE_SWITCH_ENV_DIR/models-qwen.env}"
CLAUDE_DEEPSEEK_ENV="${CLAUDE_DEEPSEEK_ENV:-$CLAUDE_SWITCH_ENV_DIR/models-deepseek.env}"
# Shared token reader — the SAME script the Windows fleet wires as settings.json
# apiKeyHelper, so the secret is read from one canonical place on both platforms.
CLAUDE_QWEN_HELPER="${CLAUDE_QWEN_HELPER:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwen-key-helper.sh}"
DEFAULT_AUTH="${DEFAULT_AUTH:-sub}"   # non-interactive default: sub | qwen | deepseek

# --- Command A: Claude subscription (gói Max) ---
# env -u xóa BASE_URL + biến API để chắc chắn KHÔNG dính proxy/headroom hay Qwen.
# `env` exec binary trực tiếp -> tự bỏ qua shell function `claude` (không cần `command`).
claude-max() {
  env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY \
      -u ANTHROPIC_MODEL -u ANTHROPIC_DEFAULT_SONNET_MODEL -u ANTHROPIC_DEFAULT_HAIKU_MODEL \
      -u ANTHROPIC_DEFAULT_OPUS_MODEL -u CLAUDE_CODE_SUBAGENT_MODEL -u HEADROOM_USER_ID \
      OTEL_RESOURCE_ATTRIBUTES="machine=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['Self']['DNSName'].split('.')[0])" 2>/dev/null || cat "$HOME/.claude/fleet-name" 2>/dev/null || hostname),user.id=${USER:-$(whoami)},auth=sub" \
      claude "$@"
}

# Internal: route to a provider whose env file holds BASE_URL + API_KEYS + lineup.
# $1=env file, $2=auth label (qwen|deepseek), rest=claude args.
_claude_route() {
  local envfile="$1" auth="$2"; shift 2
  if [ ! -f "$envfile" ]; then
    echo "claude-$auth: $envfile missing — copy ${envfile}.example to it and fill API_KEYS" >&2
    return 1
  fi
  (
    set -a
    # shellcheck source=/dev/null
    . "$envfile"
    set +a
    if [ -z "${BASE_URL:-}" ] || [ -z "${API_KEYS:-}" ] || printf '%s' "${API_KEYS:-}" | grep -q 'xxxxxxxx'; then
      echo "claude-$auth: BASE_URL/API_KEYS chưa được điền trong $envfile — fill API_KEYS với token thật" >&2
      exit 1
    fi
    # Token comes from the shared helper (parity with the Windows apiKeyHelper),
    # fail-closed: abort rather than launch with an empty token.
    local token
    token="$(CLAUDE_QWEN_ENV="$envfile" "$CLAUDE_QWEN_HELPER")" || {
      echo "claude-$auth: qwen-key-helper.sh failed to provide a token — aborting" >&2
      exit 1
    }
    # env -u: drop the global autocompact overrides (tuned for Opus 1M); the
    # lineup + any CLAUDE_CODE_* (e.g. EFFORT_LEVEL=max for deepseek) are already
    # exported via `set -a` and inherited. Direct upstream, no proxy.
    env -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u CLAUDE_CODE_AUTO_COMPACT_WINDOW \
        ANTHROPIC_BASE_URL="$BASE_URL" \
        ANTHROPIC_AUTH_TOKEN="$token" \
        OTEL_RESOURCE_ATTRIBUTES="machine=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['Self']['DNSName'].split('.')[0])" 2>/dev/null || cat "$HOME/.claude/fleet-name" 2>/dev/null || hostname),user.id=${USER:-$(whoami)},auth=$auth" \
        claude "$@"
  )
}

# --- Command B: Qwen endpoint (Alibaba Model Studio token-plan), trực tiếp ---
claude-qwen()     { _claude_route "$CLAUDE_QWEN_ENV" qwen "$@"; }
# --- Command C: DeepSeek native API, trực tiếp ---
claude-deepseek() { _claude_route "$CLAUDE_DEEPSEEK_ENV" deepseek "$@"; }

# --- Wrapper: gõ `claude` trần sẽ hỏi dùng gì ---
claude() {
  # Non-interactive (script, claude -p qua pipe): không hỏi, dùng DEFAULT_AUTH.
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    case "$DEFAULT_AUTH" in
      qwen)     claude-qwen     "$@" ;;
      deepseek) claude-deepseek "$@" ;;
      *)        claude-max      "$@" ;;
    esac
    return
  fi
  echo "Chọn auth cho Claude Code:"
  echo "  1) Subscription (gói Max)"
  echo "  2) Qwen API (Alibaba token-plan)"
  echo "  3) DeepSeek API (native)"
  printf "Lựa chọn [1/2/3]: "
  local choice
  read -r choice
  case "$choice" in
    1) echo "→ Subscription";   claude-max      "$@" ;;
    2) echo "→ Qwen API";       claude-qwen     "$@" ;;
    3) echo "→ DeepSeek API";   claude-deepseek "$@" ;;
    *) echo "Không hợp lệ, hủy."; return 1 ;;
  esac
}
