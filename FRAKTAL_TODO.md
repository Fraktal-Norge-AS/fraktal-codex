# Fraktal CLI — TODO

What's left to make the fork actually usable, ordered roughly by what
unblocks the most. Update as items land or scope shifts. Items already
done live in [`FRAKTAL_CHANGELOG.md`](./FRAKTAL_CHANGELOG.md); the full
context lives in `~/.claude/plans/crispy-singing-moth.md`.

## Critical path (blocks day-1 use)

- [ ] **Register the "Fraktal CLI" Entra enterprise app.** Owner: Azure
  admin. Outputs: tenant ID, client (application) ID, granted scopes
  (`Cognitive Services OpenAI User` on the AOAI resource, plus whatever
  narrow scopes the agent should be able to reach). Required for both
  `fraktal-auth` and the default Azure profile.
- [ ] **Build the `fraktal-auth` helper binary.** New repo
  `Fraktal-Norge-AS/fraktal-auth`. Subcommands: `login` (Entra
  device-code flow, refresh token to OS keyring) and `token --scope <S>`
  (refresh-for-access exchange, stdout). Crates: `clap`, `reqwest`,
  `serde`, `keyring`, `anyhow`. Compile-in the tenant/client IDs from
  the step above. See plan §4.
- [ ] **Provision the AOAI deployment.** Owner: Azure admin. Pick a
  model (`gpt-5-codex` per the plan, or whatever's actually deployed),
  note the resource endpoint and deployment name. Update the template
  in README and the installer.

## Distribution (so people can install without `cargo build`)

- [ ] **Homebrew tap.** New repo `Fraktal-Norge-AS/homebrew-tap` with a
  `fraktal.rb` formula. Formula depends on `fraktal-auth`, downloads
  the static MUSL binary from our GitHub Releases, runs a post-install
  step that writes `~/.codex/config.toml` if missing and prompts the
  user to run `fraktal-auth login`.
- [ ] **Windows MSI.** Signed installer built from the same Rust
  artifact. Same template-write + login prompt. Winget manifest as a
  stretch goal.
- [ ] **GitHub Releases pipeline.** Repoint `.github/workflows/`
  release jobs (currently gated off on the fork) to publish our own
  artifacts. Requires CI secrets: signing keys, npm token if/when we
  publish, Homebrew bump token.
- [ ] **Default `config.toml` template.** Lives in the installer
  artifacts above, not in this repo. The template body is in
  [`README.md`](./README.md#konfigurasjon) and in the plan.

## In-repo follow-ups (small, can be picked up anytime)

- [ ] **Regenerate TUI snapshot tests after the splash rebrand.** The
  splash text changes (`OpenAI Codex` → `Fraktal`) shift layout in ~19
  insta snapshots under `codex-rs/tui/src/**/snapshots/`. Run
  `cd codex-rs && cargo insta test --review -p codex-tui` (or
  `cargo insta accept` after confirming a diff). Until this lands,
  `cargo test -p codex-tui` fails for the affected tests.
- [ ] **`--version` banner.** `fraktal --version` still prints
  `codex-cli 0.0.0` because the Cargo package name is `codex-cli`.
  Either rename the package (workspace-wide ripple) or override the
  `version` clap attribute. Low priority.
- [ ] **npm wrapper rebrand of platform packages.** Patch 1 renamed
  `bin/fraktal.js` and the local binary lookup, but
  `codex-cli/scripts/build_npm_package.py` and the `@openai/codex-*`
  platform-package names inside `bin/fraktal.js` are untouched. Rebrand
  these when we set up our own npm publishing (or delete the npm
  wrapper entirely if we never plan to publish there).
- [ ] **`.github/CODEOWNERS`, PR/issue templates.** Still reference
  `@openai/codex-core-agent-team` and OpenAI doc URLs. Replace or
  delete; not urgent until the repo has external contributors.

## Org-policy follow-ups (requires org-owner cooperation)

- [ ] **Make `fraktal/main` the GitHub default branch.** Currently blocked
  by an org-level policy that forces all repos to default to `main`, and
  by a "Branch protection of default branch" ruleset that bans
  force-push and requires PRs on `~DEFAULT_BRANCH`. Until an org owner
  either exempts this repo or drops the policy, people landing on the
  GitHub home page see upstream's README rather than ours. The README
  banner is the workaround. Option B in the plan; see `RELEASING.md`
  for the full trade-off analysis.

## Optional / when it becomes useful

- [ ] **Azure MCP integration.** Uncomment the `[mcp_servers.azure]`
  block in the shipped config when employees actually need agent-driven
  Azure tool access (read logs, query storage, etc.). Wrapper script
  exports the bearer token to `FRAKTAL_AZURE_TOKEN` before launching;
  same `fraktal-auth token` call provides it. No fork patches required.
- [ ] **Internal OTEL endpoint** instead of fully-off. Right now
  Statsig telemetry is feature-gated off (`codex-otel/openai-telemetry`).
  If we want internal observability later, point an OTLP endpoint at our
  own collector and re-enable.
- [ ] **`fraktal-auth` access-token cache.** v1 hits AAD on every Codex
  call (every ~5 min per `refresh_interval_ms`). Cheap (~100ms), but if
  it becomes a bottleneck, cache access tokens in `/tmp` or keyring
  with TTL.
- [ ] **Per-user vs. shared SP audit.** Plan picked per-user device-code
  for clean audit trails. Revisit if onboarding friction is too high
  for the team size.
