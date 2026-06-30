#!/usr/bin/env bash
# Reap orphaned native-team teammate tmux panes (Claude Code SubagentStop hook).
#
# Root cause (Claude Code EXPERIMENTAL agent teams): when a teammate is stopped or
# finishes, the harness flips its member record to isActive=false in
# ~/.claude/teams/<session>/config.json but LEAVES its tmux pane (an idle `claude`
# process) running forever. This closes those orphaned panes. Idempotent.
#
# Invoked as a SubagentStop hook: a JSON payload arrives on STDIN (fields include
# session_id, cwd, transcript_path). We read it best-effort to PREFER the team
# config matching session_id; if stdin is empty or the id can't be matched we fall
# back to the most-recently-modified team config. A hook must NEVER break the
# session, so every failure path degrades gracefully and the script ALWAYS exits 0.
#
# SAFETY (critical — tmux RECYCLES pane ids, so a STALE config's "%45" may now be
# an unrelated live pane):
#   - Only consider config files modified within REAP_MAX_AGE_SEC (default 2 days).
#     Older configs are skipped entirely.
#   - Only act on members with backendType=="tmux" AND isActive==false AND a
#     "%NN" pane id whose pane is still alive (pane_dead==0).
#   - Never the in-process "leader" (backendType!="tmux", paneId=="leader"), never
#     an active teammate.
#   - Before killing, confirm the pane still looks like a Claude teammate (its
#     pane_current_command/pane_title mentions claude or a known agent marker);
#     skip it otherwise, defending against a recycled id now owned by some other
#     program. The guard is lenient so real teammates are not missed.
#
# CAVEAT: this rides on Claude Code's UNDOCUMENTED experimental-team schema
# (~/.claude/teams/<session>/config.json with members[].{name,tmuxPaneId,
# backendType,isActive}). A future rename of those fields would require updating
# this script.
#
# Usage: reap-teammate-panes.sh [path-to-config.json]   (default: resolve from the
#        SubagentStop stdin payload, else the newest recent team config)
#
# Env:
#   REAP_MAX_AGE_SEC  max config age in seconds to consider (default 172800 = 2d)
set -uo pipefail

REAP_MAX_AGE_SEC="${REAP_MAX_AGE_SEC:-172800}"
teams_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/teams"

log() { echo "reap: $*" >&2; }

# have CMD : is an executable on PATH?
have() { command -v "$1" >/dev/null 2>&1; }

# Read the SubagentStop JSON payload from stdin (best-effort, never blocks the
# session) and extract session_id. Empty string if stdin is empty or unparseable.
read_session_id() {
  local payload sid=""
  payload="$(cat 2>/dev/null || true)"
  [[ -n "$payload" ]] || return 0
  if have jq; then
    sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
  elif have python3; then
    sid="$(printf '%s' "$payload" | python3 -c \
      'import json,sys
try:
    print(json.load(sys.stdin).get("session_id","") or "")
except Exception:
    print("")' 2>/dev/null || true)"
  fi
  printf '%s' "$sid"
}

# newest_recent_config : path of the most-recently-modified team config.json that
# is younger than REAP_MAX_AGE_SEC. Empty if none qualify.
newest_recent_config() {
  local now cfg mtime newest="" newest_mtime=0
  now="$(date +%s)"
  for cfg in "$teams_dir"/*/config.json; do
    [[ -f "$cfg" ]] || continue
    mtime="$(stat -c %Y "$cfg" 2>/dev/null || echo 0)"
    ((now - mtime <= REAP_MAX_AGE_SEC)) || continue
    if ((mtime > newest_mtime)); then
      newest_mtime="$mtime"
      newest="$cfg"
    fi
  done
  printf '%s' "$newest"
}

# resolve_config SESSION_ID : pick the team config to act on. Prefer a config whose
# directory name matches SESSION_ID (and which is recent enough), else the newest
# recent config. Empty if nothing qualifies.
resolve_config() {
  local sid="$1" now cfg mtime
  now="$(date +%s)"
  if [[ -n "$sid" ]]; then
    for cfg in "$teams_dir"/*"$sid"*/config.json "$teams_dir/$sid/config.json"; do
      [[ -f "$cfg" ]] || continue
      mtime="$(stat -c %Y "$cfg" 2>/dev/null || echo 0)"
      ((now - mtime <= REAP_MAX_AGE_SEC)) || continue
      printf '%s' "$cfg"
      return 0
    done
  fi
  newest_recent_config
}

# pane_is_teammate PANE : 0 if the pane's current command/title looks like a Claude
# teammate (lenient guard against tmux recycling a pane id onto another program).
pane_is_teammate() {
  local pane="$1" info
  info="$(tmux display-message -p -t "$pane" '#{pane_current_command}|#{pane_title}' 2>/dev/null || true)"
  [[ -n "$info" ]] || return 1
  local lc="${info,,}"
  case "$lc" in
  *claude* | *general-purpose* | *node*) return 0 ;; # "oh-my-claudecode" already contains "claude"
  *) return 1 ;;
  esac
}

# emit_members CONFIG : print "name<TAB>paneId<TAB>backendType<TAB>isActive" rows.
emit_members() {
  local cfg="$1"
  if have jq; then
    jq -r '.members[]? | [(.name//""),(.tmuxPaneId//""),(.backendType//""),(.isActive|tostring)] | @tsv' \
      "$cfg" 2>/dev/null || true
  elif have python3; then
    python3 -c '
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for m in cfg.get("members", []):
    print("\t".join([str(m.get("name", "")), str(m.get("tmuxPaneId", "")),
                     str(m.get("backendType", "")), str(m.get("isActive"))]))
' "$cfg" 2>/dev/null || true
  fi
}

main() {
  have tmux || {
    log "tmux not found — nothing to reap"
    exit 0
  }
  [[ -d "$teams_dir" ]] || {
    log "no teams dir ($teams_dir) — nothing to reap"
    exit 0
  }

  local sid cfg
  sid="$(read_session_id)"

  cfg="${1:-}"
  [[ -n "$cfg" ]] || cfg="$(resolve_config "$sid")"
  [[ -n "$cfg" && -f "$cfg" ]] || {
    log "no recent team config found — nothing to reap"
    exit 0
  }

  local killed=0 name pane backend active
  while IFS=$'\t' read -r name pane backend active; do
    [[ "$backend" == "tmux" ]] || continue
    [[ "$active" == "False" || "$active" == "false" ]] || continue
    [[ "$pane" =~ ^%[0-9]+$ ]] || continue
    local dead
    dead="$(tmux display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null || echo missing)"
    [[ "$dead" == "0" ]] || continue
    pane_is_teammate "$pane" || {
      log "skip $pane ($name): does not look like a teammate (recycled id?)"
      continue
    }
    if tmux kill-pane -t "$pane" 2>/dev/null; then
      log "closed pane $pane ($name)"
      killed=$((killed + 1))
    fi
  done < <(emit_members "$cfg")

  log "closed $killed orphaned pane(s) from $(basename "$(dirname "$cfg")")"
  exit 0
}

main "$@"
