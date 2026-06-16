<p align="center">
  <img src="./fraktal_logo.png" alt="Fraktal" width="200" />
</p>

# Fraktal CLI

> **Merknad om grener:** Du er på `fraktal/main` — Fraktals arbeidsgren.
> Repoens default-gren `main` speiler `openai/codex` urørt på grunn av
> en org-policy som låser default til `main`. Alle Fraktal-spesifikke
> endringer (binærnavn, Azure-profil, telemetri-av, denne dokumentasjonen)
> ligger her. Hvis du landet på `main` og lurer på hvor Fraktal-koden er
> — den er her. Bytt gren øverst til venstre på GitHub, eller `git
> checkout fraktal/main` lokalt. Se [`RELEASING.md`](./RELEASING.md) for
> hvorfor modellen ser slik ut.

**Fraktal CLI** er Fraktals interne kode-agent for terminalen. Det er en
lett fork av [OpenAIs Codex](https://github.com/openai/codex) som er
satt opp til å snakke med interne modeller — en lokal LLM som standard,
og Azure OpenAI med Entra ID-autentisering når du trenger en sterkere
modell.

> Det meste av funksjonaliteten kommer fra Codex selv. Forken legger kun
> til det som må endres for at den skal være vår: rebranding av
> binærnavnet, intern oppdateringssjekk, og telemetri som er slått av.
> Se [`RELEASING.md`](./RELEASING.md) for forholdet til oppstrøms.

---

## Status

Forken er fersk og under oppbygging. Følgende fungerer i dag:

- Binæret bygger og kjører som `fraktal` (ikke `codex`).
- Statsig-telemetri til OpenAI er slått av som standard.
- Oppdateringssjekken peker mot vår egen GitHub Release.

Følgende er planlagt, men ikke ferdig:

- **`fraktal-auth`** — hjelpeprogrammet som henter Entra-tokener for
  Azure OpenAI-profilen. Skal ligge i eget repo
  (`Fraktal-Norge-AS/fraktal-auth`).
- **Installasjonspakker** — Homebrew-tap for macOS/Linux og signert MSI
  for Windows. Inntil disse er på plass, må du bygge fra kilde.
- **Standard `~/.codex/config.toml`** levert av installeren. Inntil
  videre må du legge inn konfigurasjonen selv (mal nedenfor).

## Bygg fra kilde

Krever Rust (toolchain-versjon styres av `codex-rs/rust-toolchain.toml`,
rustup installerer riktig versjon automatisk).

```sh
git clone https://github.com/Fraktal-Norge-AS/fraktal-codex.git
cd fraktal-codex/codex-rs
cargo build --release -p codex-cli
```

Binæret havner i `codex-rs/target/release/fraktal` (eller `fraktal.exe`
på Windows). Legg det på `PATH` selv, eller bruk det direkte.

## Konfigurasjon

Konfigurasjonen ligger i `~/.codex/config.toml` (stien arves fra
oppstrøms — `CODEX_HOME` overstyrer hvis ønskelig). Når installeren er
klar vil den skrive en mal hvis filen mangler. Inntil videre:

```toml
# Standard: Fraktals Ollama-server (krever VPN / kontornett)
model_provider = "fraktal-ollama"
model = "qwen3.5:27b"                # generell modell med tool-calling
                                     # og thinking (~17 GB, 256K kontekst).
                                     # Andre modeller med tool-støtte på
                                     # ml-dev-titan:
                                     #   glm-4.7-flash:latest  (~19 GB, MoE)
                                     #   gemma4:26b            (~18 GB)
                                     # NB: deepseek-coder-v2:16b støtter
                                     # IKKE tool-calling og kan ikke brukes
                                     # av Fraktal-agenten.
                                     # Oppdatert liste + capabilities:
                                     #   curl .../api/tags
                                     #   curl .../api/show -d '{"model":"X"}'

[model_providers.fraktal-ollama]
name = "Fraktal Ollama (ml-dev-titan)"
base_url = "http://ml-dev-titan.fraktal.as:11434/v1"
# wire_api er "responses" som standard og er den eneste gyldige verdien.

# Bytt til Azure med: fraktal --profile azure
[profiles.azure]
model_provider = "fraktal-azure"
model = "gpt-5-codex"                # AOAI deployment-navn

[model_providers.fraktal-azure]
name = "Fraktal Azure OpenAI"
base_url = "https://fraktal-aoai.openai.azure.com/openai/deployments/gpt-5-codex"
wire_api = "responses"
requires_openai_auth = false

[model_providers.fraktal-azure.http_headers]
"api-version" = "2026-02-01"

[model_providers.fraktal-azure.auth]
command = "fraktal-auth"
args = ["token", "--scope", "https://cognitiveservices.azure.com/.default"]
refresh_interval_ms = 300000
timeout_ms = 10000

# Bytt til DeepInfra med: fraktal --profile deepinfra
# Krever en oversetter-proxy (se under) fordi Codex kun snakker
# Responses-API-et, mens DeepInfra kun tilbyr Chat Completions.
[profiles.deepinfra]
model_provider = "fraktal-deepinfra"
model = "kimi-k2-code"               # model_name definert i LiteLLM-proxyen

[model_providers.fraktal-deepinfra]
name = "DeepInfra (via LiteLLM-proxy)"
base_url = "http://localhost:4000/v1"   # LiteLLM-proxyens /v1/responses
wire_api = "responses"
requires_openai_auth = false
# Nøkkelen Fraktal sender til proxyen. Lokalt uten proxy-auth kan denne
# linjen droppes; i delt drift settes LiteLLMs master key her.
env_key = "LITELLM_MASTER_KEY"
```

### DeepInfra via oversetter-proxy

DeepInfra eksponerer kun Chat Completions
(`https://api.deepinfra.com/v1/openai`), mens Codex/Fraktal utelukkende
snakker Responses-API-et (`wire_api = "responses"` er eneste gyldige
verdi — oppstrøms fjernet `chat`, se
[openai/codex#7782](https://github.com/openai/codex/discussions/7782)).
Derfor kan ikke Fraktal treffe DeepInfra direkte. Løsningen er en
[LiteLLM](https://docs.litellm.ai/docs/simple_proxy)-proxy som tilbyr et
`/v1/responses`-endepunkt og oversetter til DeepInfras Chat Completions.

`litellm_config.yaml`:

```yaml
model_list:
  - model_name: kimi-k2-code
    litellm_params:
      model: deepinfra/moonshotai/Kimi-K2.7-Code
      api_key: os.environ/DEEPINFRA_TOKEN
```

Start proxyen (lytter på `http://localhost:4000`):

```sh
export DEEPINFRA_TOKEN=...           # fra https://deepinfra.com/dash/api_keys
pip install "litellm[proxy]"
litellm --config litellm_config.yaml
```

Deretter:

```sh
fraktal --profile deepinfra "skriv en kort sammendrag av denne mappen"
```

NB: oversettelsen gir vanlig chat + tool-calling, men Responses-native
funksjoner (server-side reasoning-items, kryptert reasoning, remote
compaction) er ikke tilgjengelige bak proxyen. Det er greit for Kimi
K2-Code, som ikke er en reasoning-modell i OpenAI-forstand.

`ollama` og `lmstudio` finnes også som innebygde provider-ID-er i Codex,
men de er låst til `localhost:11434` / `localhost:1234` og kan ikke
overstyres via TOML. Derfor definerer vi `fraktal-ollama` som en egen
provider mot vår delte server i stedet for å bruke den innebygde.

## Bruk

**Fraktals Ollama-server** (krever VPN eller kontornett, treffer
`ml-dev-titan`):

```sh
fraktal "skriv en kort sammendrag av denne mappen"
```

**Azure OpenAI** (krever `fraktal-auth` på `PATH` og en gyldig pålogging):

```sh
fraktal-auth login          # engangs device-code-pålogging mot Entra
fraktal --profile azure "samme spørsmål, men mot Azure-modellen"
```

Codex' egne underkommandoer fungerer som vanlig — `fraktal --help`
viser hele listen (`exec`, `mcp`, `plugin`, `login`, m.fl.).

## Forholdet til oppstrøms

`main` følger `openai/codex` direkte; alle Fraktal-spesifikke commits
ligger på `fraktal/main` som en kort, dokumentert patch-serie. Vi
rebaser mot oppstrøms jevnlig — se [`RELEASING.md`](./RELEASING.md)
for runbook og prinsipper.

Hvis du finner en feil i oppstrøms-koden (alt utenfor `[fraktal]`-
commits), meld den til [openai/codex](https://github.com/openai/codex/issues).
Hvis det er noe Fraktal-spesifikt, åpne en issue her.

## Lisens

Apache-2.0, arvet fra oppstrøms. Se [`LICENSE`](./LICENSE).
