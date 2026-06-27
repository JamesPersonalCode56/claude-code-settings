# Claude Code — dual-auth switch (subscription vs Qwen API)
# Được source từ ~/.bashrc. Định nghĩa: claude-max, claude-qwen, và wrapper `claude` hỏi chọn.
# Upstream TRỰC TIẾP (không proxy) để giữ độ chính xác từng chữ.
# Headroom (nén context, tiết kiệm token) là OPT-IN thủ công: chạy `claude-hr` khi nào cần.

# Path-relative: .env sits next to this script. Honour a pre-exported CLAUDE_QWEN_ENV if set.
CLAUDE_QWEN_ENV="${CLAUDE_QWEN_ENV:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env}"
CLAUDE_QWEN_MODELS="${CLAUDE_QWEN_MODELS:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/models.env}"
# Shared token reader — the SAME script the Windows fleet wires as settings.json
# apiKeyHelper, so the secret is read from one canonical place on both platforms.
CLAUDE_QWEN_HELPER="${CLAUDE_QWEN_HELPER:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwen-key-helper.sh}"
DEFAULT_AUTH="${DEFAULT_AUTH:-sub}"   # non-interactive default: sub | qwen

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

# --- Command B: Qwen endpoint (Alibaba Model Studio token-plan), trực tiếp ---
claude-qwen() {
  # Fail-fast: .env phải tồn tại, không thì launch sẽ thiếu auth (chạy ẩn danh / sai endpoint).
  if [ ! -f "$CLAUDE_QWEN_ENV" ]; then
    echo "claude-qwen: $CLAUDE_QWEN_ENV missing — copy .env.example to .env and fill API_KEYS" >&2
    return 1
  fi
  # Nạp models.env (model lineup — version-controlled) rồi .env (BASE_URL, API_KEYS — secret)
  # trong subshell để không rò biến ra shell hiện tại.
  (
    set -a
    [ -f "$CLAUDE_QWEN_MODELS" ] && . "$CLAUDE_QWEN_MODELS"
    . "$CLAUDE_QWEN_ENV"
    set +a
    # Fail-fast: BASE_URL/API_KEYS phải có thật + đã điền (không còn placeholder của .env.example).
    if [ -z "$BASE_URL" ] || [ -z "$API_KEYS" ] || [ "$API_KEYS" = "sk-sp-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" ]; then
      echo "claude-qwen: BASE_URL/API_KEYS chưa được điền trong $CLAUDE_QWEN_ENV — fill API_KEYS với token thật" >&2
      exit 1
    fi
    # .env dùng tên BASE_URL/API_KEYS -> map sang biến Claude Code cần. Đi thẳng tới Qwen, không proxy.
    # env -u: gỡ override autocompact global (~/.bashrc set PCT=40 cho cửa sổ 1M của Opus).
    # Qwen cửa sổ context nhỏ -> 40% chạm gần như tức thì -> compact liên tục, nên bỏ ở đây.
    # Dùng `env ... claude` (không `command`) để exec binary trực tiếp, tự bỏ qua shell function `claude`.
    # Token comes from the shared helper (parity with the Windows apiKeyHelper),
    # not inline $API_KEYS. Forward CLAUDE_QWEN_ENV so the helper reads the same file.
    # Fail-closed: abort rather than launch against the Qwen endpoint with an empty token.
    qwen_token="$(CLAUDE_QWEN_ENV="$CLAUDE_QWEN_ENV" "$CLAUDE_QWEN_HELPER")" || {
      echo "claude-qwen: qwen-key-helper.sh failed to provide a token — aborting" >&2
      exit 1
    }
    env -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u CLAUDE_CODE_AUTO_COMPACT_WINDOW \
        ANTHROPIC_BASE_URL="$BASE_URL" \
        ANTHROPIC_AUTH_TOKEN="$qwen_token" \
        OTEL_RESOURCE_ATTRIBUTES="machine=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['Self']['DNSName'].split('.')[0])" 2>/dev/null || cat "$HOME/.claude/fleet-name" 2>/dev/null || hostname),user.id=${USER:-$(whoami)},auth=qwen" \
        claude "$@"
  )
}

# --- Wrapper: gõ `claude` trần sẽ hỏi dùng gì ---
claude() {
  # Non-interactive (script, claude -p qua pipe): không hỏi, dùng DEFAULT_AUTH.
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    case "$DEFAULT_AUTH" in
      qwen) claude-qwen "$@" ;;
      *)    claude-max  "$@" ;;
    esac
    return
  fi
  echo "Chọn auth cho Claude Code:"
  echo "  1) Subscription (gói Max)"
  echo "  2) Qwen API (Alibaba token-plan)"
  printf "Lựa chọn [1/2]: "
  local choice
  read -r choice
  case "$choice" in
    1) echo "→ Subscription";   claude-max  "$@" ;;
    2) echo "→ Qwen API";       claude-qwen "$@" ;;
    *) echo "Không hợp lệ, hủy."; return 1 ;;
  esac
}
