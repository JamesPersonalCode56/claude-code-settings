#!/usr/bin/env bash
# Bootstrap + apply this captured Claude Code configuration onto the current
# machine / user. Idempotent: existing config files are backed up to
# <name>.bak-<timestamp> before being overwritten.
#
#   bash setup.sh                # full bootstrap: install missing tools + config
#   bash setup.sh --config-only  # only copy config (old behaviour, no installs)
#
# Tool installs (claude / omc / rtk / mcp-bridge) are best-effort: a failure
# warns and continues so the config part still lands. Re-run any time.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pull in submodules (vendor/claude-switch) so a non-recursive clone still works.
git -C "$REPO" submodule update --init --recursive >/dev/null 2>&1 || true
CC="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TS="$(date +%Y%m%d-%H%M%S)"
BIN="$HOME/.local/bin"
BOOTSTRAP=1
[[ "${1:-}" == "--config-only" ]] && BOOTSTRAP=0

mkdir -p "$CC" "$CC/skills" "$BIN"

have()  { command -v "$1" >/dev/null 2>&1; }
warn()  { echo "  !! $*" >&2; }
ok()    { echo "  ok $*"; }

backup_then_copy() { # src dst
  local src="$1" dst="$2"
  if [[ -e "$dst" ]]; then cp -a "$dst" "$dst.bak-$TS"; echo "  backed up $dst -> $dst.bak-$TS"; fi
  cp -a "$src" "$dst"; echo "  installed $dst"
}

# ----------------------------------------------------------------------------
if [[ $BOOTSTRAP -eq 1 ]]; then
echo "[0/7] bootstrap tools (claude / omc / rtk)"

# --- Claude Code CLI (native installer) ---
if have claude; then ok "claude present ($(claude --version 2>/dev/null | head -1))"
else
  echo "  installing Claude Code (native installer)…"
  if curl -fsSL https://claude.ai/install.sh | bash; then ok "claude installed"
  else warn "claude install failed — install manually: curl -fsSL https://claude.ai/install.sh | bash"; fi
fi

# --- oh-my-claudecode (omc) — npm global ---
if have omc; then ok "omc present"
elif have npm; then
  echo "  installing omc (npm i -g oh-my-claude-sisyphus)…"
  npm i -g oh-my-claude-sisyphus >/dev/null 2>&1 && ok "omc installed" \
    || warn "omc install failed — run: npm i -g oh-my-claude-sisyphus"
else warn "npm not found — install Node.js, then: npm i -g oh-my-claude-sisyphus"
fi

# --- rtk (Rust Token Killer) — custom static binary, no public registry ---
# settings.json hooks call rtk; missing rtk => hooks error. It is a static-pie
# x86-64 ELF, so copying the binary works on any x86-64 Linux. Looks for a
# source binary via $RTK_SRC, then known locations.
if have rtk; then ok "rtk present ($(rtk --version 2>/dev/null))"
else
  RTK_FOUND=""
  for cand in "${RTK_SRC:-}" "$REPO/bin/rtk" "$BIN/rtk" /usr/local/bin/rtk; do
    [[ -n "$cand" && -x "$cand" ]] && { RTK_FOUND="$cand"; break; }
  done
  if [[ -n "$RTK_FOUND" ]]; then
    cp -a "$RTK_FOUND" "$BIN/rtk"; chmod +x "$BIN/rtk"; ok "rtk copied from $RTK_FOUND -> $BIN/rtk"
  else
    warn "rtk not found and no source binary. settings.json hooks need it."
    warn "  -> copy it: cp /path/to/rtk $BIN/rtk   (or set RTK_SRC=/path/to/rtk and re-run)"
  fi
fi

# Make sure ~/.local/bin is on PATH for future shells.
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN"; then
  PROFILE_PATH="${PROFILE:-$HOME/.bashrc}"
  grep -qF 'HOME/.local/bin' "$PROFILE_PATH" 2>/dev/null \
    || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE_PATH"
  ok "added ~/.local/bin to PATH in $PROFILE_PATH"
