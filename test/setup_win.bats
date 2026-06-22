#!/usr/bin/env bats
# Smoke tests for the Windows fleet installer (setup.win.sh) and its settings
# transform (windows/build-settings.mjs).
#
# The full installer needs a Windows host + Git Bash + portable Node, so it can't
# run end-to-end on the Linux CI box. What IS testable here — and is the
# security-critical part — is build-settings.mjs: it folds the Qwen base_url +
# token + model lineup into settings.json and strips the Linux/heavy blocks
# (rtk hook, statusLine, OMC marketplace). We drive it against a throwaway
# fixture repo so the real vendored .env is never touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WIN="$REPO/setup.win.sh"
  BUILD="$REPO/windows/build-settings.mjs"
  TMP="$(mktemp -d)"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# Build a throwaway "repo" the mjs can read: a settings.json carrying every block
# that must be stripped, plus models.env + a (good by default) secret .env.
_make_repo() {
  local key="${1:-sk-sp-REALKEY123}"
  local with_keys_line="${2:-yes}"
  mkdir -p "$TMP/repo/settings" "$TMP/repo/vendor/claude-switch"
  cat >"$TMP/repo/settings/settings.json" <<'EOF'
{
  "env": { "EXISTING": "1" },
  "permissions": { "allow": ["Bash(*)"], "defaultMode": "auto" },
  "model": "opus[1m]",
  "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "rtk hook claude" } ] } ] },
  "statusLine": { "type": "command", "command": "sh hud/omc-hud.sh" },
  "enabledPlugins": { "oh-my-claudecode@omc": true },
  "extraKnownMarketplaces": { "omc": { "source": { "source": "git", "url": "https://example/omc.git" } } }
}
EOF
  cat >"$TMP/repo/vendor/claude-switch/models.env" <<'EOF'
# non-secret lineup
ANTHROPIC_MODEL='deepseek-v4-pro[1m]'
ANTHROPIC_DEFAULT_OPUS_MODEL='glm-5.2[1m]'
EOF
  {
    echo "BASE_URL='https://fixture.example/anthropic'"
    if [ "$with_keys_line" = yes ]; then echo "API_KEYS='$key'"; fi
  } >"$TMP/repo/vendor/claude-switch/.env"
}

@test "setup.win.sh: passes bash -n syntax check" {
  run bash -n "$WIN"
  [ "$status" -eq 0 ]
}

@test "build-settings: bakes Qwen base_url + token + lineup into env" {
  command -v node >/dev/null || skip "node not available"
  _make_repo
  run node "$BUILD" "$TMP/repo" "$TMP/out.json" test-host agency
  [ "$status" -eq 0 ]
  grep -qF '"ANTHROPIC_BASE_URL": "https://fixture.example/anthropic"' "$TMP/out.json"
  grep -qF '"ANTHROPIC_AUTH_TOKEN": "sk-sp-REALKEY123"' "$TMP/out.json"
  grep -qF '"ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.2[1m]"' "$TMP/out.json"
  grep -qF '"EXISTING": "1"' "$TMP/out.json"
}

@test "build-settings: per-host OTEL machine + auth=qwen label" {
  command -v node >/dev/null || skip "node not available"
  _make_repo
  run node "$BUILD" "$TMP/repo" "$TMP/out.json" client-laptop-hp-1 agency
  [ "$status" -eq 0 ]
  grep -qF '"OTEL_RESOURCE_ATTRIBUTES": "machine=client-laptop-hp-1,user.id=agency,auth=qwen"' "$TMP/out.json"
}

@test "build-settings: strips rtk hook / statusLine / OMC marketplace" {
  command -v node >/dev/null || skip "node not available"
  _make_repo
  run node "$BUILD" "$TMP/repo" "$TMP/out.json" test-host agency
  [ "$status" -eq 0 ]
  ! grep -q '"hooks"' "$TMP/out.json"
  ! grep -q 'rtk' "$TMP/out.json"
  ! grep -q '"statusLine"' "$TMP/out.json"
  ! grep -q '"enabledPlugins"' "$TMP/out.json"
  ! grep -q '"extraKnownMarketplaces"' "$TMP/out.json"
}

@test "build-settings: refuses when API_KEYS is missing (exit 1)" {
  command -v node >/dev/null || skip "node not available"
  _make_repo "" no
  run node "$BUILD" "$TMP/repo" "$TMP/out.json" test-host agency
  [ "$status" -eq 1 ]
  [ ! -f "$TMP/out.json" ]
}

@test "build-settings: refuses the .env.example placeholder token (exit 1)" {
  command -v node >/dev/null || skip "node not available"
  _make_repo "sk-sp-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  run node "$BUILD" "$TMP/repo" "$TMP/out.json" test-host agency
  [ "$status" -eq 1 ]
  [ ! -f "$TMP/out.json" ]
}
