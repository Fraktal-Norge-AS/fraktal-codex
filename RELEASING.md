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
  in `~/.fraktal/config.toml` (delivered by the installer), in the
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

### Conflict patterns seen so far

- **One commit per feature.** Never let work pile up as one big patch. The
  conflicts are the same either way, but split commits tell you *which
  feature* each conflict belongs to, and let you drop a feature instead of
  untangling it. Keep the working tree clean before starting.
- **Additive struct/field conflicts are the common case.** Upstream adds a
  field where we added ours (`supports_standalone_web_search` vs
  `discover_models`). Resolution is "keep both sides" — this accounted for
  26 of 31 conflicts in the `bb5054fe47` sync.
- **An empty `HEAD` side means upstream moved the code**, not that it
  deleted it. Check with `git grep -l '<symbol>' upstream/main` before
  accepting our side, or you will re-add a few hundred lines of relocated
  upstream code. Re-apply only *our* delta at the new location.
- **`config.schema.json` is generated.** Hand-merge it if you must, but the
  authority is `cargo test -p codex-core --lib -- config::schema::tests::config_schema_matches_fixture`
  (byte-exact, including the trailing newline), or regenerate with
  `just write-config-schema`.
- **Deleting an upstream file guarantees recurring conflicts.** Gate it
  instead (`if: github.repository == 'openai/codex'`). If the job already
  has an `if:`, fold the condition in — a duplicate YAML key is silently
  dropped.
- **Serialized structs have expectation fixtures elsewhere.** Adding a
  field to `ModelProviderInfo` also changes the TOML in
  `config/src/thread_config.rs` tests. `cargo check` will not catch this;
  only running the tests will.

## Smoke test

```sh
cd codex-rs
# Windows debug test binaries overflow the default stack on upstream's
# async tests; harmless but it aborts the run.
RUST_MIN_STACK=67108864 cargo test -p codex-core -p codex-config -p codex-api \
  -p codex-models-manager -p codex-mcp -p codex-tools -p codex-utils-home-dir --lib
cargo fmt --all -- --check
cargo clippy --all-targets -p codex-core -p codex-cli -p codex-api

cargo build --release -p codex-cli
./target/release/fraktal --version
./target/release/fraktal --help | head -5    # confirm bin_name = fraktal
FRAKTAL_HOME=/definitely/not/here ./target/release/fraktal debug prompt-input
# ^ must fail naming FRAKTAL_HOME — proves home resolution is wired
```

`cargo check --workspace` does **not** pass on Windows: upstream's `v8`
dependency has no prebuilt archive for `x86_64-pc-windows-msvc`, so
`code-mode-runtime` and `v8-poc` fail to build. Build the crates you
touched instead, or set `V8_FROM_SOURCE=1` if you need the full workspace.

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
As of the `bb5054fe47` sync:

```
[fraktal] rebrand binary, disable OpenAI telemetry and CI, repoint update check
[fraktal] add Fraktal docs, logo, and ml-dev-titan config template
[fraktal] document DeepInfra provider via LiteLLM proxy
[fraktal] restore `chat` wire API for OpenAI-compatible providers
[fraktal] discover provider models from the OpenAI-compatible /models endpoint
[fraktal] make MCP tools usable from non-namespace-aware models
[fraktal] document the chat wire API, model discovery and MCP flattening
[fraktal] adapt fork features to upstream API changes
[fraktal] store settings and state in ~/.fraktal
[fraktal] satisfy rustfmt and clippy after the upstream merge
```

Cost ranking, by how much upstream churns the files each patch touches
(commits between `3ded846488` and `bb5054fe47`):

| Patch | Hottest files it touches |
| --- | --- |
| MCP flattening + tolerant resolution | `spec_plan.rs` 43, `connection_manager.rs` 38, `registry.rs` 11 |
| chat wire API | `client.rs` 30, `codex-api/lib.rs` 7, `tool_spec.rs` 4 |
| rebrand | `cli/main.rs` 26, `rust-release.yml` 10, `cli/Cargo.toml` 9 |
| model discovery | `model_info.rs` 9, `manager.rs` 4 |

**`[fraktal] make MCP tools usable from non-namespace-aware models` is the
most expensive patch and the best upstreaming candidate.**
`ProviderCapabilities::namespace_tools` is `true` for *every* provider, so
Codex emits Responses-API `type: "namespace"` tools unconditionally — but
only the OpenAI GPT-5 family implements that convention. Every other model
sees an opaque wrapper and cannot call the tools inside, making MCP tools
silently invisible. That is an upstream bug, not a Fraktal preference; if
upstream fixes it we drop our highest-churn patch. Until then, watch it on
rebase: it lives in a hot dispatch path, so if upstream reworks
`ToolRegistry::dispatch_any_with_terminal_outcome`, `flat_tool_name`, or
`build_model_visible_specs`, re-verify the fallback still fires before the
`unsupported call` return.

**`[fraktal] restore `chat` wire API`** is a deliberate revert of upstream
discussion #7782. It is the largest patch (~1250 lines) in the area upstream
refactors most. It exists so Ollama and OpenRouter work with no extra
infrastructure; if the LiteLLM proxy path (see README) proves sufficient for
those too, this patch can be dropped outright.

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
- **Default `~/.fraktal/config.toml` template** for the installer. Lives in
  the Homebrew tap formula and the MSI installer, not in this repo. See
  the plan file for the template body.
- **`fraktal-auth` helper binary.** Lives in `Fraktal-Norge-AS/fraktal-auth`
  (separate repo), not in this workspace.
- **Splash / banner rebrand** (cosmetic) at
  `codex-rs/tui/src/onboarding/welcome.rs` and
  `codex-rs/tui/src/history_cell/session.rs`. Add when someone cares.
