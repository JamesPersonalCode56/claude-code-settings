#!/usr/bin/env bash
# Bootstrap + apply this captured Claude Code configuration onto the current
# machine / user. Idempotent: existing config files are backed up to
# <name>.bak-<timestamp> before being overwritten.
#
#   bash setup.sh                # full bootstrap: install missing tools + config
#   bash setup.sh --config-only  # only copy config (old behaviour, no installs)
#   bash setup.sh --dry-run      # print the plan; make NO changes
#   bash setup.sh --uninstall    # remove this bundle's footprint from $PROFILE
#   bash setup.sh --help         # show usage
#
# Tool installs (claude / omc / rtk / mcp-bridge) are best-effort: a failure
# warns and continues so the config part still lands. Re-run any time.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: setup.sh [--config-only] [--dry-run] [--uninstall] [--help]

Bootstrap + apply this captured Claude Code configuration onto the current
machine / user. Idempotent: existing config files are backed up to
<name>.bak-<timestamp> before being overwritten.

Flags:
  --config-only   Only copy config (CLAUDE.md / RTK.md / settings / skills /
                  profile blocks). Skip all tool installs (claude / omc / rtk)
                  and the PATH append. This is the old default behaviour.
  --dry-run       Print every mutating action as "would: <action>" and make NO
                  writes. The real $HOME / $CLAUDE_CONFIG_DIR / $PROFILE are left
                  byte-for-byte unchanged. Combinable: "--config-only --dry-run"
                  shows just the config plan; "--dry-run" alone shows the full
                  bootstrap plan.
  --uninstall     Remove this bundle's footprint from $PROFILE (the auto-compact
                  and dual-auth blocks, marked + legacy forms). $PROFILE is
                  backed up first. Installed config files under
                  $CLAUDE_CONFIG_DIR and copied binaries are NOT deleted —
                  the exact restore/remove commands are printed instead. Safe to
                  run twice. Does not bootstrap or copy config.
  -h, --help      Show this help and exit.

Remaining MANUAL steps after a real install:
  1. Open a NEW shell (or: source $PROFILE) so PATH + env vars apply.
  2. Log in to Claude Code:  claude   (then follow the auth prompt).
  3. Launch claude once so it auto-installs the enabled plugins.
USAGE
}

# ---- strict argument parsing -----------------------------------------------
BOOTSTRAP=1
DRY=0
UNINSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-only) BOOTSTRAP=0 ;;
    --dry-run)     DRY=1 ;;
    --uninstall)   UNINSTALL=1 ;;
    -h|--help)     usage; exit 0 ;;
    *)
      echo "setup.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# do_or_echo: run the command, or under --dry-run just print "would: ...".
# Usage: do_or_echo "human description" cmd arg arg...
do_or_echo() {
  local desc="$1"; shift
  if [[ $DRY -eq 1 ]]; then
    echo "  would: $desc"
  else
    "$@"
  fi
}
CC="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TS="$(date +%Y%m%d-%H%M%S)"
BIN="$HOME/.local/bin"
PROFILE="${PROFILE:-$HOME/.bashrc}"

have()  { command -v "$1" >/dev/null 2>&1; }
warn()  { echo "  !! $*" >&2; }
ok()    { echo "  ok $*"; }

backup_then_copy() { # src dst
  local src="$1" dst="$2"
  if [[ $DRY -eq 1 ]]; then
    [[ -e "$dst" ]] && echo "  would: back up $dst -> $dst.bak-$TS"
    echo "  would: install $dst (from $src)"
    return 0
  fi
  if [[ -e "$dst" ]]; then cp -a "$dst" "$dst.bak-$TS"; echo "  backed up $dst -> $dst.bak-$TS"; fi
  cp -a "$src" "$dst"; echo "  installed $dst"
}

# Markers used to delimit the blocks we append to $PROFILE so --uninstall can
# remove them cleanly.
AC_BEGIN="# >>> claude-code-settings auto-compact >>>"
AC_END="# <<< claude-code-settings auto-compact <<<"
DA_BEGIN="# >>> claude-code-settings dual-auth >>>"
DA_END="# <<< claude-code-settings dual-auth <<<"
# Legacy (unmarked) dual-auth header from older installs — kept so users who
# installed before the marked form can still uninstall cleanly.
DA_LEGACY="# ===== Claude Code: dual-auth (subscription vs Qwen API) ====="

