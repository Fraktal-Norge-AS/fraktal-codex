# Fraktal CLI — Changelog

Human-readable summary of Fraktal-specific changes layered on top of
`openai/codex`. Format roughly follows [Keep a Changelog]. For the raw
commit list use `git log upstream/main..fraktal/main --oneline`; for
upstream changes see [openai/codex releases][upstream-releases].

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[upstream-releases]: https://github.com/openai/codex/releases

## [Unreleased] — fork bootstrap

Fraktal patch series on top of upstream `main` (snapshot `bb5054fe47` —
`Capture rollout budget units from response usage`). No tagged Fraktal
release yet.

### Upstream-synk

Rebasert fra `3ded846488` til `bb5054fe47` (1288 oppstrøms-commits). Hele
serien er delt i én commit per funksjon, så en enkelt funksjon kan
droppes eller rebases for seg. Tilpasninger som fulgte av synken:

- `ResponseItem::metadata` heter nå
  `internal_chat_message_metadata_passthrough`; item-ID-er ble
  `Option<ResponseItemId>`; `FunctionCall` fikk `encrypted_function_args`
  og `FunctionCallOutput` fikk `id`.
- `ContentItem` / `FunctionCallOutputContentItem` fikk `InputAudio`, som
  Chat Completions ikke kan representere — droppes som kryptert innhold.
- Chat-stien speiler nå Responses-stien: transport fra
  `build_api_transport`, feil via `provider.map_api_error`, og
  `map_response_stream` / `handle_unauthorized` tar provideren.
- `.github/workflows/bazel.yml` er ikke lenger slettet, men gated med
  `if: github.repository == 'openai/codex'` (samme mønster som
  `rust-release.yml`). Sletting ga delete/modify-konflikt hver gang
  oppstrøms rørte fila.
- `codex-mcp/src/connection_manager.rs` ble splittet i en modulkatalog
  oppstrøms; den tolerante server-navn-oppslaget ligger nå i
  `connection_manager/resources.rs` der `client_by_name` bor.

Kjent: `code-mode-runtime` bygger ikke på Windows fordi oppstrøms
`v8`-avhengighet ikke finner et ferdigbygd arkiv for målet. Ikke relatert
til fork-endringene.

### Added

- **`RELEASING.md`** — rebase runbook, branch model, smoke test,
  follow-ups list.
- **`README.md`** — rewritten in Norwegian Bokmål to reflect what the
  fork actually is and how to use it. Adds `fraktal_logo.png` at repo
  root as the header image.
- **`FRAKTAL_TODO.md` / `FRAKTAL_CHANGELOG.md`** — project tracking
  surface.
- **Egen hjemmekatalog `~/.fraktal`** — innstillinger og tilstand
  (config, auth, historikk, sesjoner, logger) ligger nå under
  `~/.fraktal` i stedet for `~/.codex`, så Fraktal og en eventuell
  Codex-installasjon ikke deler tilstand. `FRAKTAL_HOME` overstyrer
  stien; `CODEX_HOME` godtas fortsatt som fallback slik at verktøy og
  skript fra oppstrøms virker uendret. Den repo-lokale `.codex/`-
  prosjektkatalogen er bevisst uendret.
- **Chat Completions wire-API gjeninnført** — oppstrøms fjernet `chat`
  (`d2394a2494`, discussion #7782) for å gå Responses-only. Fraktal
  porterer den tilbake så vi treffer OpenAI-kompatible Chat
  Completions-tjenester (OpenRouter, DeepInfra, Groq, …) direkte uten
  oversetter-proxy. Omfang (minimal sti):
  - `WireApi::Chat` tilbake i `codex-model-provider-info` (+ deserialisering
    av `wire_api = "chat"`).
  - `ChatRequestBuilder` + chat-SSE-parser + `ChatClient` gjeninnført i
    `codex-api`, tilpasset dagens `EndpointSession`-arkitektur.
  - `create_tools_json_for_chat_completions_api` tilbake i `codex-tools`.
  - `WireApi::Chat`-gren i `core/src/client.rs` (`stream_chat_completions`)
    som speiler Responses-stien, uten WebSocket/reasoning/compaction.
  - **OpenRouter-provider** — `--profile openrouter` mot
    `https://openrouter.ai/api/v1` med `wire_api = "chat"`, dokumentert med
    `z-ai/glm-5.2`.
  - Merk: chat-stien har ingen Responses-native funksjoner (server-side
    reasoning, kryptert reasoning, remote compaction). Disse er
    protokoll-begrensninger, ikke modell-begrensninger.

### Changed — rebrand

- Renamed the Rust binary from `codex` to `fraktal`
  (`codex-rs/cli/Cargo.toml`, `clap` `bin_name` in
  `codex-rs/cli/src/main.rs`, npm wrapper bin entry and shim filename).
- `fraktal --version` skriver nå `fraktal <versjon>` i stedet for
  `codex-cli <versjon>` — `clap` bruker `name` (som defaulter til
  crate-navnet), ikke `bin_name`, på versjonslinja. `--help` starter med
  «Fraktal CLI». Wire-identifikatorer (`User-Agent`, `agent_harness_id`,
  `SessionSource`) er bevisst uendret — de er protokollverdier, ikke
  visningsnavn.
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

- Repo-lokal `.codex/`-prosjektkatalog (uendret med vilje — så Fraktal
  fortsatt leser prosjektkonfigurasjon team-et allerede har sjekket inn).
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
