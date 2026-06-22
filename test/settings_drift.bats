#!/usr/bin/env bats
# Tests for bin/settings-drift.sh — repo vs live settings.json drift detector.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/bin/settings-drift.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

@test "settings-drift: identical files report in sync (exit 0)" {
  echo '{"a":1,"env":{"x":"1"}}' >"$TMP/repo.json"
  echo '{"a":1,"env":{"x":"1"}}' >"$TMP/live.json"
  run bash "$SCRIPT" "$TMP/repo.json" "$TMP/live.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"in sync"* ]]
}

@test "settings-drift: live-only key (repo would drop it) reports drift (exit 1)" {
  echo '{"env":{"x":"1"}}' >"$TMP/repo.json"
  echo '{"env":{"x":"1","CLAUDE_CODE_ENABLE_TELEMETRY":"1"}}' >"$TMP/live.json"
  run bash "$SCRIPT" "$TMP/repo.json" "$TMP/live.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT"* ]]
  [[ "$output" == *"env.CLAUDE_CODE_ENABLE_TELEMETRY"* ]]
}

@test "settings-drift: differing value reports drift (exit 1)" {
  echo '{"model":"opus"}'      >"$TMP/repo.json"
  echo '{"model":"opus[1m]"}'  >"$TMP/live.json"
  run bash "$SCRIPT" "$TMP/repo.json" "$TMP/live.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"value differs"* ]]
  [[ "$output" == *"model"* ]]
}

@test "settings-drift: missing file exits 2" {
  echo '{}' >"$TMP/repo.json"
  run bash "$SCRIPT" "$TMP/repo.json" "$TMP/does-not-exist.json"
  [ "$status" -eq 2 ]
}
