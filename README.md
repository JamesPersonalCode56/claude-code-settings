# claude-code-settings

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
bash setup.sh --config-only  # only copy config (no installs)
```

`setup.sh` is a **full bootstrap** for a fresh user/machine. It:

1. **Installs missing tools** (best-effort, skipped if already present):
   - `claude` — Claude Code CLI via the native installer
     (`curl -fsSL https://claude.ai/install.sh | bash`).
   - `omc` — `npm i -g oh-my-claude-sisyphus` (oh-my-claudecode).
   - `rtk` — the Rust Token Killer binary used by the hooks. It is a static
     x86-64 ELF, so the binary is **bundled in `bin/rtk`** and just copied to
     `~/.local/bin` (override with `RTK_SRC=/path/to/rtk`).
2. Copies all config (settings, CLAUDE.md/RTK.md, local skills, env vars).
3. Installs `bin/claude-hr` (Headroom-wrapped `claude` launcher) to `~/.local/bin`.
4. Sources the Qwen/Anthropic dual-auth switch from the `vendor/claude-switch`
   submodule (scaffolding its `.env` from `.env.example` if missing).

It backs up any existing config file to `<name>.bak-<timestamp>` before
overwriting, and is safe to re-run.

### Still manual afterwards

- Open a new shell (or `source ~/.bashrc`) so PATH + env vars apply.
- `claude` once to **log in** (credentials are per-user, never in this repo).
- Launch `claude` once so it auto-installs the enabled plugins.
- The `rcp` / `browser-app` / `headroom` MCP servers are **prod-hosted and
  injected externally** (out of this repo's scope) — nothing to register here.
- Fill `API_KEYS` in `vendor/claude-switch/.env` to use the Qwen endpoint
  (scaffolded from `.env.example`; never committed).

## What's captured

| Path | What |
|---|---|
| `settings/settings.json` | Main Claude Code settings — permissions, hooks (rtk), status line (omc-hud), enabled plugins, marketplaces, `effortLevel`, theme, teammate mode, etc. |
| `settings/omc-config.json` | oh-my-claudecode config (default execution mode `ultrawork`, team ops). |
| `claude-md/CLAUDE.md` | Global instructions (oh-my-claudecode + graphify). |
| `claude-md/RTK.md` | Rust Token Killer usage notes. |
| `plugins/known_marketplaces.json` | Plugin marketplaces: `claude-plugins-official` (anthropics) + `omc` (Yeachan-Heo/oh-my-claudecode). |
| `plugins/installed_plugins.json` | Installed plugins + pinned versions: `oh-my-claudecode@omc` (4.13.6), `rust-analyzer-lsp@claude-plugins-official` (1.0.0). |
| `vendor/claude-switch` | Submodule: dual-auth switch (`claude-max` / `claude-qwen` / bare-`claude` prompt) — **direct upstreams, no proxy** (verbatim accuracy). Headroom is opt-in via `bin/claude-hr`. |
| `bin/claude-hr` | Headroom-wrapped `claude` launcher (sets `ANTHROPIC_BASE_URL` + `HEADROOM_USER_ID`); installed to `~/.local/bin`. |
| `skills/graphify` | Local skill: any input → knowledge graph. |
| `skills/omc-reference` | Local skill: OMC agent/tool/skill reference. |
| `env/auto-compact.env` | Auto-compact tuning env vars (window = 1,000,000; trigger = 40%). |
| `bin/rtk` | Bundled Rust Token Killer binary (static x86-64), copied to `~/.local/bin` by `setup.sh` so the hooks work on a fresh box. |

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

## NOT included (secrets / runtime — intentionally excluded)

These are **never** committed (also guarded by `.gitignore`):

- `~/.claude/.credentials.json` — OAuth tokens.
- `~/.claude.json` (full) — runtime cache + `oauthAccount` + `userID` (PII).
- Sessions, history, stats, caches, file-history.

If you ever copy a whole `~/.claude` in here, `.gitignore` blocks the secret/
runtime files — but double-check before committing.
