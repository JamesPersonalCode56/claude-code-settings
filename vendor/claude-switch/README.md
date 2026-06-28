# Claude Code — Dual auth: Subscription vs Qwen API vs DeepSeek API

Chạy song song các phiên Claude Code độc lập:
- **Command A** (`claude-max`) → gói **Max subscription** (OAuth, claude.ai login)
- **Command B** (`claude-qwen`) → **Qwen endpoint** (Alibaba Cloud Model Studio token-plan, tính theo token)
- **Command C** (`claude-deepseek`) → **DeepSeek native API**

Các process tách biệt hoàn toàn — mỗi cái có env riêng, không đụng auth của nhau.

---

## File env (per-provider)

Connection + token + model lineup nằm chung trong một file self-contained mỗi provider, ở repo `env/`:
- `env/models-qwen.env` (cho `claude-qwen`)
- `env/models-deepseek.env` (cho `claude-deepseek`)

Real file gitignored — chỉ commit bản `.example`. Ví dụ `env/models-qwen.env`:

```ini
BASE_URL='https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic'
API_KEYS='sk-sp-...'            # token của Qwen endpoint (KHÔNG commit lên git)
ANTHROPIC_MODEL='qwen3.7-max'
ANTHROPIC_DEFAULT_HAIKU_MODEL='qwen3.7-plus'
ANTHROPIC_DEFAULT_SONNET_MODEL='qwen3.7-plus'
ANTHROPIC_DEFAULT_OPUS_MODEL='qwen3.7-max'
CLAUDE_CODE_SUBAGENT_MODEL='qwen3.7-plus'
```

Đây là endpoint **Anthropic-compatible** — gọi qua `/v1/messages` với header `anthropic-version` và `x-api-key` (hoặc `Authorization: Bearer`).

---

## Cài đặt (đã thêm vào `~/.bashrc`)

```bash
# Command A — Claude subscription. env -u xóa biến API để chắc chắn KHÔNG ăn nhầm Qwen.
alias claude-max='env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY claude'

# Command B — Qwen endpoint (đọc trực tiếp từ .env này)
claude-qwen() {
  local envf="/home/minh/WORKSPACE/alibaba-cloud-AI/.env"
  local base token
  base=$(grep '^BASE_URL'  "$envf" | cut -d"'" -f2)
  token=$(grep '^API_KEYS' "$envf" | cut -d"'" -f2)
  ANTHROPIC_BASE_URL="$base" \
  ANTHROPIC_AUTH_TOKEN="$token" \
  ANTHROPIC_MODEL='qwen3.7-max' \
  ANTHROPIC_DEFAULT_SONNET_MODEL='qwen3.7-plus' \
  ANTHROPIC_DEFAULT_HAIKU_MODEL='qwen3.7-plus' \
  ANTHROPIC_DEFAULT_OPUS_MODEL='qwen3.7-max' \
  CLAUDE_CODE_SUBAGENT_MODEL='qwen3.7-plus' \
  claude "$@"
}
```

Áp dụng ngay: `source ~/.bashrc`

---

## Dùng

```bash
claude-max      # Terminal 1 → gói Max subscription
claude-qwen     # Terminal 2 → Qwen endpoint, tính token riêng
claude-deepseek # Terminal 3 → DeepSeek native API
```

Kiểm tra đang dùng auth nào: gõ `/status` trong Claude Code.

### Gọi worker Qwen headless từ một session khác
```bash
claude-qwen -p "tóm tắt file X..."     # process con, env Qwen, tách khỏi session đang chạy
```

---

## Vì sao KHÔNG thể trộn trong cùng 1 process

Một process Claude Code chỉ dùng **một** `ANTHROPIC_BASE_URL` + **một** bộ credentials cho cả main lẫn subagent.

- `CLAUDE_CODE_SUBAGENT_MODEL` chỉ đổi **tên model**, KHÔNG đổi endpoint/auth → subagent vẫn gọi cùng provider với main.
- Subscription dùng **OAuth gắn riêng cho Claude Code**, không relay qua proxy/router được; Qwen dùng `ANTHROPIC_AUTH_TOKEN`. Hai cơ chế loại trừ nhau trong một process.

→ Muốn "main = subscription, worker = Qwen" thì **bắt buộc tách thành process riêng** (2 command như trên, hoặc `omc-teams` spawn worker trong tmux pane riêng).

| Mục tiêu | Khả thi? |
|---|---|
| Subagent (Task tool) chạy Qwen, main subscription, **1 process** | ❌ |
| 2 session/process riêng: A subscription, B Qwen | ✅ |
| Main subscription tự gọi `claude-qwen -p` (process con) | ✅ |

---

## Test endpoint nhanh

```bash
cd /home/minh/WORKSPACE/alibaba-cloud-AI
BASE_URL=$(grep '^BASE_URL' .env | cut -d"'" -f2)
API_KEYS=$(grep '^API_KEYS' .env | cut -d"'" -f2)
curl -sS "$BASE_URL/v1/messages" \
  -H "x-api-key: $API_KEYS" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d '{"model":"qwen3.7-max","max_tokens":32,"messages":[{"role":"user","content":"Reply with exactly: pong"}]}'
```

Kết quả mong đợi: HTTP 200, text `pong`. Các model đã verify: `qwen3.7-max`, `qwen3.7-plus`.

---

## Lưu ý bảo mật

- `.env` chứa token thật → thêm vào `.gitignore`, đừng commit.
- Nếu lỡ `export ANTHROPIC_BASE_URL` trong shell profile, mọi `claude` sẽ ăn Qwen. `claude-max` đã `env -u` để phòng việc này, nhưng nên kiểm tra `env | grep ANTHROPIC` nếu thấy bất thường.
