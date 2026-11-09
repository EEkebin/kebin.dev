# Sets up `claude-local` on Windows: Claude Code running on the kebin.dev model server instead of Anthropic's cloud.
# Your normal `claude` is left alone; claude-local keeps its own settings and history in ~\.claude-local.
# It only adds the profile: Claude Code itself has to be installed already (https://code.claude.com/docs).
#   Invoke-RestMethod https://kebin.dev/cli/claude-install.ps1 | Invoke-Expression
#   $env:AIBOX_KEY = "..."; Invoke-RestMethod https://kebin.dev/cli/claude-install.ps1 | Invoke-Expression    (non-interactive)
# Everything runs inside & { } so that, under `irm | iex`, nothing (error mode, variables, the key) is left behind in
# your session, and a failed check returns instead of closing your PowerShell window.
& {
$ErrorActionPreference = "Stop"
$Api = "https://ai.kebin.dev/v1"
$Search = "https://search.kebin.dev"
$EnvDir = Join-Path $HOME ".config\kebin"
$EnvFile = Join-Path $EnvDir "aibox.env"
$HomeDir = Join-Path $HOME ".claude-local"
$Bin = Join-Path $HOME ".local\bin"
$NoBom = New-Object System.Text.UTF8Encoding $false

function Say($m) { Write-Host $m -ForegroundColor Yellow }
function Add-ToUserPath($dir) {
    if (($env:Path -split ';') -contains $dir) { return }
    $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($UserPath -split ';') -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', "$dir;$UserPath", 'User') }
    $env:Path = "$dir;$env:Path"
}

Say "1/3  Claude Code"
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Host "Claude Code isn't installed. Install it first (https://code.claude.com/docs), then rerun this script."; return }
Write-Host "found: $(claude --version 2>$null | Select-Object -First 1)"

Say "2/3  API key"
$Key = $env:AIBOX_KEY
if (-not $Key) { $Key = Read-Host "Paste the ai.kebin.dev API key" }
if (-not $Key) { Write-Host "no key given"; return }
try { Invoke-WebRequest -UseBasicParsing -Headers @{ Authorization = "Bearer $Key" } "$Api/models" | Out-Null; Write-Host "key accepted" }
catch { Write-Host "key rejected by $Api"; return }

Say "3/3  claude-local"
New-Item -ItemType Directory -Force -Path $EnvDir, $HomeDir, $Bin | Out-Null
[IO.File]::WriteAllText($EnvFile, "AIBOX_KEY=$Key`r`n", $NoBom)
# Anthropic's hosted web search doesn't exist on a local model; search goes through search.kebin.dev instead
$Settings = Join-Path $HomeDir "settings.json"
if (-not (Test-Path $Settings)) { [IO.File]::WriteAllText($Settings, "{`n  `"permissions`": { `"deny`": [`"WebSearch`"] }`n}`n", $NoBom) }
$ErrorActionPreference = "Continue"
$PrevConfigDir = $env:CLAUDE_CONFIG_DIR
$env:CLAUDE_CONFIG_DIR = $HomeDir
& claude mcp remove -s user searxng *> $null
& claude mcp add --transport http -s user searxng "$Search/mcp" --header "Authorization: Bearer $Key" *> $null
if ($LASTEXITCODE -eq 0) { Write-Host "web search (searxng) added" } else { Write-Host "warning: couldn't add the web search tool; claude-local still works without it" }
if ($PrevConfigDir) { $env:CLAUDE_CONFIG_DIR = $PrevConfigDir } else { Remove-Item Env:\CLAUDE_CONFIG_DIR }
$ErrorActionPreference = "Stop"
$Launcher = @'
@echo off
rem kebin.dev: Claude Code on the model server at ai.kebin.dev. Settings and history live in %USERPROFILE%\.claude-local.
setlocal
for /f "usebackq tokens=1,* delims==" %%a in ("%USERPROFILE%\.config\kebin\aibox.env") do set "%%a=%%b"
set "ANTHROPIC_API_KEY="
set "CLAUDE_CODE_USE_BEDROCK="
set "CLAUDE_CODE_USE_VERTEX="
set "CLAUDE_CODE_USE_FOUNDRY="
set "ANTHROPIC_BASE_URL=https://ai.kebin.dev"
set "ANTHROPIC_AUTH_TOKEN=%AIBOX_KEY%"
set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-local"
set "ANTHROPIC_MODEL=qwen3.8-27b"
set "ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3.8-27b"
set "ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3.8-27b"
set "ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.8-27b"
set "CLAUDE_CODE_MAX_CONTEXT_TOKENS=262144"
set "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
claude %*
'@
[IO.File]::WriteAllText((Join-Path $Bin "claude-local.cmd"), ($Launcher -replace "`r?`n", "`r`n"), $NoBom)
Add-ToUserPath $Bin
Write-Host ""
Say "done. open a project folder and run:  claude-local"
Write-Host "Uses qwen3.8-27b on ai.kebin.dev with web search. Your normal 'claude' still uses Anthropic. Open a new terminal if 'claude-local' isn't found yet."
}
