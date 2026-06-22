#!/usr/bin/env bats
# Hermetic tests for `setup.sh --config-only`.
# Each test uses its own throwaway HOME; the real ~/.claude is never touched.

setup() {
  # Repo root = parent of this test dir.
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export CLAUDE_CONFIG_DIR="$TEST_HOME/.claude"
  export PROFILE="$TEST_HOME/.bashrc"
  touch "$PROFILE"
}

teardown() {
  [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

@test "config-only copies settings.json, CLAUDE.md and skills" {
  run bash "$REPO/setup.sh" --config-only
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
  [ -f "$CLAUDE_CONFIG_DIR/CLAUDE.md" ]
  [ -d "$CLAUDE_CONFIG_DIR/skills/graphify" ]
  [ -d "$CLAUDE_CONFIG_DIR/skills/omc-reference" ]
}

@test "installed CLAUDE.md carries the Poetry/.venv project-local rule" {
  run bash "$REPO/setup.sh" --config-only
  [ "$status" -eq 0 ]
  grep -qF "project_local_toolchains" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  grep -qF "Poetry" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  grep -qF ".venv" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
}

@test "second run is idempotent: backup created and bashrc markers stay at count 1" {
  run bash "$REPO/setup.sh" --config-only
  [ "$status" -eq 0 ]
  run bash "$REPO/setup.sh" --config-only
  [ "$status" -eq 0 ]

  # A backup of an overwritten file must exist after the second run.
  run bash -c 'ls "$CLAUDE_CONFIG_DIR"/settings.json.bak-* >/dev/null 2>&1'
  [ "$status" -eq 0 ]

  # Idempotent profile edits: each marker appears exactly once.
  ac="$(grep -cF '>>> claude-code-settings auto-compact >>>' "$PROFILE")"
  da="$(grep -cF 'Claude Code: dual-auth' "$PROFILE")"
  [ "$ac" -eq 1 ]
  [ "$da" -eq 1 ]
}

@test "--help exits 0 and prints usage with each flag" {
  run bash "$REPO/setup.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: setup.sh"* ]]
  [[ "$output" == *"--config-only"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--uninstall"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "unknown flag exits 2 and prints an error to stderr" {
  run bash "$REPO/setup.sh" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option: --nope"* ]]
}

@test "--config-only --dry-run makes ZERO changes and prints would: lines" {
  # Snapshot the temp HOME (checksums + listing) before and after.
  before="$(find "$HOME" -type f -exec sha256sum {} \; 2>/dev/null | sort; echo '--'; find "$HOME" | sort)"

  run bash "$REPO/setup.sh" --config-only --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would:"* ]]

  after="$(find "$HOME" -type f -exec sha256sum {} \; 2>/dev/null | sort; echo '--'; find "$HOME" | sort)"
  [ "$before" = "$after" ]
}

@test "--uninstall after a real install removes profile blocks and is idempotent" {
  run bash "$REPO/setup.sh" --config-only
  [ "$status" -eq 0 ]
  # Both blocks present after install.
  [ "$(grep -cF '>>> claude-code-settings auto-compact >>>' "$PROFILE")" -eq 1 ]
  [ "$(grep -cF '>>> claude-code-settings dual-auth >>>' "$PROFILE")" -eq 1 ]

  run bash "$REPO/setup.sh" --uninstall
  [ "$status" -eq 0 ]
  # Markers gone.
  [ "$(grep -cF '>>> claude-code-settings auto-compact >>>' "$PROFILE")" -eq 0 ]
  [ "$(grep -cF '>>> claude-code-settings dual-auth >>>' "$PROFILE")" -eq 0 ]
  [ "$(grep -cF 'Claude Code: dual-auth' "$PROFILE")" -eq 0 ]
  # $PROFILE was backed up before editing.
  run bash -c 'ls "$PROFILE".bak-* >/dev/null 2>&1'
  [ "$status" -eq 0 ]

  # Running uninstall again is safe (no error, nothing to do).
  run bash "$REPO/setup.sh" --uninstall
  [ "$status" -eq 0 ]
}

@test "--uninstall removes the legacy unmarked dual-auth form" {
  cat > "$PROFILE" <<'EOF'
# user top line

# ===== Claude Code: dual-auth (subscription vs Qwen API) =====
[ -f "/some/path/claude-switch.sh" ] && . "/some/path/claude-switch.sh"
# user bottom line
EOF
  run bash "$REPO/setup.sh" --uninstall
  [ "$status" -eq 0 ]
  [ "$(grep -cF '===== Claude Code: dual-auth' "$PROFILE")" -eq 0 ]
  [ "$(grep -cF 'claude-switch.sh' "$PROFILE")" -eq 0 ]
  # User's own lines are preserved (conservative removal).
  grep -qF "# user top line" "$PROFILE"
  grep -qF "# user bottom line" "$PROFILE"
}

@test "dual-auth .env is scaffolded from .env.example and ends up mode 600" {
  SWITCH_DIR="$REPO/vendor/claude-switch"
  if [ ! -f "$SWITCH_DIR/.env.example" ]; then
    skip "vendor/claude-switch/.env.example not present (submodule not initialized)"
  fi
  if [ -f "$SWITCH_DIR/.env" ]; then
    skip "vendor/claude-switch/.env already exists on this checkout (real secret) — not overwriting"
  fi

  run bash "$REPO/setup.sh" --config-only
  [ "$status" -eq 0 ]

  [ -f "$SWITCH_DIR/.env" ]
  # Content matches the example it was scaffolded from.
  cmp -s "$SWITCH_DIR/.env.example" "$SWITCH_DIR/.env"
  # Mode is owner-only (600).
  perms="$(stat -c '%a' "$SWITCH_DIR/.env")"
  [ "$perms" = "600" ]

  # Clean up the scaffolded secret so we don't leave it lying around.
  rm -f "$SWITCH_DIR/.env"
}
