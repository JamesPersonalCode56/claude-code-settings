<project>
Development doc for `claude-code-settings` — version-controlled Claude Code config + a `setup.sh` bootstrap that replicates it to a fresh user/machine. Mostly bash/shell + JSON.
This file = guidance for working ON the repo. NOT distributed. The user-level instructions that ship to `~/.claude/CLAUDE.md` live in `claude-md/CLAUDE.md` (see `<distribution>`) — different file, different audience.
Global behavioral rules (quality gates, project-local toolchains, surgical edits, delegation, agent↔agent English) come from the global `~/.claude/CLAUDE.md` and apply here too — not repeated below.
</project>

<distribution>
`setup.sh` copies repo files INTO `~/.claude` (or `$CLAUDE_CONFIG_DIR`). Source-of-truth mapping — edit the REPO file, never the installed copy:
| Repo path | → installed | Wired in setup.sh |
| `claude-md/CLAUDE.md` | `~/.claude/CLAUDE.md` (global user instructions) | `[2/7]` `backup_then_copy` :305 |
| `claude-md/RTK.md` | `~/.claude/RTK.md` | `[2/7]` :306 |
| `settings/settings.json`, `settings/omc-config.json` | `~/.claude/…` | `[1/7]` |
| `skills/*/` (graphify, omc-reference) | `~/.claude/skills/*/` | `[3/7]` loop |
| `env/auto-compact.env` | appended to `$PROFILE` (`~/.bashrc`) | `[4/7]` |
| `plugins/*.json` | documented desired state (Claude re-installs on launch) | `[5/7]` |
| `vendor/claude-switch/` | sourced into `$PROFILE` (dual-auth switch) | `[7/7]` |
`backup_then_copy` saves any existing target to `<name>.bak-<ts>` first; setup is idempotent + re-runnable.
</distribution>

<setup_sh_layout>
Flags: `--config-only` (skip tool installs + PATH), `--dry-run` (print `would: …`, no changes; combines with `--config-only`), `--uninstall` (remove this bundle's `$PROFILE` blocks, backup first), `--help`/`-h`.
Steps: `[0/7]` bootstrap tools (claude/omc/rtk) · `[1/7]` settings+OMC config · `[2/7]` CLAUDE.md/RTK.md · `[3/7]` skills · `[4/7]` auto-compact env · `[5/7]` plugins · `[6/7]` MCP (no-op, prod-injected) · `[7/7]` dual-auth.
Helpers: `do_or_echo` (dry-run gate), `have`/`warn`/`ok`, `backup_then_copy src dst`, `remove_marked_block`, `remove_legacy_dualauth`. `rtk` is `RTK_TAG`-pinned, fetched via `gh release download`, hash-checked vs `bin/rtk.sha256`, skipped on mismatch.
</setup_sh_layout>

<dev_tasks>
- Add/change a config file: drop under correct dir (`settings/` `claude-md/` `plugins/` `skills/` `env/`) → wire into `setup.sh` (`backup_then_copy` call or `skills/*/` loop), match the `[n/7]` step style → JSON must pass the validation loop → add a smoke `test -f`/`grep -qF` and/or `bats` assertion if it should be guarded.
- Edit `vendor/claude-switch/*` (dual-auth switch — now PLAIN vendored files, no longer a submodule): edit in place + `git add` the specific file(s) by explicit path. The real secret `.env` and runtime `.omc/` stay gitignored (root `.gitignore` + the dir's own `.gitignore`) — never stage them. The Qwen token is read at runtime via the shared `qwen-key-helper.sh` (used by BOTH the Linux switch `claude-qwen` and the Windows `settings.json` `apiKeyHelper`); change token-reading logic there, in one place.
- Update `rtk`: regenerate `bin/rtk.sha256` from the new binary + commit it → `gh release upload v1.0.0 <rtk> --clobber` (asset MUST be named `rtk`) → if new tag, bump `RTK_TAG` default in `setup.sh`. Binary is NOT committed (stripped from history; release-asset only).
</dev_tasks>

<ci_gates>
`.github/workflows/ci.yml` — 3 jobs. Repro locally before PR:
- lint: `shellcheck --severity=warning setup.sh setup.win.sh` (BLOCKING — keep clean) · `shfmt -d setup.sh vendor/claude-switch/claude-switch.sh` (advisory) · JSON validate `settings/*.json plugins/*.json` (BLOCKING).
- smoke: `HOME=$(mktemp -d) CLAUDE_CONFIG_DIR=$HOME/.claude PROFILE=$HOME/.bashrc bash -c 'touch "$PROFILE"; bash setup.sh --config-only'` — asserts settings.json + skills landed, CLAUDE.md carries sentinel `project_local_toolchains`, runs twice for idempotency, `$PROFILE` markers appear EXACTLY once.
- bats: `bats test/` (`setup_config_only.bats`, `switch_routing.bats`, `settings_drift.bats`, `setup_win.bats`). `setup_win.bats` smoke-tests the Windows installer: `bash -n setup.win.sh` + the `windows/build-settings.mjs` transform (Qwen creds baked into settings.json `env`, rtk hook / statusLine / OMC marketplace stripped); node-dependent cases `skip` when node is absent.
COUPLING: the `project_local_toolchains` anchor lives in `claude-md/CLAUDE.md` and is grepped by TWO independent checks — `.github/workflows/ci.yml` (smoke job) AND `test/setup_config_only.bats:31`. Rename/remove it → update ALL THREE files in the same commit. (Real regression: smoke was updated but the bats grep was missed, so smoke passed green while the bats job failed on the same anchor.)
</ci_gates>

<change_discipline>
Lessons from a real anchor-rename regression (smoke passed, bats failed on the SAME anchor):
- Changing a referenced value (anchor, JSON key, filename, flag, env var) → `grep -rn` the WHOLE repo for EVERY dependent BEFORE claiming done. Enumerate call sites with grep, never from memory — memory stops at the first site you recall; grep lists all of them.
- Verify with the ACTUAL check that guards it, not a sibling assumed equivalent. No local `bats`? `git clone --depth 1 https://github.com/bats-core/bats-core` and run `bats test/` — never infer the bats job is green from the smoke job alone.
- A literal duplicated across N files is a regression trap: update all N or none. Prefer one source + reference; if duplication is unavoidable, list every site in the COUPLING note above.
- Config sync drift: `settings/settings.json` (repo) can fall behind `~/.claude/settings.json` (live) when something edits the live file directly. Before `setup.sh --config-only` (which copies repo→live), run `bin/settings-drift.sh` (exit 1 = drift, lists live-only keys repo would DROP) — re-install silently reverts live to repo, so reconcile repo forward first. CI can't see live, so this guard is local-only.
</change_discipline>

<guardrails>
- NEVER `git add -A` / `git add .`. Stage by explicit path. Working tree holds a REAL secret `vendor/claude-switch/.env` (gitignored, chmod 600) — keep it out of every commit.
- NEVER re-commit the `rtk` binary — only `bin/rtk.sha256`.
- Commits: short scoped subject (`setup.sh: …`, `vendor/claude-switch: …`, `ci: …`, `docs: …`). End AI-assisted commits with trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Repo default branch is `main` — branch before opening a PR.
</guardrails>
