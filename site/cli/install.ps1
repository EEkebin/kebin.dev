# Installs the OpenCode CLI on Windows and points it at the kebin.dev model server.
#   irm https://kebin.dev/cli/install.ps1 | iex
#   $env:AIBOX_KEY = "..."; irm https://kebin.dev/cli/install.ps1 | iex    (non-interactive)
$ErrorActionPreference = "Stop"
$Api = "https://ai.kebin.dev/v1"
$CfgDir = Join-Path $HOME ".config\opencode"
$Cfg = Join-Path $CfgDir "opencode.json"

function Say($m) { Write-Host $m -ForegroundColor Yellow }

Say "1/3  OpenCode"
if (Get-Command opencode -ErrorAction SilentlyContinue) {
    Write-Host "already installed: $(opencode --version 2>$null | Select-Object -First 1)"
} elseif (Get-Command npm -ErrorAction SilentlyContinue) {
    npm install -g opencode-ai
} elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
    scoop install opencode
} elseif (Get-Command choco -ErrorAction SilentlyContinue) {
    choco install -y opencode
} else {
    Write-Host "No npm, scoop or choco found. Install Node.js from https://nodejs.org then rerun, or grab the Windows binary from https://github.com/anomalyco/opencode/releases" -ForegroundColor Red
    exit 1
}

Say "2/3  API key"
$Key = $env:AIBOX_KEY
if (-not $Key) { $Key = Read-Host "Paste the ai.kebin.dev API key" }
if (-not $Key) { Write-Host "no key given" -ForegroundColor Red; exit 1 }
try { Invoke-WebRequest -Uri "$Api/models" -Headers @{ Authorization = "Bearer $Key" } -UseBasicParsing | Out-Null; Write-Host "key accepted" }
catch { Write-Host "key rejected by $Api" -ForegroundColor Red; exit 1 }

Say "3/3  config -> $Cfg"
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
if (Test-Path $Cfg) { Copy-Item $Cfg "$Cfg.bak.$([int](Get-Date -UFormat %s))" }
$json = @{
    '$schema' = "https://opencode.ai/config.json"
    model = "aibox/qwen3.5-9b"
    provider = @{ aibox = @{
        npm = "@ai-sdk/openai-compatible"
        name = "kebin.dev (ai.kebin.dev)"
        options = @{ baseURL = $Api; apiKey = $Key }
        models = @{
            'qwen3.5-9b' = @{ name = "Qwen3.5 9B (vision, 128K)"; attachment = $true; modalities = @{ input = @("text","image"); output = @("text") }; limit = @{ context = 131072; output = 16384 } }
            'qwen3.8-27b' = @{ name = "Qwen3.8 27B (vision, 32K)"; attachment = $true; modalities = @{ input = @("text","image"); output = @("text") }; limit = @{ context = 32768; output = 8192 } }
        }
    } }
    lsp = $true
}
$json | ConvertTo-Json -Depth 8 | Set-Content -Path $Cfg -Encoding utf8
Write-Host ""
Say "done. open a project folder and run:  opencode"
Write-Host "switch models inside OpenCode with /models. Re-run this script any time to update."