fi
fi  # end BOOTSTRAP

# ----------------------------------------------------------------------------
echo "[1/7] settings + OMC config"
backup_then_copy "$REPO/settings/settings.json"  "$CC/settings.json"
backup_then_copy "$REPO/settings/omc-config.json" "$CC/.omc-config.json"

echo "[2/7] global instructions (CLAUDE.md / RTK.md)"
backup_then_copy "$REPO/claude-md/CLAUDE.md" "$CC/CLAUDE.md"
backup_then_copy "$REPO/claude-md/RTK.md"    "$CC/RTK.md"

echo "[3/7] local skills"
for s in "$REPO"/skills/*/; do
  name="$(basename "$s")"
  [[ -e "$CC/skills/$name" ]] && { cp -a "$CC/skills/$name" "$CC/skills/$name.bak-$TS"; echo "  backed up skill $name"; }
  rm -rf "$CC/skills/$name"; cp -a "$s" "$CC/skills/$name"; echo "  installed skill $name"
done

echo "[4/7] auto-compact env vars"
PROFILE="${PROFILE:-$HOME/.bashrc}"
MARK="# >>> claude-code-settings auto-compact >>>"
if grep -qF "$MARK" "$PROFILE" 2>/dev/null; then
  echo "  already present in $PROFILE (skipping; edit there to change)"
else
  {
    echo ""
    echo "$MARK"
    grep -E '^export ' "$REPO/env/auto-compact.env"
    echo "# <<< claude-code-settings auto-compact <<<"
  } >> "$PROFILE"
  echo "  appended exports to $PROFILE (open a NEW shell / Claude session to apply)"
fi

echo "[5/7] plugins"
echo "  settings.json carries enabledPlugins + extraKnownMarketplaces, so Claude"
echo "  Code auto-installs them on next launch (oh-my-claudecode@omc,"
echo "  rust-analyzer-lsp@claude-plugins-official). Desired state documented in"
echo "  plugins/known_marketplaces.json + installed_plugins.json."

echo "[6/7] MCP servers"
echo "  rcp / browser-app MCP are prod-hosted and injected externally"
echo "  (out of this repo's scope) — nothing to register here."

echo "[7/7] dual-auth (Qwen / Anthropic-sub switch) — optional"
# Dual-auth switch ships as the vendored submodule (pulled by `submodule update` above).
SWITCH="$REPO/vendor/claude-switch/claude-switch.sh"
# Scaffold the secret file if missing so the user knows to fill it.
SWITCH_DIR="$(dirname "$SWITCH")"
if [[ ! -f "$SWITCH_DIR/.env" && -f "$SWITCH_DIR/.env.example" ]]; then
  cp "$SWITCH_DIR/.env.example" "$SWITCH_DIR/.env"
  chmod 600 "$SWITCH_DIR/.env"  # holds a real API token — keep it owner-only
  warn "fill API_KEYS in vendor/claude-switch/.env (scaffolded from .env.example)"
fi
if [[ -f "$SWITCH" ]]; then
  if grep -qF "$SWITCH" "$PROFILE" 2>/dev/null; then
    echo "  already sourced in $PROFILE"
  else
    {
      echo ""
      echo "# ===== Claude Code: dual-auth (subscription vs Qwen API) ====="
      echo "[ -f \"$SWITCH\" ] && . \"$SWITCH\""
    } >> "$PROFILE"
    ok "appended dual-auth source to $PROFILE"
  fi
else
  warn "$SWITCH missing — run: git -C \"$REPO\" submodule update --init vendor/claude-switch"
fi

echo ""
echo "Done. Remaining MANUAL steps:"
echo "  1. Open a NEW shell (or: source $PROFILE) so PATH + env vars apply."
echo "  2. Log in to Claude Code:  claude   (then follow the auth prompt)."
echo "     Credentials are per-user and intentionally NOT in this repo."
echo "  3. Launch claude once so it auto-installs the enabled plugins."
