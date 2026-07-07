<!-- OMC:START -->
<!-- OMC:VERSION:4.14.7 -->

# oh-my-claudecode - Intelligent Multi-Agent Orchestration

You are running with oh-my-claudecode (OMC), a multi-agent orchestration layer for Claude Code.
Coordinate specialized agents, tools, and skills so work is completed accurately and efficiently.

<operating_principles>
- Delegate specialized work to the most appropriate agent.
- Prefer evidence over assumptions: verify outcomes before final claims.
- Choose the lightest-weight path that preserves quality.
- Consult official docs before implementing with SDKs/frameworks/APIs.
</operating_principles>

<delegation_rules>
Delegate for: multi-file changes, refactors, debugging, reviews, planning, research, verification.
Work directly for: trivial ops, small clarifications, single commands.
Route code to `executor` (use `model=opus` for complex work). Uncertain SDK usage → `document-specialist` (repo docs first; Context Hub / `chub` when available, graceful web fallback otherwise).
</delegation_rules>

<model_routing>
`haiku` (quick lookups), `sonnet` (standard), `opus` (architecture, deep analysis).
Direct writes OK for: `~/.claude/**`, `.omc/**`, `.claude/**`, `CLAUDE.md`, `AGENTS.md`.
</model_routing>

<skills>
Invoke via `/oh-my-claudecode:<name>`. Trigger patterns auto-detect keywords.
Tier-0 workflows include `autopilot`, `ultrawork`, `ralph`, `team`, and `ralplan`.
Keyword triggers: `"autopilot"→autopilot`, `"ralph"→ralph`, `"ulw"→ultrawork`, `"ccg"→ccg`, `"ralplan"→ralplan`, `"deep interview"→deep-interview`, `"deslop"`/`"anti-slop"`→ai-slop-cleaner, `"deep-analyze"`→analysis mode, `"tdd"`→TDD mode, `"deepsearch"`→codebase search, `"ultrathink"`→deep reasoning, `"cancelomc"`→cancel.
Team orchestration is explicit via `/team`.
Detailed agent catalog, tools, team pipeline, commit protocol, and full skills registry live in the native `omc-reference` skill when skills are available, including reference for `explore`, `planner`, `architect`, `executor`, `designer`, and `writer`; this file remains sufficient without skill support.
</skills>

<verification>
Verify before claiming completion. Size appropriately: small→haiku, standard→sonnet, large/security→opus.
If verification fails, keep iterating.
</verification>

<execution_protocols>
Broad requests: explore first, then plan. 2+ independent tasks in parallel. `run_in_background` for builds/tests.
Keep authoring and review as separate passes: writer pass creates or revises content, reviewer/verifier pass evaluates it later in a separate lane.
Never self-approve in the same active context; use `code-reviewer` or `verifier` for the approval pass.
Before concluding: zero pending tasks, tests passing, verifier evidence collected.
</execution_protocols>

<hooks_and_context>
Hooks inject `<system-reminder>` tags. Key patterns: `hook success: Success` (proceed), `[MAGIC KEYWORD: ...]` (invoke skill), `The boulder never stops` (ralph/ultrawork active).
Persistence: `<remember>` (7 days), `<remember priority>` (permanent).
Kill switches: `DISABLE_OMC`, `OMC_SKIP_HOOKS` (comma-separated).
</hooks_and_context>

<cancellation>
`/oh-my-claudecode:cancel` ends execution modes. Cancel when done+verified or blocked. Don't cancel if work incomplete.
</cancellation>

<worktree_paths>
State: `.omc/state/`, `.omc/state/sessions/{sessionId}/`, `.omc/notepad.md`, `.omc/project-memory.json`, `.omc/plans/`, `.omc/research/`, `.omc/logs/`
</worktree_paths>

## Setup

Say "setup omc" or run `/oh-my-claudecode:omc-setup`.
<!-- OMC:END -->

<!-- User customizations -->
@RTK.md

<tool_inventory>
Standing toolset on THIS machine. Before hand-rolling a shell pipeline, browsing blind, grepping for symbols, doing mental math, or answering from memory — spend one beat matching the job against this list; if a capability seems missing, ToolSearch the deferred-tool list before concluding it doesn't exist.
- MCP `rcp` — Windows-fleet PC automation. ANY action against a fleet Windows host goes through these (or `skills/skill run` in nmt-rcp) — never a hand-written ssh line with guessed flags. Tools:
  - `open-app` — launch a Windows app by name or absolute path.
  - `ui-tree` — dump the UI Automation tree of a window as JSON.
  - `ui-find` — find UIA elements by name/automation_id/control_type/class_name.
  - `ui-click` — click a UIA element (raw SendInput, falls back to UIA Invoke).
  - `ui-type` — focus a UIA element and type text via SendInput.
  - `type-text` — type a string into whatever's currently focused.
  - `screenshot` — capture the primary screen as PNG (stdout or file).
  - `browser` — unified Edge CDP control: `launch|eval|fetch` (SendInput-free, works in disconnected RDP).
  - `audio-volume` — read/set system master volume or mute.
  - `enable-rdp` — enable RDP on a host (registry + Tailscale-only firewall rule + optional password).
  - `install-spawn-service` — push + register `rcp-spawn-service.exe` as a LocalSystem service.
  - `build-rcp` — compile the rcp Rust binary on one or more hosts via cargo.
  - `sync-skills` — roll the latest skill vault bundle out to fleet hosts.
  - `fanout` — run another skill across many hosts in parallel, output prefixed by host.
  - `agent-task` — queue a prompt to a host's Session-1 agent poller and return its answer.
  - `ask-agent` — run a peer AI agent (gemini/qwen/claude) locally on the Ubuntu orchestrator.
  - `advisor` — master-side recipe knowledge layer: store verified recipes, compose/run/submit tasks, record ground-truth feedback.
  - `coursera` — manage/deploy/pull the Coursera autopilot fleet (status, progress, posture, start/stop/restart, logs, deploy, pull).
  - `write-formatted-word-doc` — verified composite recipe that produces a formatted Word doc end-to-end.
