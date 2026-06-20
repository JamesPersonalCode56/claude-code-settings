# claude-code-settings

[![CI](https://github.com/JamesPersonalCode56/claude-code-settings/actions/workflows/ci.yml/badge.svg)](https://github.com/JamesPersonalCode56/claude-code-settings/actions/workflows/ci.yml)

Version-controlled **Claude Code** configuration, captured from this machine so
it can be reviewed, diffed, and re-applied (or replicated to another box).

**Clone with submodules** (the dual-auth switch is vendored as a submodule):

```bash
git clone --recursive git@github.com:JamesPersonalCode56/claude-code-settings.git
# already cloned non-recursively? run: git submodule update --init --recursive
```

Apply it with:

```bash
bash setup.sh                # full bootstrap: install missing tools + config
bash setup.sh --config-only  # only copy config; skip all tool installs + PATH append
bash setup.sh --dry-run      # print the plan as "would: …"; make NO changes
bash setup.sh --uninstall    # remove this bundle's $PROFILE blocks (backs it up first)
bash setup.sh --help         # show usage and exit (also -h)
```

`--config-only` and `--dry-run` combine: `--config-only --dry-run` previews just
the config plan.

`setup.sh` is a **full bootstrap** for a fresh user/machine. It:

1. **Installs missing tools** (best-effort, skipped if already present):
   - `claude` — Claude Code CLI via the native installer
     (`curl -fsSL https://claude.ai/install.sh | bash`).
   - `omc` — `npm i -g oh-my-claude-sisyphus` (oh-my-claudecode).
   - `rtk` — the **Rust Token Killer** binary used by the hooks (private build,
     no public registry; pinned **v0.42.1**; **x86-64 Linux only** static-pie
     ELF). Bundled in **`bin/rtk`** and copied to `~/.local/bin`. `setup.sh`
     **verifies the bundled binary against `bin/rtk.sha256` before copying** and
     **skips install on mismatch** (it will not place an unverified binary).
     Override the source with `RTK_SRC=/path/to/rtk` (your own source isn't
     hash-checked against ours).
2. Copies all config (settings, CLAUDE.md/RTK.md, local skills, env vars).
3. Sources the Qwen/Anthropic dual-auth switch from the `vendor/claude-switch`
   submodule (scaffolding its `.env` from `.env.example` if missing).

It backs up any existing config file to `<name>.bak-<timestamp>` before
overwriting, and is safe to re-run.

### Still manual afterwards

- Open a new shell (or `source ~/.bashrc`) so PATH + env vars apply.
- `claude` once to **log in** (credentials are per-user, never in this repo).
- Launch `claude` once so it auto-installs the enabled plugins.
- The `rcp` / `browser-app` MCP servers are **prod-hosted and injected
  externally** (out of this repo's scope) — nothing to register here.
- Fill `API_KEYS` in `vendor/claude-switch/.env` to use the Qwen endpoint
  (scaffolded from `.env.example`; never committed).

## Requirements

- **x86-64 Linux only** for the bundled `rtk`: `bin/rtk` is a static x86-64 ELF
  binary, so it runs only on x86-64 Linux. The settings.json hooks invoke `rtk`,
  so on macOS / ARM / other arches the bundled binary will not run (config still
  applies — see below).
- **bash ≥ 4** — `setup.sh` uses bash 4+ features (`[[ … ]]`, arrays).
- **`git`** — to clone the repo and pull the `vendor/claude-switch` submodule.
- **`curl`** — used by the native Claude Code installer during full bootstrap.
- **`node` / `npm`** — only needed for the optional `omc` install
  (`npm i -g oh-my-claude-sisyphus`); skipped if `npm` is absent.
- **`gh`** — optional; not required by `setup.sh`.

macOS / non-x86-64 users can still apply the config (`bash setup.sh
--config-only`), but the bundled `rtk` binary won't execute on their platform —
supply your own `rtk` via `RTK_SRC=/path/to/rtk` or remove the rtk hooks.

## What's captured

| Path | What |
|---|---|
| `settings/settings.json` | Main Claude Code settings — permissions, hooks (rtk), status line (omc-hud), enabled plugins, marketplaces, `effortLevel`, theme, teammate mode, etc. |
| `settings/omc-config.json` | oh-my-claudecode config (default execution mode `ultrawork`, team ops). |
| `claude-md/CLAUDE.md` | Global instructions (oh-my-claudecode + graphify). |
| `claude-md/RTK.md` | Rust Token Killer usage notes. |
| `plugins/known_marketplaces.json` | Plugin marketplaces: `claude-plugins-official` (anthropics) + `omc` (Yeachan-Heo/oh-my-claudecode). |
| `plugins/installed_plugins.json` | Installed plugins + pinned versions: `oh-my-claudecode@omc` (4.13.6), `rust-analyzer-lsp@claude-plugins-official` (1.0.0). |
| `vendor/claude-switch` | Submodule: dual-auth switch (`claude-max` / `claude-qwen` / bare-`claude` prompt) — **direct upstreams, no proxy** (verbatim accuracy). |
| `skills/graphify` | Local skill: any input → knowledge graph. |
| `skills/omc-reference` | Local skill: OMC agent/tool/skill reference. |
| `env/auto-compact.env` | Auto-compact tuning env vars (window = 1,000,000; trigger = 40%). |
| `bin/rtk` | Bundled **Rust Token Killer** (`rtk`) binary — **private build, no public registry/URL**, pinned **v0.42.1**, **x86-64 Linux only** (static-pie ELF). Copied to `~/.local/bin` by `setup.sh`, which now **verifies it against `bin/rtk.sha256` before install** (mismatch → warn + skip). See `claude-md/RTK.md` for usage. |
| `bin/rtk.sha256` | Recorded SHA-256 of `bin/rtk` for provenance/integrity. `setup.sh` checks the bundled binary against it before copying; verify manually with `cd bin && sha256sum -c rtk.sha256`. |

> **De-bloat later (user-gated, not done here):** `bin/rtk` is a ~9.6 MB binary
> committed straight into git history. Two outward-facing options to slim the
> repo, both deferred because they rewrite history / publish artifacts and need
> an explicit decision: (1) `git lfs migrate` the binary, then force-push; or
> (2) publish `rtk` as a GitHub Release asset and have `setup.sh` download +
> verify it (against `bin/rtk.sha256`) instead of bundling it.

## Plugins

`settings.json` carries `enabledPlugins` + `extraKnownMarketplaces`, so Claude
Code re-installs the plugins from their marketplaces on next launch. The
`plugins/*.json` files document the exact desired state / pinned versions.

## Auto-compact env vars

`env/auto-compact.env` must be sourced as **real shell env vars** (not the
settings.json `env` block — that is silently ignored for autocompact). `setup.sh`
appends the exports to `~/.bashrc`. On a Windows host (e.g. the Qwen box) use
`setx` instead. See the comments in that file for what each var does and why a
custom Qwen endpoint must set the window manually.

## Troubleshooting

- **`rtk` missing, or sha256 mismatch → hooks error / setup skips it.** The
  settings.json hooks call `rtk`; if it isn't installed they error. `setup.sh`
  verifies the bundled `bin/rtk` against `bin/rtk.sha256` and **skips the install
  on mismatch** (it won't place an unverified binary). Fix: restore a trusted
  `bin/rtk`, or point setup at your own binary and re-run:
  `RTK_SRC=/path/to/rtk bash setup.sh`.
- **Submodule didn't clone (`vendor/claude-switch` empty).** Pull it explicitly:
  `git submodule update --init --recursive`. The submodule URL is HTTPS, so an
  anonymous clone works (no SSH key needed).
- **`claude-qwen` exits immediately complaining about `.env`.** The switch
  fails fast when `vendor/claude-switch/.env` is missing or still holds the
  placeholder. Fix: fill `API_KEYS` (and `BASE_URL`) in
  `vendor/claude-switch/.env` with your real Qwen token.
- **Undo everything this bundle added.** Run `bash setup.sh --uninstall` to
  remove the auto-compact + dual-auth blocks from your `$PROFILE` (it backs the
  profile up first). Installed config files and copied binaries are left in
  place; the command prints the exact restore/remove lines.

## NOT included (secrets / runtime — intentionally excluded)

These are **never** committed (also guarded by `.gitignore`):

- `~/.claude/.credentials.json` — OAuth tokens.
- `~/.claude.json` (full) — runtime cache + `oauthAccount` + `userID` (PII).
- Sessions, history, stats, caches, file-history.

If you ever copy a whole `~/.claude` in here, `.gitignore` blocks the secret/
runtime files — but double-check before committing.
