#!/usr/bin/env bash
# Report drift between the repo's settings/settings.json and the installed live
# copy (~/.claude/settings.json). Run this BEFORE `setup.sh` — setup copies repo
# -> live, so if the live file has drifted ahead (e.g. something edited it
# directly), re-installing would silently revert those keys. Reconcile the repo
# forward first.
#
# Usage:   bin/settings-drift.sh [repo_json] [live_json]
# Exit:    0 = in sync   1 = drift detected   2 = a file is missing
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="${1:-$repo_dir/settings/settings.json}"
live="${2:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"

[[ -f "$repo" ]] || { echo "repo settings missing: $repo" >&2; exit 2; }
[[ -f "$live" ]] || { echo "live settings missing: $live (nothing installed yet?)" >&2; exit 2; }

python3 - "$repo" "$live" <<'PY'
import json, sys

def flat(d, p=''):
    out = {}
    for k, v in d.items():
        key = f"{p}.{k}" if p else k
        if isinstance(v, dict):
            out.update(flat(v, key))
        else:
            out[key] = v
    return out

repo = flat(json.load(open(sys.argv[1])))
live = flat(json.load(open(sys.argv[2])))

only_live = [k for k in live if k not in repo]
only_repo = [k for k in repo if k not in live]
changed   = [k for k in repo if k in live and repo[k] != live[k]]

if not (only_live or only_repo or changed):
    print("settings.json: repo and live are in sync")
    sys.exit(0)

print("settings.json DRIFT detected (repo vs live):")
for k in only_live:
    print(f"  + live-only  (repo would DROP this on next setup): {k} = {live[k]!r}")
for k in only_repo:
    print(f"  - repo-only  (would be ADDED to live on next setup): {k}")
for k in changed:
    print(f"  ~ value differs: {k}: repo={repo[k]!r} live={live[k]!r}")
sys.exit(1)
PY
