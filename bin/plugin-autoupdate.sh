#!/usr/bin/env bash
# plugin-autoupdate.sh — CD for the minh-internal Claude Code plugins.
#
# Watches the canonical sources and refreshes the installed plugins when they
# advance:
#   - nmt-tool-remote-control-pc: new `v*` release tag or new origin/main commit -> rcp-engine
#   - claude-code-settings: new origin/main commit             -> ccs
#
# Fired by the `ccs-plugin-cd` systemd user timer (see systemd/); run manually
# with `--force` to update unconditionally (the "manual request" path).
# Updates apply to NEW Claude Code sessions; running sessions keep the old
# version until restart.
#
# NOTE: plugin content refresh keys off .claude-plugin/plugin.json `version` —
# bump it when shipping plugin-visible changes (skills/, hooks/), or the cache
# may keep serving the old copy.
set -euo pipefail

CCS=/mnt/2TB/minh-archive/claude-code-settings
RCP=/mnt/2TB/minh-archive/nmt-tool-remote-control-pc
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/minh-plugin-cd"
STATE="$STATE_DIR/last-applied"
LOG="$STATE_DIR/plugin-cd.log"
mkdir -p "$STATE_DIR"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG" >&2; }

git -C "$RCP" fetch --quiet --tags origin 2>/dev/null || log "WARN: nmt-tool-remote-control-pc fetch failed (offline?)"
git -C "$CCS" fetch --quiet origin 2>/dev/null || log "WARN: claude-code-settings fetch failed (offline?)"

rcp_tag=$(git -C "$RCP" tag --list 'v*' --sort=-v:refname | head -1)
rcp_main=$(git -C "$RCP" rev-parse origin/main)
ccs_main=$(git -C "$CCS" rev-parse origin/main)
sig="rcp=${rcp_tag}@${rcp_main} ccs=${ccs_main}"

if [[ "${1:-}" != "--force" && -f "$STATE" && "$(cat "$STATE")" == "$sig" ]]; then
  exit 0 # nothing new — quiet no-op
fi

log "updating minh-internal plugins ($sig)"
claude plugin marketplace update minh-internal >>"$LOG" 2>&1 || { log "ERROR: marketplace update failed"; exit 1; }
claude plugin update ccs@minh-internal >>"$LOG" 2>&1 || log "WARN: ccs update failed"
claude plugin update rcp-engine@minh-internal >>"$LOG" 2>&1 || log "WARN: rcp-engine update failed"
printf '%s' "$sig" >"$STATE"
log "done — new Claude Code sessions pick up the update"
