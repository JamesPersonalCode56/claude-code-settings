#!/usr/bin/env bats
# Hermetic tests for hooks/reap-teammate-panes.sh.
#
# No real tmux and no real teammates are involved: a STUB `tmux` is put on PATH and
# fixture team configs are written under an isolated $HOME/.claude/teams/. The stub
# models pane liveness from files under $STUB_PANES_DIR ("0"=alive, "1"=dead, file
# absent=unknown -> nonzero exit, like a gone pane), reports every pane as a
# "claude" teammate, records each `kill-pane -t %NN` to $STUB_KILL_LOG, and DELETES
# the pane file on kill so a second run sees it gone (true idempotency).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/hooks/reap-teammate-panes.sh"

  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export CLAUDE_CONFIG_DIR="$TEST_HOME/.claude"
  TEAMS="$CLAUDE_CONFIG_DIR/teams"
  mkdir -p "$TEAMS"

  # Stub tmux + its state live under the test tmpdir.
  STUB_BIN="$TEST_HOME/bin"
  export STUB_PANES_DIR="$TEST_HOME/panes"
  export STUB_KILL_LOG="$TEST_HOME/killed.log"
  mkdir -p "$STUB_BIN" "$STUB_PANES_DIR"
  : >"$STUB_KILL_LOG"

  cat >"$STUB_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
# Minimal tmux stub: display-message (pane_dead / pane_current_command|pane_title)
# and kill-pane. Pane liveness comes from files in $STUB_PANES_DIR.
sub="${1:-}"
shift || true
case "$sub" in
  display-message)
    pane="" fmt=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t)
          pane="$2"
          shift 2
          ;;
        -p)
          shift
          ;;
        *)
          fmt="$1"
          shift
          ;;
      esac
    done
    [[ -f "$STUB_PANES_DIR/$pane" ]] || exit 1 # unknown/gone pane
    if [[ "$fmt" == *pane_dead* ]]; then
      cat "$STUB_PANES_DIR/$pane" # "0" alive, "1" dead
    else
      echo "claude|teammate $pane" # looks like a Claude teammate
    fi
    ;;
  kill-pane)
    pane=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t)
          pane="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    [[ -f "$STUB_PANES_DIR/$pane" ]] || exit 1
    echo "$pane" >>"$STUB_KILL_LOG"
    rm -f "$STUB_PANES_DIR/$pane" # pane is gone after kill (idempotency)
    ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"

  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# alive PANE  : mark a stub pane as alive (pane_dead=0)
alive() { echo "0" >"$STUB_PANES_DIR/$1"; }
# dead PANE   : mark a stub pane as dead (pane_dead=1)
dead() { echo "1" >"$STUB_PANES_DIR/$1"; }
# missing PANE: no file -> stub display-message exits nonzero (gone pane)

# write_config DIR : write a teams/<DIR>/config.json with a representative member
# set. Panes referenced: %10 (orphan, killable), %11 (active), %12 (dead),
# %13 (missing), leader (in-process).
write_config() {
  local dir="$TEAMS/$1"
  mkdir -p "$dir"
  cat >"$dir/config.json" <<'JSON'
{
  "members": [
    { "name": "lead",     "agentId": "a0", "tmuxPaneId": "leader", "backendType": "in-process", "isActive": true },
    { "name": "orphan",   "agentId": "a1", "tmuxPaneId": "%10",    "backendType": "tmux",       "isActive": false },
    { "name": "busy",     "agentId": "a2", "tmuxPaneId": "%11",    "backendType": "tmux",       "isActive": true },
    { "name": "deadpane", "agentId": "a3", "tmuxPaneId": "%12",    "backendType": "tmux",       "isActive": false },
    { "name": "gonepane", "agentId": "a4", "tmuxPaneId": "%13",    "backendType": "tmux",       "isActive": false }
  ]
}
JSON
}

# killed_count : number of recorded kill-pane calls
killed_count() { wc -l <"$STUB_KILL_LOG" | tr -d ' '; }
# was_killed PANE : grep the kill log for a pane id
was_killed() { grep -qx "$1" "$STUB_KILL_LOG"; }

@test "kills a tmux + isActive:false + alive orphan pane" {
  write_config session-x
  alive %10
  alive %11
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  was_killed "%10"
}

@test "does NOT kill an isActive:true member" {
  write_config session-x
  alive %10
  alive %11
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  ! was_killed "%11"
}

@test "does NOT kill the in-process leader member" {
  write_config session-x
  alive %10
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  ! was_killed "leader"
}

@test "skips a member whose pane is dead or missing (no error, exit 0)" {
  write_config session-x
  dead %12 # pane_dead=1
  # %13 has no stub file -> reported gone
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  ! was_killed "%12"
  ! was_killed "%13"
}

@test "skips a config OLDER than REAP_MAX_AGE_SEC entirely" {
  write_config session-old
  alive %10
  touch -d "3 days ago" "$TEAMS/session-old/config.json"
  run bash "$SCRIPT" </dev/null # default window is 2 days
  [ "$status" -eq 0 ]
  [ "$(killed_count)" -eq 0 ]
  # Within a wider window the same orphan IS reaped (proves age was the only gate).
  run env REAP_MAX_AGE_SEC=864000 bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  was_killed "%10"
}

@test "is idempotent: a second run kills nothing and exits 0" {
  write_config session-x
  alive %10
  alive %11
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  [ "$(killed_count)" -eq 1 ]
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  [ "$(killed_count)" -eq 1 ] # no new kills (pane already gone)
}

@test "empty stdin / no session_id falls back to the newest recent config" {
  write_config session-x
  alive %10
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  was_killed "%10"
}

# write_orphan_config DIR PANE : a minimal config with a single killable tmux
# orphan on PANE. Lets two configs reference DISTINCT panes.
write_orphan_config() {
  local dir="$TEAMS/$1" pane="$2"
  mkdir -p "$dir"
  cat >"$dir/config.json" <<JSON
{ "members": [
  { "name": "orphan", "agentId": "x", "tmuxPaneId": "$pane", "backendType": "tmux", "isActive": false }
] }
JSON
}

@test "prefers the config matching the SubagentStop session_id over the newest" {
  write_orphan_config session-aaa %20
  alive %20
  write_orphan_config session-bbb %21
  alive %21
  touch "$TEAMS/session-bbb/config.json" # session-bbb is the newest on disk
  run bash "$SCRIPT" <<<'{"session_id":"session-aaa"}'
  [ "$status" -eq 0 ]
  was_killed "%20"   # the session_id match was honored
  ! was_killed "%21" # NOT the newest fallback
}

@test "no teams dir / no tmux: exits 0 quietly" {
  rm -rf "$TEAMS"
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
}
