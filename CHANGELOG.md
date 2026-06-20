# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Deferred

- **LICENSE not yet chosen** — no license file is committed; usage terms are
  undecided.
- **`bin/rtk` de-bloat pending** — the ~9.6 MB binary is still committed straight
  into git history. Two outward-facing options remain deferred (each rewrites
  history or publishes artifacts and needs an explicit decision): `git lfs
  migrate` the binary, or publish `rtk` as a GitHub Release asset and have
  `setup.sh` download + verify it against `bin/rtk.sha256`.

## [1.0.0] - 2026-06-20

First tagged baseline of the version-controlled Claude Code configuration +
`setup.sh` bootstrap.

### Added

- **Initial config capture** — `settings/`, `claude-md/` (CLAUDE.md / RTK.md),
  `plugins/`, `skills/`, `env/auto-compact.env`, and a full-bootstrap `setup.sh`
  that installs `claude` / `omc` / `rtk` and applies all config idempotently.
- **`vendor/claude-switch` vendored as a git submodule** — the dual-auth switch
  (`claude-max` / `claude-qwen` / bare-`claude` prompt) ships as a pinned
  submodule, making the bundle self-contained and portable.
- **Project-local toolchain / dependency-isolation rule** added to CLAUDE.md
  (Python `.venv` + Poetry; keep all toolchains and bin paths project-local).
- **Rust/Python quality gates** and Karpathy-style surgical-changes /
  delegation rules in CLAUDE.md.
- **`bin/rtk` provenance guard** — `bin/rtk.sha256` records the binary's SHA-256;
  `setup.sh` verifies the bundled binary before install and **skips on
  mismatch** rather than placing an unverified binary.
- **GitHub Actions CI + `bats` test suite** — `lint` (shellcheck / shfmt / JSON
  validation), `smoke` (`setup.sh --config-only` apply + idempotency), and
  `bats` (`test/` suite); CI badge added to the README.
- **`setup.sh` safety flags** — `--dry-run` (print the plan, make no changes),
  `--uninstall` (remove the `$PROFILE` blocks, backing it up first), and
  `--help` / `-h`, alongside strict argument parsing.

### Changed

- **Headroom fully retired** — the switch now talks **direct upstream** (no
  proxy) for verbatim accuracy. The `claude-hr` launcher and all Headroom
  bundling were removed; Headroom is no longer part of this repo.
- **`claude-qwen` fails fast** — exits with a clear message when
  `vendor/claude-switch/.env` is missing or still holds the placeholder token,
  instead of launching anonymously against the wrong endpoint.
- **Submodule cloned over HTTPS** — anonymous clone works without an SSH key, and
  `setup.sh` now surfaces submodule init failures instead of swallowing them.
- **Plugins runtime-field cleanup** — dropped per-machine runtime fields
  (e.g. `installPath`, which leaked the username and broke portability) from the
  `plugins/*.json` desired-state files.

### Security

- **Hardening pass** — unblocked `.github/` in `.gitignore` (so CI config is
  tracked), quoted the bashrc switch-source line, and `chmod 600` the scaffolded
  `vendor/claude-switch/.env` since it holds a real API token.

[Unreleased]: https://github.com/JamesPersonalCode56/claude-code-settings/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/JamesPersonalCode56/claude-code-settings/releases/tag/v1.0.0
