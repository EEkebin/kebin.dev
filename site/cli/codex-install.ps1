# Sets up `codex-local` on Windows: Codex running on the kebin.dev model server instead of OpenAI's cloud.
# Your normal `codex` is left alone; codex-local keeps its own settings and history in ~\.codex-local.
# It only adds the profile: Codex itself has to be installed already (https://developers.openai.com/codex).
#   Invoke-RestMethod https://kebin.dev/cli/codex-install.ps1 | Invoke-Expression
#   $env:AIBOX_KEY = "..."; Invoke-RestMethod https://kebin.dev/cli/codex-install.ps1 | Invoke-Expression    (non-interactive)
# Everything runs inside & { } so that, under `irm | iex`, nothing (error mode, variables, the key) is left behind in
# your session, and a failed check returns instead of closing your PowerShell window.
& {
$ErrorActionPreference = "Stop"
$Api = "https://ai.kebin.dev/v1"
$EnvDir = Join-Path $HOME ".config\kebin"
$EnvFile = Join-Path $EnvDir "aibox.env"
$HomeDir = Join-Path $HOME ".codex-local"
$Bin = Join-Path $HOME ".local\bin"
$NoBom = New-Object System.Text.UTF8Encoding $false

function Say($m) { Write-Host $m -ForegroundColor Yellow }
function Add-ToUserPath($dir) {
    if (($env:Path -split ';') -contains $dir) { return }
    $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($UserPath -split ';') -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', "$dir;$UserPath", 'User') }
    $env:Path = "$dir;$env:Path"
}

Say "1/3  Codex"
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { Write-Host "Codex isn't installed. Install it first (https://developers.openai.com/codex), then rerun this script."; return }
Write-Host "found: $(codex --version 2>$null | Select-Object -First 1)"

Say "2/3  API key"
$Key = $env:AIBOX_KEY
if (-not $Key) { $Key = Read-Host "Paste the ai.kebin.dev API key" }
if (-not $Key) { Write-Host "no key given"; return }
try { Invoke-WebRequest -UseBasicParsing -Headers @{ Authorization = "Bearer $Key" } "$Api/models" | Out-Null; Write-Host "key accepted" }
catch { Write-Host "key rejected by $Api"; return }

Say "3/3  codex-local"
New-Item -ItemType Directory -Force -Path $EnvDir, $HomeDir, $Bin | Out-Null
[IO.File]::WriteAllText($EnvFile, "AIBOX_KEY=$Key`r`n", $NoBom)
$Toml = Join-Path $HomeDir "config.toml"
$Config = @"
# kebin.dev: written by codex-install.ps1
model = "qwen3.8-27b"
model_provider = "aibox"
model_context_window = 262144

[model_providers.aibox]
name = "kebin.dev (ai.kebin.dev)"
base_url = "$Api"
env_key = "AIBOX_KEY"
wire_api = "responses"

# Codex's Windows sandbox; without it a fresh CODEX_HOME runs every command read-only. First use may ask for admin once.
[windows]
sandbox = "elevated"
"@
[IO.File]::WriteAllText($Toml, $Config, $NoBom)
$Launcher = @'
@echo off
rem kebin.dev: Codex on the model server at ai.kebin.dev. Settings and history live in %USERPROFILE%\.codex-local.
setlocal
for /f "usebackq tokens=1,* delims==" %%a in ("%USERPROFILE%\.config\kebin\aibox.env") do set "%%a=%%b"
set "CODEX_HOME=%USERPROFILE%\.codex-local"
codex -m qwen3.8-27b %*
'@
[IO.File]::WriteAllText((Join-Path $Bin "codex-local.cmd"), ($Launcher -replace "`r?`n", "`r`n"), $NoBom)
Add-ToUserPath $Bin
Write-Host ""
Say "done. open a project folder and run:  codex-local"
Write-Host "Uses qwen3.8-27b on ai.kebin.dev. No web search here (Codex doesn't hand search tools to local models). Your normal 'codex' still uses OpenAI. Open a new terminal if 'codex-local' isn't found yet."
}