# remove_marked_block FILE BEGIN END : delete an inclusive BEGIN..END block
# (plus a single blank line immediately preceding BEGIN, matching how we append
# one). Operates in place. No-op if BEGIN is absent.
remove_marked_block() {
  local file="$1" begin="$2" end="$3"
  [[ -f "$file" ]] || return 0
  grep -qF "$begin" "$file" || return 0
  local tmp; tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { drop=1; if (blanks>0) { blanks=0 } next }
    drop    { if ($0 == e) { drop=0 } next }
    /^[[:space:]]*$/ { blanks++; buf[blanks]=$0; next }
    { for (i=1;i<=blanks;i++) print buf[i]; blanks=0; print }
    END { for (i=1;i<=blanks;i++) print buf[i] }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# remove_legacy_dualauth FILE : delete the old unmarked dual-auth header line,
# the `[ -f ... ] && . ...` source line that follows it, and a single blank line
# immediately preceding the header (matching how older installs appended it).
remove_legacy_dualauth() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -qF "$DA_LEGACY" "$file" || return 0
  local tmp; tmp="$(mktemp)"
  awk -v hdr="$DA_LEGACY" '
    # Buffer at most one pending blank line so we can drop it if the header
    # turns out to follow it.
    $0 == hdr      { pendblank=0; skipnext=1; next }
    skipnext       { skipnext=0; if ($0 ~ /claude-switch\.sh/) next }
    /^[[:space:]]*$/ { if (pendblank) print ""; pendblank=1; next }
    { if (pendblank) { print ""; pendblank=0 } print }
    END { if (pendblank) print "" }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# ---- uninstall mode: clean $PROFILE blocks, then exit ----------------------
if [[ $UNINSTALL -eq 1 ]]; then
  echo "[uninstall] removing claude-code-settings footprint from $PROFILE"
  if [[ ! -f "$PROFILE" ]]; then
    echo "  $PROFILE does not exist — nothing to remove."
  else
    had_ac=0; had_da=0; had_legacy=0
    grep -qF "$AC_BEGIN"  "$PROFILE" && had_ac=1
    grep -qF "$DA_BEGIN"  "$PROFILE" && had_da=1
    grep -qF "$DA_LEGACY" "$PROFILE" && had_legacy=1
    if [[ $had_ac -eq 0 && $had_da -eq 0 && $had_legacy -eq 0 ]]; then
      echo "  no claude-code-settings blocks present in $PROFILE — nothing to do."
    elif [[ $DRY -eq 1 ]]; then
      echo "  would: back up $PROFILE -> $PROFILE.bak-$TS"
      [[ $had_ac -eq 1 ]]     && echo "  would: remove auto-compact block from $PROFILE"
      [[ $had_da -eq 1 ]]     && echo "  would: remove dual-auth block (marked) from $PROFILE"
      [[ $had_legacy -eq 1 ]] && echo "  would: remove dual-auth block (legacy) from $PROFILE"
    else
      cp -a "$PROFILE" "$PROFILE.bak-$TS"; echo "  backed up $PROFILE -> $PROFILE.bak-$TS"
      remove_marked_block "$PROFILE" "$AC_BEGIN" "$AC_END"
      remove_marked_block "$PROFILE" "$DA_BEGIN" "$DA_END"
      remove_legacy_dualauth "$PROFILE"
      [[ $had_ac -eq 1 ]]     && ok "removed auto-compact block from $PROFILE"
      [[ $had_da -eq 1 ]]     && ok "removed dual-auth block (marked) from $PROFILE"
      [[ $had_legacy -eq 1 ]] && ok "removed dual-auth block (legacy) from $PROFILE"
    fi
  fi
  echo ""
  echo "[uninstall] config files + binaries are left in place (CONSERVATIVE)."
  echo "  Installed config under $CC and copied binaries are NOT auto-removed."
  echo "  To restore a backed-up config file from before this bundle, pick the"
  echo "  newest *.bak-* next to it, e.g.:"
  echo "    ls -t \"$CC\"/settings.json.bak-* 2>/dev/null | head -1"
  echo "    # then: cp -a <that-file> \"$CC/settings.json\""
  echo "  Or remove an installed file outright, e.g.:  rm -f \"$CC/settings.json\""
  echo "  Copied binary (if you want it gone):          rm -f \"$BIN/rtk\""
  echo "[uninstall] done."
  exit 0
fi

# Pull in submodules (vendor/claude-switch) so a non-recursive clone still works.
# Best-effort: surface a real failure (don't swallow it) but keep going so the
# rest of the config still lands.
if [[ $DRY -eq 1 ]]; then
  echo "  would: git submodule update --init --recursive (vendor/claude-switch)"
elif ! git -C "$REPO" submodule update --init --recursive >/dev/null 2>&1; then
  echo "  !! submodule init failed — run: git submodule update --init --recursive" >&2
  echo "  !! the dual-auth switch will be missing until then; continuing with config." >&2
fi

do_or_echo "mkdir -p $CC $CC/skills $BIN" mkdir -p "$CC" "$CC/skills" "$BIN"

# ----------------------------------------------------------------------------
if [[ $BOOTSTRAP -eq 1 ]]; then
echo "[0/7] bootstrap tools (claude / omc / rtk)"

# --- Claude Code CLI (native installer) ---
if have claude; then ok "claude present ($(claude --version 2>/dev/null | head -1))"
elif [[ $DRY -eq 1 ]]; then
  echo "  would: install Claude Code (curl -fsSL https://claude.ai/install.sh | bash)"
else
  echo "  installing Claude Code (native installer)…"
  if curl -fsSL https://claude.ai/install.sh | bash; then ok "claude installed"
  else warn "claude install failed — install manually: curl -fsSL https://claude.ai/install.sh | bash"; fi
fi

# --- oh-my-claudecode (omc) — npm global ---
if have omc; then ok "omc present"
elif [[ $DRY -eq 1 ]]; then
  echo "  would: install omc (npm i -g oh-my-claude-sisyphus)"
elif have npm; then
  echo "  installing omc (npm i -g oh-my-claude-sisyphus)…"
  npm i -g oh-my-claude-sisyphus >/dev/null 2>&1 && ok "omc installed" \
    || warn "omc install failed — run: npm i -g oh-my-claude-sisyphus"
else warn "npm not found — install Node.js, then: npm i -g oh-my-claude-sisyphus"
fi

# --- rtk (Rust Token Killer) — custom static binary, no public registry ---
# settings.json hooks call rtk; missing rtk => hooks error. It is a static-pie
# x86-64 ELF, so copying the binary works on any x86-64 Linux. The binary is NOT
# committed to this repo — it is published as the `rtk` asset on the GitHub
# Release and downloaded here, then verified against the recorded bin/rtk.sha256
# before install. Override the source with $RTK_SRC (a local binary) or $RTK_URL.
RTK_URL="${RTK_URL:-https://github.com/JamesPersonalCode56/claude-code-settings/releases/download/v1.0.0/rtk}"
if have rtk; then ok "rtk present ($(rtk --version 2>/dev/null))"
else
  # Resolve a candidate binary: $RTK_SRC (local) first, else download $RTK_URL.
  RTK_FOUND=""
  RTK_TMP=""
  if [[ -n "${RTK_SRC:-}" && -x "${RTK_SRC:-}" ]]; then
    RTK_FOUND="$RTK_SRC"
  elif [[ $DRY -eq 1 ]]; then
    echo "  would: download rtk from $RTK_URL, verify sha256, install to $BIN/rtk"
  elif have curl; then
    RTK_TMP="$(mktemp)"
    if curl -fsSL "$RTK_URL" -o "$RTK_TMP"; then
      RTK_FOUND="$RTK_TMP"
    else
      warn "rtk download failed from $RTK_URL — skipping (settings.json hooks need it)."
      warn "  -> set RTK_SRC=/path/to/rtk and re-run, or check the release."
      rm -f "$RTK_TMP"; RTK_TMP=""
    fi
  else
    warn "curl not found — cannot download rtk. settings.json hooks need it."
    warn "  -> install curl, or set RTK_SRC=/path/to/rtk and re-run."
  fi

  # Verify the candidate against bin/rtk.sha256 (canonical expected hash) before
  # installing. Applies to BOTH $RTK_SRC and the downloaded file. Best-effort:
  # warn + skip on mismatch, never install unverified, never hard-exit.
  if [[ -n "$RTK_FOUND" ]]; then
    RTK_OK=1
    if [[ -f "$REPO/bin/rtk.sha256" ]]; then
      WANT="$(awk '{print $1}' "$REPO/bin/rtk.sha256")"
      GOT="$(sha256sum "$RTK_FOUND" | awk '{print $1}')"
      if [[ "$WANT" != "$GOT" ]]; then
        RTK_OK=0
        warn "rtk sha256 MISMATCH for $RTK_FOUND"
        warn "  expected $WANT"
        warn "  got      $GOT"
        warn "  refusing to install an unverified rtk — skipping (settings.json hooks need it)."
        warn "  -> set RTK_SRC=/path/to/rtk and re-run, or check the release."
      else
        ok "rtk sha256 verified against bin/rtk.sha256"
      fi
    else
      warn "bin/rtk.sha256 missing — installing rtk WITHOUT verification."
    fi
    if [[ $RTK_OK -eq 1 ]]; then
      cp "$RTK_FOUND" "$BIN/rtk"; chmod +x "$BIN/rtk"; ok "rtk installed -> $BIN/rtk"
    fi
  fi
  [[ -n "$RTK_TMP" ]] && rm -f "$RTK_TMP"
fi

# Make sure ~/.local/bin is on PATH for future shells.
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN"; then
  PROFILE_PATH="${PROFILE:-$HOME/.bashrc}"
  if grep -qF 'HOME/.local/bin' "$PROFILE_PATH" 2>/dev/null; then
    ok "PATH already has ~/.local/bin in $PROFILE_PATH"
  elif [[ $DRY -eq 1 ]]; then
    echo "  would: append 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to $PROFILE_PATH"
  else
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE_PATH"
    ok "added ~/.local/bin to PATH in $PROFILE_PATH"
  fi
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
  if [[ $DRY -eq 1 ]]; then
    [[ -e "$CC/skills/$name" ]] && echo "  would: back up skill $name -> $CC/skills/$name.bak-$TS"
    echo "  would: install skill $name -> $CC/skills/$name"
    continue
  fi
  [[ -e "$CC/skills/$name" ]] && { cp -a "$CC/skills/$name" "$CC/skills/$name.bak-$TS"; echo "  backed up skill $name"; }
  rm -rf "$CC/skills/$name"; cp -a "$s" "$CC/skills/$name"; echo "  installed skill $name"
done

echo "[4/7] auto-compact env vars"
if grep -qF "$AC_BEGIN" "$PROFILE" 2>/dev/null; then
  echo "  already present in $PROFILE (skipping; edit there to change)"
elif [[ $DRY -eq 1 ]]; then
  echo "  would: append auto-compact exports block to $PROFILE"
else
  {
    echo ""
    echo "$AC_BEGIN"
    grep -E '^export ' "$REPO/env/auto-compact.env"
    echo "$AC_END"
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
  if [[ $DRY -eq 1 ]]; then
    echo "  would: scaffold $SWITCH_DIR/.env from .env.example (chmod 600)"
  else
    cp "$SWITCH_DIR/.env.example" "$SWITCH_DIR/.env"
    chmod 600 "$SWITCH_DIR/.env"  # holds a real API token — keep it owner-only
    warn "fill API_KEYS in vendor/claude-switch/.env (scaffolded from .env.example)"
  fi
fi
if [[ -f "$SWITCH" ]]; then
  if grep -qF "$DA_BEGIN" "$PROFILE" 2>/dev/null; then
    echo "  already sourced in $PROFILE"
  elif [[ $DRY -eq 1 ]]; then
    echo "  would: append dual-auth source block to $PROFILE"
  else
    {
      echo ""
      echo "$DA_BEGIN"
      echo "# Claude Code: dual-auth (subscription vs Qwen API) — switch wrapper"
      echo "[ -f \"$SWITCH\" ] && . \"$SWITCH\""
      echo "$DA_END"
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
