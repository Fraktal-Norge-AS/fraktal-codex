#Requires -Version 5.1
<#
.SYNOPSIS
    Installs Fraktal CLI on Windows and configures it against OpenRouter.

.DESCRIPTION
    Downloads the latest published fraktal.exe, verifies its checksum, puts it
    on your PATH, stores an OpenRouter API key, and writes the provider
    configuration.

    It is safe to re-run. An existing ~/.fraktal/config.toml is never
    overwritten: the OpenRouter provider is appended only if missing, and your
    existing default model/provider is left alone. In that case the script
    writes an overlay profile instead, so OpenRouter is opt-in per run via
    `fraktal --profile openrouter`.

.PARAMETER ApiKey
    OpenRouter API key. Prompted for (without echo) when omitted.

.PARAMETER Model
    OpenRouter model slug. Note that `deepseek/deepseek-v4-flash` resolves to
    the older 0423 snapshot; the dated `-0731` slug is newer and cheaper.

.PARAMETER InstallDir
    Where fraktal.exe is placed. Defaults to %LOCALAPPDATA%\Programs\Fraktal.

.PARAMETER FraktalHome
    Configuration directory. Defaults to $env:FRAKTAL_HOME, else ~\.fraktal.

.PARAMETER DryRun
    Report every action without downloading, writing files, or touching the
    environment.

.EXAMPLE
    .\or-setup.ps1

.EXAMPLE
    .\or-setup.ps1 -Model "deepseek/deepseek-v4-pro" -DryRun
#>
[CmdletBinding()]
param(
    [string] $ApiKey,
    [string] $Model = 'deepseek/deepseek-v4-flash-0731',
    [string] $InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\Fraktal'),
    [string] $FraktalHome,
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo        = 'Fraktal-Norge-AS/fraktal-codex'
$AssetUrl    = "https://github.com/$Repo/releases/latest/download/fraktal.exe"
$ChecksumUrl = "$AssetUrl.sha256"
$ProviderId  = 'fraktal-openrouter'

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Skip { param([string] $Message) Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string] $Message) Write-Host "    $Message" -ForegroundColor Yellow }

if (-not $FraktalHome) {
    $FraktalHome = if ($env:FRAKTAL_HOME) { $env:FRAKTAL_HOME }
                   else { Join-Path $env:USERPROFILE '.fraktal' }
}

if ($DryRun) { Write-Warn 'DRY RUN — nothing will be downloaded, written, or changed.' }

# --- 1. API key -------------------------------------------------------------
Write-Step 'OpenRouter API key'

$keptExistingKey = $false

if (-not $ApiKey) {
    $existing = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', 'User')
    if ($existing) {
        # Never print the key; four characters is enough to recognise it.
        $tail = if ($existing.Length -ge 4) { $existing.Substring($existing.Length - 4) } else { '****' }
        $reply = Read-Host "    OPENROUTER_API_KEY is already set (ends ...$tail). Replace it? [y/N]"
        if ($reply -notmatch '^(y|yes)$') {
            $ApiKey = $existing
            $keptExistingKey = $true
        }
    }
}

