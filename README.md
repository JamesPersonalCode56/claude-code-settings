# claude-code-settings

[![CI](https://github.com/JamesPersonalCode56/claude-code-settings/actions/workflows/ci.yml/badge.svg)](https://github.com/JamesPersonalCode56/claude-code-settings/actions/workflows/ci.yml)

Version-controlled **Claude Code** configuration, captured from this machine so
it can be reviewed, diffed, and re-applied (or replicated to another box).

**Clone:**

```bash
git clone git@github.com:JamesPersonalCode56/claude-code-settings.git
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
     ELF). **Not stored in git** — it is **fetched from the private GitHub
     Release `v1.0.0` (asset `rtk`) via `gh release download`** and copied to
     `~/.local/bin`. Requires **`gh` installed + `gh auth login`** (repo is
     private). `setup.sh` **verifies the downloaded binary against
     `bin/rtk.sha256` before copying** and **skips install on mismatch** (it
     will not place an unverified binary). Override with `RTK_SRC=/path/to/rtk`
     (a local binary, still hash-checked) to skip the gh download.
2. Copies all config (settings, CLAUDE.md/RTK.md, local skills, env vars).
3. Sources the dual-auth switch (subscription / Qwen / DeepSeek) vendored in
   `vendor/claude-switch/`, scaffolding `env/models-qwen.env` +
   `env/models-deepseek.env` from their `.example` siblings if missing.

It backs up any existing config file to `<name>.bak-<timestamp>` before
overwriting, and is safe to re-run.

### Still manual afterwards

- Open a new shell (or `source ~/.bashrc`) so PATH + env vars apply.
- `claude` once to **log in** (credentials are per-user, never in this repo).
- Launch `claude` once so it auto-installs the enabled plugins.
- The `rcp` / `browser-app` MCP servers are **prod-hosted and injected
  externally** (out of this repo's scope) — nothing to register here.
- Fill `API_KEYS` in `env/models-qwen.env` (Qwen endpoint) and/or
  `env/models-deepseek.env` (DeepSeek native API) — each is scaffolded from its
  `.example` sibling; never committed.

## Requirements

- **x86-64 Linux only** for `rtk`: the `rtk` binary is a static x86-64 ELF, so it
  runs only on x86-64 Linux. The settings.json hooks invoke `rtk`, so on macOS /
  ARM / other arches it will not run (config still applies — see below).
- **`gh` + `gh auth login` for `rtk`** — the repo is private, so `setup.sh`
  uses `gh release download` to fetch the `rtk` binary. Install `gh` and run
  `gh auth login` before bootstrapping, or supply a local binary with
  `RTK_SRC=/path/to/rtk` to skip the download entirely.
- **bash ≥ 4** — `setup.sh` uses bash 4+ features (`[[ … ]]`, arrays).
- **`git`** — to clone the repo.
- **`curl`** — used by the native Claude Code installer during full bootstrap.
- **`node` / `npm`** — only needed for the optional `omc` install
  (`npm i -g oh-my-claude-sisyphus`); skipped if `npm` is absent.

macOS / non-x86-64 users can still apply the config (`bash setup.sh
--config-only`), but the `rtk` binary won't execute on their platform —
supply your own `rtk` via `RTK_SRC=/path/to/rtk` or remove the rtk hooks.

## What's captured

| Path | What |
|---|---|
| `settings/settings.json` | Main Claude Code settings — permissions, hooks (rtk), status line (omc-hud), enabled plugins, marketplaces, `effortLevel`, theme, teammate mode, etc. |
| `settings/omc-config.json` | oh-my-claudecode config (default execution mode `ultrawork`, team ops). |
| `claude-md/CLAUDE.md` | Global instructions (oh-my-claudecode + tool inventory + graphify). |
| `claude-md/RTK.md` | Rust Token Killer usage notes. |
| `hooks/*.sh` | Hook scripts installed to `~/.claude/hooks/` (SubagentStop pane-reaper). |
| `plugins/known_marketplaces.json` | Plugin marketplaces: `claude-plugins-official` (anthropics) + `omc` (Yeachan-Heo/oh-my-claudecode). |
| `plugins/installed_plugins.json` | Installed plugins + pinned versions: `oh-my-claudecode@omc` (4.14.7), `rust-analyzer-lsp@claude-plugins-official` (1.0.0), `frontend-design@claude-plugins-official`. |
| `vendor/claude-switch` | Dual-auth switch, vendored as plain files (`claude-max` / `claude-qwen` / `claude-deepseek` / bare-`claude` 1/2/3 prompt) — **direct upstreams, no proxy** (verbatim accuracy). Per-provider connection + token + lineup live in `env/models-qwen.env` / `env/models-deepseek.env`; the token is read at runtime via the shared `qwen-key-helper.sh` (Linux switch + Windows `apiKeyHelper`), never stored in `settings.json`. |
| `env/models-qwen.env` / `env/models-deepseek.env` | Per-provider env (base url + real token + model lineup, self-contained) for the dual-auth switch — gitignored; only the `.example` siblings are tracked. |
| `skills/graphify` | Local skill: any input → knowledge graph. |
| `skills/omc-reference` | Local skill: OMC agent/tool/skill reference. |
| `env/auto-compact.env` | Auto-compact tuning env vars (window = 1,000,000; trigger = 40%). |
| `bin/rtk.sha256` | Canonical SHA-256 of the **Rust Token Killer** (`rtk`) binary — **private build, no public registry**, pinned **v0.42.1**, **x86-64 Linux only** (static-pie ELF). The binary itself is **not in git**; it is published as the `rtk` asset on the GitHub Release `v1.0.0` and **downloaded + verified against this hash** by `setup.sh` before install (mismatch → warn + skip). See `claude-md/RTK.md` for usage. |

## Plugins

`settings.json` carries `enabledPlugins` + `extraKnownMarketplaces`, so Claude
Code re-installs the plugins from their marketplaces on next launch. The
`plugins/*.json` files document the exact desired state / pinned versions.

## Internal plugins (`minh-internal`)

This repo doubles as a Claude Code **plugin** and hosts the internal **marketplace**:

- `.claude-plugin/marketplace.json` — marketplace `minh-internal`, registered
  from the local checkout as a `directory` source (manifest edits apply without
  a push). Plugins:
  - `ccs` — this repo via its **git URL** (tracked files only; a path source
    would copy the gitignored env secrets into the plugin cache — never do
    that): ships `skills/` + the SubagentStop pane-reaper (`hooks/hooks.json`).
  - `rcp-engine` — `git-subdir` of `nmt-rcp` `plugin/` @ `main`, versioned with
    the rcp release tags.
- **Auto-update:** `bin/plugin-autoupdate.sh` (systemd user timer
  `ccs-plugin-cd`, every 10 min; units in `systemd/`, installed to
  `~/.config/systemd/user`) fetches both repos and, on a new nmt-rcp `v*` tag
  or a new `origin/main` commit, runs `claude plugin marketplace update
  minh-internal` + `claude plugin update <plugin>`. Manual refresh:
  `bin/plugin-autoupdate.sh --force` (or `/plugin` in a session). Updates apply
  to new sessions.
- **Version rule:** bump `.claude-plugin/plugin.json` `version` when shipping a
  plugin-visible change (`skills/`, `hooks/`) — content refresh keys off it.

## Auto-compact env vars

`env/auto-compact.env` must be sourced as **real shell env vars** (not the
settings.json `env` block — that is silently ignored for autocompact). `setup.sh`
appends the exports to `~/.bashrc`. On a Windows host (e.g. the Qwen box) use
`setx` instead. See the comments in that file for what each var does and why a
custom Qwen endpoint must set the window manually.

## Troubleshooting

- **`rtk` not installed / download failed / sha256 mismatch → hooks error /
  setup skips it.** The settings.json hooks call `rtk`; if it isn't installed
  they error. `setup.sh` fetches `rtk` via `gh release download v1.0.0` (repo is
  private — requires `gh auth login`), verifies against `bin/rtk.sha256`, and
  **skips install on mismatch or download failure** (it won't place an unverified
  binary). Fix:
  - Not authenticated: `gh auth login`, then re-run `bash setup.sh`.
  - No `gh`: install it, or supply a local binary: `RTK_SRC=/path/to/rtk bash setup.sh`.
  - Wrong asset: check `gh release view v1.0.0 --repo JamesPersonalCode56/claude-code-settings`.
- **`claude-qwen` / `claude-deepseek` exits immediately complaining about its env
  file.** The switch fails fast when `env/models-qwen.env` (Qwen) or
  `env/models-deepseek.env` (DeepSeek) is missing or still holds the placeholder.
  Fix: fill `API_KEYS` (and `BASE_URL`) in the matching `env/models-*.env` with
  your real provider token. (`claude` bare prompts 1/2/3 → sub / qwen / deepseek.)
- **Windows fleet: Qwen worker 401s on a fresh box.** The generated
  `settings.json` uses `apiKeyHelper` (an absolute Git-Bash path +
  `qwen-key-helper.sh`) instead of a baked token. `build-settings.mjs` resolves an
  absolute `bash.exe` (Claude Code runs `apiKeyHelper` via `cmd`, where Git Bash is
  usually not on PATH) and the helper reads `env/models-qwen.env` at runtime.
  `settings.json` is no longer self-contained: provisioning must ship
  `qwen-key-helper.sh` + `env/models-qwen.env`, not just `settings.json`. Missing
  either → empty token → 401.
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
