# Fraktal CLI — Changelog

Human-readable summary of Fraktal-specific changes layered on top of
`openai/codex`. Format roughly follows [Keep a Changelog]. For the raw
commit list use `git log upstream/main..fraktal/main --oneline`; for
upstream changes see [openai/codex releases][upstream-releases].

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[upstream-releases]: https://github.com/openai/codex/releases

## [Unreleased] — fork bootstrap

Initial Fraktal patch series on top of upstream `main` (snapshot
`2d1ad374a7` — `feat(tui): make turn interruption keybind configurable`).
No tagged Fraktal release yet.

### Added

- **`RELEASING.md`** — rebase runbook, branch model, smoke test,
  follow-ups list.
- **`README.md`** — rewritten in Norwegian Bokmål to reflect what the
  fork actually is and how to use it. Adds `fraktal_logo.png` at repo
  root as the header image.
- **`FRAKTAL_TODO.md` / `FRAKTAL_CHANGELOG.md`** — project tracking
  surface.

### Changed — rebrand

- Renamed the Rust binary from `codex` to `fraktal`
  (`codex-rs/cli/Cargo.toml`, `clap` `bin_name` in
  `codex-rs/cli/src/main.rs`, npm wrapper bin entry and shim filename).
- Repointed `doctor`'s update-check URL from `openai/codex` to
  `Fraktal-Norge-AS/fraktal-codex`. Updated brew/npm/bun labels.
- Rebranded TUI splash text: welcome line and session/status card
  headers say "Fraktal" instead of "OpenAI Codex". Norwegian tagline
  on the welcome screen. Snapshot tests under `codex-rs/tui/src/**`
  need `cargo insta accept` (tracked in `FRAKTAL_TODO.md`).

### Changed — privacy

- Feature-gated the built-in Statsig telemetry exporter behind a new
  `openai-telemetry` cargo feature on `codex-otel` (off by default).
  Internal builds never contact `ab.chatgpt.com`. (`e3bccc9f21`)

### Changed — privacy

- Feature-gated the built-in Statsig telemetry exporter behind a new
  `openai-telemetry` cargo feature on `codex-otel` (off by default).
  Internal builds never contact `ab.chatgpt.com`.

### Removed

- Deleted `.github/workflows/cla.yml` — was enforcing OpenAI's CLA on
  every PR to the fork.
- Deleted `.github/workflows/bazel.yml` — required Bazel remote-cache
  secrets we don't have; cargo is the canonical build.

### Disabled

- Gated the entire `rust-release.yml` pipeline behind
  `github.repository == 'openai/codex'` so it self-skips on the fork.
  Scaffolding stays intact for when we wire up our own publish
  credentials.

### Deliberately NOT changed

These would have inflated the patch series for marginal benefit; they
live in [`FRAKTAL_TODO.md`](./FRAKTAL_TODO.md) if revisited:

- `~/.codex/` config directory (unchanged on purpose — keeps upstream
  config tooling working; `CODEX_HOME` overrides if you want).
- ChatGPT login flow (left intact; harmless when a default
  `model_provider` is configured).
- npm platform-package publishing pipeline (deferred until we set up
  our own npm registry).

---

## Conventions

- One commit per intent, prefix `[fraktal]`. Run
  `git log upstream/main..fraktal/main --oneline` for the live list.
- Add an entry here when a patch lands. Keep entries short — the
  commit message has the detail.
- When we cut a Fraktal release, replace the `Unreleased` heading with
  the tag (e.g. `## [rust-v0.131.0-fraktal.1] — 2026-06-01`) and start
  a new `Unreleased` section above it.
