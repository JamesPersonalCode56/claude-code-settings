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
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.

# Quality gates (Rust / Python)
When developing or changing application code, run the language's full static-check + test suite before claiming a change is done — skip only for trivial non-code edits (docs, config, comments) or when the user explicitly says so.
- **Rust:** `cargo fmt --all` → `cargo clippy --all-targets -- -D warnings` → `cargo build` → `cargo test`. A project-specific build path in CLAUDE.md (e.g. `cargo xwin ...`) overrides plain `cargo build`.
- **Python:** `ruff format` → `ruff check` (or the project's configured linter) → `mypy`/`pyright` if type hints are used → `pytest`.
Prefer the exact commands a project's CLAUDE.md / CI defines; fall back to the above when none is specified. Run long builds/tests with `run_in_background`. If a gate fails, fix and re-run — do not report completion on a red gate.

# Surgical changes & no silent assumptions
(Distilled from Karpathy's notes on LLM coding pitfalls — the parts not already covered above.)
- **Surgical edits.** Touch only what the task requires. Don't "improve" adjacent code, comments, or formatting; don't refactor what isn't broken; match the existing style even if you'd do it differently. Every changed line must trace to the request.
- **Clean up only your own mess.** Remove imports/vars/functions that YOUR change orphaned; leave pre-existing dead code alone (mention it, don't delete it) unless asked.
- **No silent assumptions.** If the request is ambiguous, surface the interpretations and ask — don't pick one quietly. If a simpler approach exists, say so. When confused, name what's unclear and stop rather than guessing.

# Execution by delegation (master = router, subagents = doers)
When executing a task above trivial scope, do NOT implement it directly. Re-prompt it into a self-contained brief and hand it to a separate subagent to execute via `/omc-teams` (oh-my-claudecode:omc-teams).
- **Master agent does only:** read/inspect, plan and route work, write the task brief, and small edits *below issue level* — typos, one-liners, config tweaks, single-file trivial fixes.
- **At or above issue level** (a discrete feature / bugfix / refactor, or anything multi-step or multi-file): the master must NOT do it itself — delegate to an independent subagent that owns the work end-to-end.
- The brief must be self-contained (goal, context, constraints, verifiable success criteria) so the subagent can loop to done without re-querying the master. Spawn teammates in `acceptEdits` mode.

> **Relation to OMC `delegation_rules`:** this rule is a stricter override of the OMC block above, not a contradiction. OMC says "delegate specialized work, work directly for trivial ops" — this pins the boundary at *issue level* and makes `/omc-teams` hand-off mandatory for anything at/above it. On any overlap, follow this rule.