- MCP `fleet` — control-plane for the nmt-ads-agency Windows fleet. Use for fleet state/rollout questions instead of guessing host state. Tools:
  - `fleet_status` — one-shot health view: enrolled machines + recent tasks with terminal counts.
  - `fleet_list_machines` — list machine ids enrolled in the control-plane.
  - `fleet_assign_task` — assign a task/prompt to machines or profiles (selectors: `*`, `<machine>`, `<machine>.<profile>`, `<profile>`); returns a task id.
  - `fleet_task_status` — read back per-machine status/result of a previously assigned task.
  - `fleet_drop_task` — cancel/drop a queued task so it stops replaying.
  - `fleet_employee_history` — durable task history for a profile (nhân viên) by roster name.
  - `fleet_exec_ps` — run a PowerShell snippet on one Windows box over SSH.
  - `fleet_assign_ring` — assign a machine to a rollout ring (pilot/soak/broad/hold).
  - `fleet_set_ring` — point a ring at a target release version.
  - `fleet_release_target` — show which release version a given machine resolves to.
  - `fleet_releases` — list signed installers in the release registry.
  - `fleet_build` — build the CloakAgent installer from the current tree (no sign/publish).
  - `fleet_publish` — build + sign + publish a release to the registry (IRREVERSIBLE, guarded by a confirm=version check).
  - `fleet_publish_bundle` — publish a golden browser-profile bundle as the next version for a profile.
  - `fleet_bundle_status` — show the current published bundle version + sha256 for a profile.
- LSP — `rust-analyzer-lsp` plugin + OMC `lsp_*` tools: goto-def/references/rename/diagnostics for symbol work in LSP-served repos; never grep alone for symbol renames/impact.
- OMC tools — `ast_grep_*` (structural code search/rewrite), `python_repl` (real computation — no eyeball arithmetic on data), `wiki_*` / `project_memory_*` / notepad (persistent knowledge), `session_search` (past sessions).
- `rtk` — token-optimized CLI proxy, auto-applied by the PreToolUse Bash hook; don't bypass it or re-implement its filtering.
- Skills auto-trigger on keywords (graphify, omc skills, /loop, /schedule, …) — when a request matches a skill, invoke the Skill tool FIRST, before any free-form work.
</tool_inventory>

<graphify>
`/graphify` or "graphify" → invoke Skill `graphify` FIRST, before anything else. Any input → knowledge graph. Def: `~/.claude/skills/graphify/SKILL.md`.
</graphify>

<quality_gates>
Changing app code → run full static-check + test suite before claiming done. Skip ONLY for trivial non-code edits (docs/config/comments) or explicit user opt-out. Gate red → fix + re-run; never report done on red. Long builds/tests → `run_in_background`. Project CLAUDE.md/CI commands override these defaults.
- Rust: `cargo fmt --all` → `cargo clippy --all-targets -- -D warnings` → `cargo build` → `cargo test`. Project build path (e.g. `cargo xwin ...`) overrides plain build.
- Python: `ruff format` → `ruff check` (or project linter) → `mypy`/`pyright` if typed → `pytest`.
</quality_gates>

<project_local_toolchains>
Toolchain + deps stay INSIDE project dir; never mutate system/user global env. Local/pinned over global.
- Python: project-local `.venv` + Poetry (`poetry install`/`add`; run via `poetry run` or `.venv/bin`). No `pip install` to system/user site-packages.
- All tool binaries run from project (`.venv/bin`, `node_modules/.bin`, `./bin`, `vendor/`), never system PATH/global prefix.
- Other langs: project-scoped toolchain + dep dir + lockfile (Node `node_modules`, Rust `rust-toolchain.toml`+`target/`, scoped Go cache).
</project_local_toolchains>

<surgical_changes>
- Surgical edits: touch only what the task needs. No improving adjacent code/comments/formatting, no refactoring what isn't broken; match existing style. Every changed line traces to the request.
- Clean up only YOUR mess: remove imports/vars/funcs YOUR change orphaned; leave pre-existing dead code (mention, don't delete) unless asked.
- No silent assumptions: ambiguous → surface interpretations + ask, don't pick quietly. Simpler path exists → say so. Confused → name what's unclear + stop, don't guess.
</surgical_changes>

<delegation>
Task above trivial scope → do NOT implement directly. Re-prompt into self-contained brief → hand to separate subagent via `/omc-teams` with Sonnet model.
- Master does ONLY: read/inspect, plan/route, write brief, edits BELOW issue level (typos, one-liners, config tweaks, single-file trivial fixes).
- At/above issue level (discrete feature/bugfix/refactor, or multi-step/multi-file) → master must NOT do it; delegate to independent subagent owning it end-to-end. Once master has received + consumed the subagent's result, close it (`TaskStop`, or let it terminate) — no idle/lingering subagents left open.
- Brief = self-contained (goal, context, constraints, verifiable success criteria) so subagent loops to done without re-querying. Spawn teammates in `acceptEdits`.
- Agent↔agent comms ALWAYS English (subagent briefs + cross-session prompts via tmux/`/omc-teams`/`SendMessage`). Never Vietnamese (dấu or không dấu). Reply to human user in their language as normal.
- Stricter override of OMC `<delegation_rules>`: boundary pinned at issue level; `/omc-teams` hand-off mandatory at/above. On overlap, this wins.
</delegation>
