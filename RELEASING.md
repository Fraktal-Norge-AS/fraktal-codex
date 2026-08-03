# Releasing Fraktal CLI

This file is Fraktal-specific and lives only on `fraktal/main`. Upstream
(`openai/codex`) knows nothing about it.

## Branch model

- `main` mirrors `upstream/main` (no Fraktal commits land here).
- `fraktal/main` is the long-lived release branch. It carries a small patch
  series on top of `upstream/main` and is **rebased** (never merged) onto
  upstream.
- Every Fraktal commit is prefixed `[fraktal]` so the patch series is auditable:
  `git log upstream/main..fraktal/main --oneline`.

`main` stays the GitHub default because the Fraktal-Norge-AS org enforces
a "default branch must be named `main`" policy that repo admins can't
override. That means people landing on the repo home page see upstream's
README, not ours — the banner at the top of this README is the consolation
prize. The proper fix is org-owner-level (see [`FRAKTAL_TODO.md`](./FRAKTAL_TODO.md));
until then we live with the split.
- **Patch budget: 10 commits.** Every commit on `fraktal/main` is a recurring
  rebase cost. Before adding a new one, consider whether the change can live
  in `~/.codex/config.toml` (delivered by the installer), in the
  `fraktal-auth` helper, or in a follow-up tap formula.

## One-time setup

```sh
git remote add upstream https://github.com/openai/codex.git
git fetch upstream --tags
git checkout main && git merge --ff-only upstream/main
git checkout -b fraktal/main   # if not already created
```

## Routine rebase against upstream

OpenAI ships Codex multiple times a week. Rebase weekly (or whenever an
upstream feature you want lands).

```sh
git fetch upstream --tags
git checkout main
git merge --ff-only upstream/main           # local main tracks upstream
git checkout fraktal/main
git rebase upstream/main                    # replay the [fraktal] commits
```

If a patch conflicts:

1. Fix it in-place — do **not** widen the patch to "make it easier".
2. If the same patch conflicts on two consecutive upstream releases, that is
   the signal that the patch should shrink, move into the installer, or move
   into `fraktal-auth`. File an issue; do not let it accrete.

After a clean rebase, run the smoke test below before force-pushing.

## Smoke test

```sh
cd codex-rs
cargo build --release -p codex-cli
./target/release/fraktal --version
./target/release/fraktal --help | head -5    # confirm bin_name = fraktal
```

Optional end-to-end checks when the helper + config are in place:

- With Ollama running locally: `./target/release/fraktal "say hi"` — should
  reach the local model without any login prompt.
- With `fraktal-auth` on PATH and the Azure profile present:
  `./target/release/fraktal --profile azure "say hi"` — should invoke the
  auth helper once and reach Azure OpenAI.
- Outbound HTTP capture (`HTTPS_PROXY=…`) should show **no** requests to
  `ab.chatgpt.com`. Statsig telemetry is feature-gated off; turn it on with
  `--features codex-otel/openai-telemetry` only if you intend to send to
  OpenAI.

## Publishing a release

1. Pick the upstream tag you're tracking (upstream uses the `rust-v0.X.Y`
   tag scheme; `codex-rs/cli/src/doctor/updates.rs` parses the `rust-v`
   prefix, so our tags must keep it).
2. Tag the tip of `fraktal/main` as `rust-v0.X.Y-fraktal.N`
   (`fraktal.N` is our local revision counter against that upstream
   release).
3. Push the tag to `origin` — CI publishes the GitHub release.

## Force-push procedure

`fraktal/main` history is rewritten on every rebase, so pushing is a
force-push.

```sh
git push --force-with-lease origin fraktal/main
```

Always `--force-with-lease`, never `--force`. If someone else has pushed
intermediate commits to `origin/fraktal/main`, stop and reconcile —
do not blow their work away.

## Current patch series

Run `git log --oneline upstream/main..fraktal/main` to see the live list.
At the time of the initial fork it was:

```
[fraktal] disable fork-unsafe CI workflows
[fraktal] add RELEASING.md rebase runbook
[fraktal] feature-gate Statsig telemetry exporter
[fraktal] repoint update-check URL and brand strings
[fraktal] rename binary codex -> fraktal
[fraktal] tolerant MCP tool-name resolution for local models
```

`[fraktal] tolerant MCP tool-name resolution` touches
`core/src/tools/registry.rs` (+ `registry_tests.rs`): on an exact tool-lookup
miss, `resolve_fuzzy_mcp_name` / `canonical_tool_key` resolve `mcp__server__tool`
calls whose namespace was flattened into the name or whose `__` separator was
mangled to `.`/`:`. Needed because OpenAI-compatible chat-completions models
(Ollama: qwen3.5, gemma4) don't reproduce the exact host-side namespaced name.
Watch this one on rebase — it lives in a hot dispatch path; if upstream reworks
`ToolRegistry::dispatch_any_with_terminal_outcome` or `flat_tool_name`, re-verify
the fallback still fires before the `unsupported call` return.

Each commit is documented in its message; they are intentionally narrow.
See `C:\Users\EmilLindfors\.claude\plans\crispy-singing-moth.md` for the
full plan and rationale.

## Open follow-ups (NOT yet done in this repo)

These were deliberately deferred to keep the patch series small. Pick them
up when the corresponding infrastructure is ready.

- **npm wrapper rebrand of the platform-package pipeline.** Patch 1 renamed
  the `bin/` entry and updated the Rust binary lookup inside the JS shim,
  but `codex-cli/scripts/build_npm_package.py` and the `@openai/codex-*`
  platform-package names inside `bin/fraktal.js` are untouched. They need
  to be rebranded as part of setting up our own npm publishing — until
  then, the npm wrapper is non-functional (Brew/MSI are the primary
  distribution channels).
- **`.github/workflows/`** still target upstream's release artifacts and
  signing keys. Repoint them when CI is wired up.
- **Default `~/.codex/config.toml` template** for the installer. Lives in
  the Homebrew tap formula and the MSI installer, not in this repo. See
  the plan file for the template body.
- **`fraktal-auth` helper binary.** Lives in `Fraktal-Norge-AS/fraktal-auth`
  (separate repo), not in this workspace.
- **Splash / banner rebrand** (cosmetic) at
  `codex-rs/tui/src/onboarding/welcome.rs` and
  `codex-rs/tui/src/history_cell/session.rs`. Add when someone cares.