if (-not $ApiKey) {
    Write-Host '    Create one at https://openrouter.ai/keys'
    # -AsSecureString keeps the key out of the console and shell history.
    $secure = Read-Host '    Paste your OpenRouter API key' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try     { $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$ApiKey = $ApiKey.Trim()
if (-not $ApiKey) { throw 'No API key provided.' }
if ($ApiKey -notmatch '^sk-or-') {
    Write-Warn "Key does not start with 'sk-or-'. Continuing, but double-check it."
}

if ($keptExistingKey) {
    # Already stored for this user; only the current session needs it.
    if (-not $DryRun) { $env:OPENROUTER_API_KEY = $ApiKey }
    Write-Skip 'Keeping the existing key; OPENROUTER_API_KEY left unchanged.'
} elseif ($DryRun) {
    Write-Skip 'Would set OPENROUTER_API_KEY for the current user.'
} else {
    [Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY', $ApiKey, 'User')
    $env:OPENROUTER_API_KEY = $ApiKey   # so the verification step below works now
    Write-Ok 'Stored OPENROUTER_API_KEY for the current user.'
}

# --- 2. Download ------------------------------------------------------------
Write-Step "Download fraktal.exe -> $InstallDir"

$exePath = Join-Path $InstallDir 'fraktal.exe'

if ($DryRun) {
    Write-Skip "Would download $AssetUrl"
    Write-Skip "Would verify against $ChecksumUrl"
} else {
    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("fraktal-" + [Guid]::NewGuid().ToString('N') + '.exe')
    try {
        try {
            Invoke-WebRequest -Uri $AssetUrl -OutFile $tmp -UseBasicParsing
        } catch {
            throw ("Could not download the binary from $AssetUrl`n" +
                   "    If no release has been published yet, check " +
                   "https://github.com/$Repo/releases`n    Underlying error: $($_.Exception.Message)")
        }

        # Checksum is published beside the binary; treat a missing one as a
        # warning rather than a hard failure so an older release still installs.
        #
        # Read it via a file rather than Invoke-WebRequest's .Content: for a
        # response PowerShell does not consider text, .Content is a Byte[], and
        # `-split` over a Byte[] yields the first *byte* (53, i.e. ASCII '5')
        # instead of the hash — a mismatch against a download that was fine.
        $expected = $null
        $tmpSum = "$tmp.sha256"
        try {
            Invoke-WebRequest -Uri $ChecksumUrl -OutFile $tmpSum -UseBasicParsing
            $expected = ((Get-Content -Path $tmpSum -Raw) -split '\s+' |
                         Where-Object { $_ })[0].ToLower()
        } catch {
            Write-Warn 'No published checksum found; skipping verification.'
        } finally {
            if (Test-Path $tmpSum) { Remove-Item $tmpSum -Force -ErrorAction SilentlyContinue }
        }

        # Anything that is not a SHA-256 digest means we failed to parse, not
        # that the download is bad. Say so instead of reporting a mismatch.
        if ($expected -and $expected -notmatch '^[0-9a-f]{64}$') {
            Write-Warn "Could not parse the published checksum ('$expected'); skipping verification."
            $expected = $null
        }

        if ($expected) {
            $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLower()
            if ($actual -ne $expected) {
                throw "Checksum mismatch.`n    expected $expected`n    actual   $actual"
            }
            Write-Ok "Checksum verified ($($expected.Substring(0,16))...)."
        }

        Move-Item -Path $tmp -Destination $exePath -Force
        Write-Ok "Installed $exePath"
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# --- 3. PATH ----------------------------------------------------------------
Write-Step 'PATH'

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
$onPath = ($userPath -split ';' | Where-Object { $_ } |
           ForEach-Object { $_.TrimEnd('\') }) -contains $InstallDir.TrimEnd('\')

if ($onPath) {
    Write-Skip 'Already on PATH.'
} elseif ($DryRun) {
    Write-Skip "Would append $InstallDir to the user PATH."
} else {
    $joined = if ($userPath.TrimEnd(';')) { $userPath.TrimEnd(';') + ';' + $InstallDir } else { $InstallDir }
    [Environment]::SetEnvironmentVariable('Path', $joined, 'User')
    $env:Path = "$env:Path;$InstallDir"   # current session
    Write-Ok "Added to PATH. Open a new terminal for other sessions to see it."
}

# --- 4. Configuration -------------------------------------------------------
Write-Step "Configuration in $FraktalHome"

$providerBlock = @"
[model_providers.$ProviderId]
name = "OpenRouter"
base_url = "https://openrouter.ai/api/v1"
wire_api = "chat"                    # [fraktal] direkte Chat Completions
requires_openai_auth = false
env_key = "OPENROUTER_API_KEY"
discover_models = true               # vis OpenRouters modeller i /model
"@

$configPath  = Join-Path $FraktalHome 'config.toml'
$profilePath = Join-Path $FraktalHome 'openrouter.config.toml'
$usedProfile = $false

if (-not $DryRun -and -not (Test-Path $FraktalHome)) {
    New-Item -ItemType Directory -Force -Path $FraktalHome | Out-Null
}

if (-not (Test-Path $configPath)) {
    # Nothing here yet, so OpenRouter can safely become the default.
    $fresh = @"
model_provider = "$ProviderId"
model = "$Model"

$providerBlock
"@
    if ($DryRun) { Write-Skip "Would create $configPath with OpenRouter as the default." }
    else {
        Set-Content -Path $configPath -Value $fresh -Encoding UTF8
        Write-Ok "Created $configPath (OpenRouter is the default provider)."
    }
} else {
    # An existing config may point at Ollama or Azure. Changing its default
    # would hijack a working setup, so add OpenRouter as an opt-in profile.
    $usedProfile = $true
    $existingConfig = Get-Content -Path $configPath -Raw

    if ($existingConfig -match [regex]::Escape("[model_providers.$ProviderId]")) {
        Write-Skip "Provider [model_providers.$ProviderId] already present; left untouched."
    } elseif ($DryRun) {
        Write-Skip "Would back up $configPath and append [model_providers.$ProviderId]."
    } else {
        $backup = "$configPath.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Copy-Item -Path $configPath -Destination $backup
        Add-Content -Path $configPath -Value "`r`n$providerBlock"
        Write-Ok "Appended the provider (backup: $(Split-Path -Leaf $backup))."
    }

    $profileBody = @"
model_provider = "$ProviderId"
model = "$Model"
"@
    if ($DryRun) { Write-Skip "Would write profile overlay $profilePath." }
    else {
        Set-Content -Path $profilePath -Value $profileBody -Encoding UTF8
        Write-Ok "Wrote profile overlay $(Split-Path -Leaf $profilePath)."
    }
}

# --- 5. Verify --------------------------------------------------------------
Write-Step 'Verify'

if ($DryRun) {
    Write-Skip 'Would run: fraktal --version'
} elseif (Test-Path $exePath) {
    $version = (& $exePath --version) 2>&1
    Write-Ok "$version"

    # We append to PATH, so an earlier entry — a cargo-installed build, say —
    # keeps winning and the freshly downloaded binary is never the one that
    # runs. Silent shadowing is worse than a warning.
    $resolved = Get-Command fraktal -ErrorAction SilentlyContinue
    if ($resolved -and $resolved.Source -and
        ($resolved.Source.TrimEnd('\') -ne $exePath.TrimEnd('\'))) {
        Write-Warn "Another fraktal is earlier on PATH and will be used instead:"
        Write-Warn "  $($resolved.Source)"
        Write-Warn "Remove it, reorder PATH, or run $exePath directly."
    }
} else {
    Write-Warn 'fraktal.exe not found; skipping.'
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
if ($usedProfile) {
    Write-Host "  You already had a config, so OpenRouter was added as a profile:" -ForegroundColor Yellow
    Write-Host "    fraktal --profile openrouter `"hva gjor dette repoet?`""
    Write-Host "  Your existing default provider was left unchanged."
} else {
    Write-Host "    fraktal                                # interactive"
    Write-Host "    fraktal exec `"hva gjor dette repoet?`"  # one-shot"
}
Write-Host "  Model: $Model"
