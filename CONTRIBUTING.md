# Contributing

This repo is version-controlled **Claude Code** configuration plus a `setup.sh`
bootstrap. Changes are small and surgical — extend what's there, don't rewrite
working parts. Keep this practical.

## Run the checks CI runs

CI (`.github/workflows/ci.yml`) has three jobs: **lint**, **smoke**, **bats**.
Reproduce them locally before opening a PR:

```bash
# lint
shellcheck --severity=warning setup.sh          # BLOCKING (must pass clean)
shfmt -d setup.sh vendor/claude-switch/claude-switch.sh   # advisory (shows diff)
for f in settings/*.json plugins/*.json; do     # JSON must be valid
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f"
done

# smoke: config-only apply into a throwaway HOME (no global side effects)
HOME="$(mktemp -d)" CLAUDE_CONFIG_DIR="$HOME/.claude" PROFILE="$HOME/.bashrc" \
  bash -c 'touch "$PROFILE"; bash setup.sh --config-only'

# bats: the test/ suite
bats test/
```

`shellcheck --severity=warning setup.sh` is the blocking gate — keep it clean.
`shfmt` and the vendor-script shellcheck are advisory but worth a glance.

## Add or adjust a config file

1. Drop the file under the right directory (`settings/`, `claude-md/`,
   `plugins/`, `skills/`, `env/`).
2. Wire it into `setup.sh` so it gets copied — follow the existing
   `backup_then_copy` calls (settings/CLAUDE.md) or the `skills/*/` loop pattern.
   Match the existing numbered `[n/7]` step style.
3. If it's JSON, it must pass the JSON validation loop above.
4. If your file should land in the smoke test's assertions, add a `test -f` /
   `grep -qF` check in the smoke job and/or a `bats` test under `test/`.

## Bump the `vendor/claude-switch` submodule

`vendor/claude-switch` is a git submodule pinned to a specific SHA in the parent.

```bash
cd vendor/claude-switch
# make + commit your change INSIDE the submodule (or pull a new upstream SHA)
git commit -am "…"            # or: git fetch && git checkout <sha>
cd ../..
git add vendor/claude-switch  # stages the new pinned SHA in the parent
git commit -m "vendor/claude-switch: bump to <reason>"
```

The parent records only the submodule's commit pointer — stage `vendor/claude-switch`
(the gitlink), never the submodule's working files from the parent.

## Update `bin/rtk` (and regenerate its checksum)

`bin/rtk` is provenance-guarded by `bin/rtk.sha256`. If you replace the binary,
**regenerate the checksum in the same commit** or `setup.sh` will refuse to
install it (sha256 mismatch → skip):

```bash
cd bin
cp /path/to/new/rtk rtk
sha256sum rtk > rtk.sha256     # records "<hash>  rtk"
sha256sum -c rtk.sha256        # confirm it verifies
cd ..
git add bin/rtk bin/rtk.sha256
```

## Commit convention

Use a short, scoped subject (e.g. `setup.sh: …`, `vendor/claude-switch: …`,
`ci: …`, `docs: …`), matching the existing history. End AI-assisted commits with
a trailer:

```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

## Never commit secrets or the rtk binary via `git add -A`

The working tree contains a **real secret** (`vendor/claude-switch/.env`) and a
large binary (`bin/rtk`) that must not be swept in accidentally.

- **Never run `git add -A` / `git add .`.** Stage files explicitly **by path**.
- `vendor/claude-switch/.env` holds a real API token — it is gitignored and
  `chmod 600`; keep it out of every commit.
- Only re-commit `bin/rtk` deliberately, alongside a regenerated
  `bin/rtk.sha256` (see above).
