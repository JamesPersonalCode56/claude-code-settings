#!/usr/bin/env bash
# Windows-fleet installer for the claude-code-settings bundle. Runs UNDER Git Bash
# (MINGW) on a Windows host; the bundle dir it lives in IS the project folder.
# Installs portable Node + Claude Code, then copies skills + CLAUDE.md into the
# Claude config dir and writes a settings.json with the Qwen connection baked in.
#
# Cross-platform deltas vs. setup.sh (Linux): no rtk (Linux ELF), no ~/.bashrc
# dual-auth switch (Qwen creds live in settings.json `env` instead), no PATH/env
# appends to a global profile — every bind path stays under the project folder or
# the Claude config dir.
#
#   Usage:  bash setup.win.sh <fleet-name>
#   Env:    CLAUDE_CONFIG_DIR (default: $HOME/.claude)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
FLEET_NAME="${1:-$(hostname)}"
USER_ID="${USERNAME:-${USER:-agency}}"

say() { printf '%s\n' "[setup.win] $*"; }

backup_then_copy() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
    cp -f "$dst" "$dst.bak-$(date +%Y%m%d%H%M%S)"
  fi
  cp -f "$src" "$dst"
}

# [1/4] portable Node + Claude Code (idempotent + self-healing) ------------------
# Resolve node + a WORKING claude. A partial npm install can leave claude.cmd present
# but its claude.exe missing, so gate on `claude --version` actually succeeding, not
# just on file presence — otherwise a pre-existing broken install is silently kept.
resolve_claude() {
  NODE_EXE="$(ls -1 "$HOME"/nodejs/node-*-win-x64/node.exe 2>/dev/null | head -1 || true)"
  [ -n "$NODE_EXE" ] || return 1
  NODE_DIR="$(dirname "$NODE_EXE")"
  CLAUDE_CMD="$(ls -1 "$NODE_DIR/claude.cmd" "$HOME"/AppData/Roaming/npm/claude.cmd 2>/dev/null | head -1 || true)"
  [ -n "$CLAUDE_CMD" ] || return 1
  "$CLAUDE_CMD" --version >/dev/null 2>&1
}
if ! resolve_claude; then
  say "installing/repairing portable Node + @anthropic-ai/claude-code ..."
  powershell -NoProfile -ExecutionPolicy Bypass -File "$HERE/windows/install-node-claude.ps1"
  resolve_claude || { say "ERROR: no working claude after install"; exit 1; }
fi
say "node:   $("$NODE_EXE" --version)"
say "claude: $("$CLAUDE_CMD" --version 2>/dev/null | head -1)"

# [2/4] config dir + skills ------------------------------------------------------
mkdir -p "$CC/skills"
for d in "$HERE"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  # back up an existing skill OUT of the scanned skills/ dir (avoid dup registration)
  if [ -d "$CC/skills/$name" ]; then
    mkdir -p "$CC/skills-backups"
    rm -rf "$CC/skills-backups/$name.bak-prev"
    cp -r "$CC/skills/$name" "$CC/skills-backups/$name.bak-prev"
    rm -rf "$CC/skills/$name"
  fi
  cp -r "$d" "$CC/skills/$name"
  say "skill: $name"
done

# [3/4] CLAUDE.md (global user instructions) ------------------------------------
backup_then_copy "$HERE/claude-md/CLAUDE.md" "$CC/CLAUDE.md"
say "CLAUDE.md installed"

# [4/4] settings.json with Qwen creds baked in ----------------------------------
TMP_SETTINGS="$CC/settings.json.new"
"$NODE_EXE" "$HERE/windows/build-settings.mjs" "$HERE" "$TMP_SETTINGS" "$FLEET_NAME" "$USER_ID"
backup_then_copy "$TMP_SETTINGS" "$CC/settings.json"
rm -f "$TMP_SETTINGS"

say "DONE — config dir: $CC ; fleet-name: $FLEET_NAME"
