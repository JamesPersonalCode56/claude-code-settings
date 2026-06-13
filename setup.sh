#!/usr/bin/env bash
# Apply this captured Claude Code configuration onto the current machine.
# Idempotent: existing files are backed up to <name>.bak-<timestamp> before
# being overwritten. Run from the repo root:  bash setup.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$CC" "$CC/skills"

backup_then_copy() { # src dst
  local src="$1" dst="$2"
  if [[ -e "$dst" ]]; then cp -a "$dst" "$dst.bak-$TS"; echo "  backed up $dst -> $dst.bak-$TS"; fi
  cp -a "$src" "$dst"; echo "  installed $dst"
}

echo "[1/5] settings + OMC config"
backup_then_copy "$REPO/settings/settings.json"  "$CC/settings.json"
backup_then_copy "$REPO/settings/omc-config.json" "$CC/.omc-config.json"

echo "[2/5] global instructions (CLAUDE.md / RTK.md)"
backup_then_copy "$REPO/claude-md/CLAUDE.md" "$CC/CLAUDE.md"
backup_then_copy "$REPO/claude-md/RTK.md"    "$CC/RTK.md"

echo "[3/5] local skills"
for s in "$REPO"/skills/*/; do
  name="$(basename "$s")"
  [[ -e "$CC/skills/$name" ]] && { cp -a "$CC/skills/$name" "$CC/skills/$name.bak-$TS"; echo "  backed up skill $name"; }
  rm -rf "$CC/skills/$name"; cp -a "$s" "$CC/skills/$name"; echo "  installed skill $name"
done

echo "[4/5] auto-compact env vars"
PROFILE="${PROFILE:-$HOME/.bashrc}"
MARK="# >>> claude-code-settings auto-compact >>>"
if grep -qF "$MARK" "$PROFILE" 2>/dev/null; then
  echo "  already present in $PROFILE (skipping; edit there to change)"
else
  {
    echo ""
    echo "$MARK"
    cat "$REPO/env/auto-compact.env" | grep -E '^export '
    echo "# <<< claude-code-settings auto-compact <<<"
  } >> "$PROFILE"
  echo "  appended exports to $PROFILE (open a NEW shell / Claude session to apply)"
fi
echo "  NOTE (Windows host w/ Qwen): set these with setx instead, e.g."
echo "       setx CLAUDE_CODE_AUTO_COMPACT_WINDOW 1000000"
echo "       setx CLAUDE_AUTOCOMPACT_PCT_OVERRIDE 40"

echo "[5/5] plugins + MCP (manual / auto)"
echo "  Plugins: settings.json carries enabledPlugins + extraKnownMarketplaces,"
echo "    so Claude Code auto-installs them on next launch. Desired state is"
echo "    documented in plugins/known_marketplaces.json + installed_plugins.json."
echo "    Enabled here: oh-my-claudecode@omc, rust-analyzer-lsp@claude-plugins-official"
echo "  MCP: mcp/mcpServers.json defines 'rcp-bridge' with a MACHINE-SPECIFIC path"
echo "    ($(python3 -c "import json;print(json.load(open('$REPO/mcp/mcpServers.json'))['rcp-bridge']['command'])" 2>/dev/null || echo 'see mcp/mcpServers.json'))."
echo "    Edit the path for this machine, then register e.g.:"
echo "       claude mcp add-json rcp-bridge \"\$(cat mcp/mcpServers.json | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)[\"rcp-bridge\"]))')\""

echo ""
echo "Done. Restart Claude Code (and open a fresh shell) for everything to apply."
