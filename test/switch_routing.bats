#!/usr/bin/env bats
# Hermetic tests for vendor/claude-switch/claude-switch.sh routing + guards.
#
# Strategy: put a stub `claude` first on PATH that just prints the auth-relevant
# env it was invoked with, then source the switch and call the wrapper. We never
# touch the real vendored .env: CLAUDE_QWEN_ENV is overridden to a temp file the
# test owns. Each call is run non-interactively (run captures piped stdio, so the
# wrapper's `[ ! -t 0 ]` branch fires and uses DEFAULT_AUTH).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWITCH="$REPO/vendor/claude-switch/claude-switch.sh"
  TEST_TMP="$(mktemp -d)"

  # Stub `claude` that records the env it ran with.
  STUB_BIN="$TEST_TMP/bin"
  mkdir -p "$STUB_BIN"
  cat >"$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "STUB_CLAUDE_RAN"
echo "BASE_URL=${ANTHROPIC_BASE_URL-<unset>}"
echo "AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN-<unset>}"
echo "MODEL=${ANTHROPIC_MODEL-<unset>}"
echo "ARGS=$*"
EOF
  chmod +x "$STUB_BIN/claude"
  export PATH="$STUB_BIN:$PATH"

  # Point the switch at a test-owned env file (never the real vendored .env).
  export CLAUDE_QWEN_ENV="$TEST_TMP/.env"
  export CLAUDE_QWEN_MODELS="$TEST_TMP/models.env"
}

teardown() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
}

# Helper: write a fully-filled (non-placeholder) qwen .env.
_write_good_env() {
  cat >"$CLAUDE_QWEN_ENV" <<'EOF'
BASE_URL='https://token-plan.example/apps/anthropic'
API_KEYS='sk-sp-REALTOKEN0000000000000000000000000000000000'
ANTHROPIC_MODEL='qwen3.7-max[1m]'
EOF
}

@test "switch file is present (submodule initialized)" {
  [ -f "$SWITCH" ] || skip "vendor/claude-switch/claude-switch.sh missing (submodule not initialized)"
}

@test "non-interactive default routes to claude-max and STRIPS base/token" {
  [ -f "$SWITCH" ] || skip "switch missing"
  # Pollute env to prove claude-max strips it.
  run bash -c '
    export ANTHROPIC_BASE_URL="https://should-be-stripped"
    export ANTHROPIC_AUTH_TOKEN="tok-should-be-stripped"
    unset DEFAULT_AUTH
    . "'"$SWITCH"'"
    claude hello </dev/null
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB_CLAUDE_RAN"* ]]
  [[ "$output" == *"BASE_URL=<unset>"* ]]
  [[ "$output" == *"AUTH_TOKEN=<unset>"* ]]
  [[ "$output" == *"ARGS=hello"* ]]
}

@test "DEFAULT_AUTH=qwen with a filled .env routes to claude-qwen with base set" {
  [ -f "$SWITCH" ] || skip "switch missing"
  _write_good_env
  run bash -c '
    export DEFAULT_AUTH=qwen
    . "'"$SWITCH"'"
    claude hi </dev/null
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB_CLAUDE_RAN"* ]]
  [[ "$output" == *"BASE_URL=https://token-plan.example/apps/anthropic"* ]]
  [[ "$output" == *"AUTH_TOKEN=sk-sp-REALTOKEN0000000000000000000000000000000000"* ]]
}

@test "guard: missing .env => claude-qwen fails non-zero and stub does NOT run" {
  [ -f "$SWITCH" ] || skip "switch missing"
  rm -f "$CLAUDE_QWEN_ENV"
  run bash -c '
    export DEFAULT_AUTH=qwen
    . "'"$SWITCH"'"
    claude hi </dev/null
  '
  [ "$status" -ne 0 ]
  [[ "$output" != *"STUB_CLAUDE_RAN"* ]]
  [[ "$output" == *"missing"* ]]
}

@test "guard: placeholder API_KEYS => claude-qwen fails non-zero and stub does NOT run" {
  [ -f "$SWITCH" ] || skip "switch missing"
  cat >"$CLAUDE_QWEN_ENV" <<'EOF'
BASE_URL='https://token-plan.example/apps/anthropic'
API_KEYS='sk-sp-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
EOF
  run bash -c '
    export DEFAULT_AUTH=qwen
    . "'"$SWITCH"'"
    claude hi </dev/null
  '
  [ "$status" -ne 0 ]
  [[ "$output" != *"STUB_CLAUDE_RAN"* ]]
}

@test "claude-qwen sources models.env before .env (model lineup is version-controlled)" {
  [ -f "$SWITCH" ] || skip "switch missing"
  # .env has the secret/connection but NO model; models.env supplies the model.
  cat >"$CLAUDE_QWEN_ENV" <<'EOF'
BASE_URL='https://token-plan.example/apps/anthropic'
API_KEYS='sk-sp-REALTOKEN0000000000000000000000000000000000'
EOF
  cat >"$CLAUDE_QWEN_MODELS" <<'EOF'
ANTHROPIC_MODEL='sentinel-model-from-models-env'
EOF
  run bash -c '
    export DEFAULT_AUTH=qwen
    . "'"$SWITCH"'"
    claude hi </dev/null
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB_CLAUDE_RAN"* ]]
  [[ "$output" == *"MODEL=sentinel-model-from-models-env"* ]]
}
