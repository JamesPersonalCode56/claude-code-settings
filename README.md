# claude-code-settings

Version-controlled **Claude Code** configuration, captured from this machine so
it can be reviewed, diffed, and re-applied (or replicated to another box).

Apply it with:

```bash
bash setup.sh
```

It backs up any existing file to `<name>.bak-<timestamp>` before overwriting.

## What's captured

| Path | What |
|---|---|
| `settings/settings.json` | Main Claude Code settings — permissions, hooks (rtk), status line (omc-hud), enabled plugins, marketplaces, `effortLevel`, theme, teammate mode, etc. |
| `settings/omc-config.json` | oh-my-claudecode config (default execution mode `ultrawork`, team ops). |
| `claude-md/CLAUDE.md` | Global instructions (oh-my-claudecode + graphify). |
| `claude-md/RTK.md` | Rust Token Killer usage notes. |
| `plugins/known_marketplaces.json` | Plugin marketplaces: `claude-plugins-official` (anthropics) + `omc` (Yeachan-Heo/oh-my-claudecode). |
| `plugins/installed_plugins.json` | Installed plugins + pinned versions: `oh-my-claudecode@omc` (4.13.6), `rust-analyzer-lsp@claude-plugins-official` (1.0.0). |
| `mcp/mcpServers.json` | MCP servers — `rcp-bridge` (stdio, local python). **Machine-specific path**, edit per host. |
| `skills/graphify` | Local skill: any input → knowledge graph. |
| `skills/omc-reference` | Local skill: OMC agent/tool/skill reference. |
| `env/auto-compact.env` | Auto-compact tuning env vars (window = 1,000,000; trigger = 40%). |

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
- `~/.claude.json` (full) — runtime cache + `oauthAccount` + `userID` (PII). Only
  the sanitized `mcpServers` block is extracted into `mcp/mcpServers.json`.
- Sessions, history, stats, caches, file-history.

If you ever copy a whole `~/.claude` in here, `.gitignore` blocks the secret/
runtime files — but double-check before committing.
