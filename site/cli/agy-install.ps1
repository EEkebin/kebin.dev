# Sets up `agy-local` on Windows: Google's Antigravity CLI (agy) running on the kebin.dev model server instead of Google's cloud.
# Your normal `agy` is left alone; agy-local keeps its own settings and history in ~\.agy-local.
# It only adds the profile: the Antigravity CLI itself has to be installed already (https://antigravity.google/docs/install).
#   Invoke-RestMethod https://kebin.dev/cli/agy-install.ps1 | Invoke-Expression
#   $env:AIBOX_KEY = "..."; Invoke-RestMethod https://kebin.dev/cli/agy-install.ps1 | Invoke-Expression    (non-interactive)
# Everything runs inside & { } so that, under `irm | iex`, nothing (error mode, variables, the key) is left behind in
# your session, and a failed check returns instead of closing your PowerShell window.
# How: agy can use a custom Gemini-API endpoint; ai.kebin.dev/v1beta/ translates it for the model server and answers every
# model name with qwen3.8-27b. Web search comes from search.kebin.dev over MCP (agy's own search needs a Google login).
& {
$ErrorActionPreference = "Stop"
$Api = "https://ai.kebin.dev/v1"
$Base = "https://ai.kebin.dev"
$Search = "https://search.kebin.dev"
$EnvDir = Join-Path $HOME ".config\kebin"
$EnvFile = Join-Path $EnvDir "aibox.env"
$HomeDir = Join-Path $HOME ".agy-local"
$Bin = Join-Path $HOME ".local\bin"
$NoBom = New-Object System.Text.UTF8Encoding $false

function Say($m) { Write-Host $m -ForegroundColor Yellow }
function Add-ToUserPath($dir) {
    if (($env:Path -split ';') -contains $dir) { return }
    $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($UserPath -split ';') -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', "$dir;$UserPath", 'User') }
    $env:Path = "$dir;$env:Path"
}

Say "1/3  Antigravity CLI"
if (-not (Get-Command agy -ErrorAction SilentlyContinue)) { Write-Host "The Antigravity CLI (agy) isn't installed. Install it first (https://antigravity.google/docs/install), then rerun this script."; return }
Write-Host "found: agy $(agy --version 2>$null | Select-Object -First 1)"

Say "2/3  API key"
$Key = $env:AIBOX_KEY
if (-not $Key) { $Key = Read-Host "Paste the ai.kebin.dev API key" }
if (-not $Key) { Write-Host "no key given"; return }
try { Invoke-WebRequest -UseBasicParsing -Headers @{ Authorization = "Bearer $Key" } "$Api/models" | Out-Null; Write-Host "key accepted" }
catch { Write-Host "key rejected by $Api"; return }

Say "3/3  agy-local"
New-Item -ItemType Directory -Force -Path $EnvDir, (Join-Path $HomeDir "antigravity-cli"), $Bin | Out-Null
[IO.File]::WriteAllText($EnvFile, "AIBOX_KEY=$Key`r`n", $NoBom)
$Settings = Join-Path $HomeDir "antigravity-cli\settings.json"
if (-not (Test-Path $Settings)) { [IO.File]::WriteAllText($Settings, "{`n  `"modelProvider`": `"gemini`"`n}`n", $NoBom) }
$GeminiDir = "--gemini_dir=$HomeDir"
$ErrorActionPreference = "Continue"
agy $GeminiDir mcp add --header "Authorization: Bearer $Key" searxng "$Search/mcp" *> $null
if ($LASTEXITCODE -eq 0) { Write-Host "web search (searxng) added" } else { Write-Host "warning: couldn't add the web search tool; agy-local still works without it" }
# agy refuses model names it doesn't know, so use one of its own; the server answers it with qwen3.8-27b either way
$env:GOOGLE_GEMINI_BASE_URL = $Base; $env:GEMINI_API_KEY = $Key
$Model = (agy $GeminiDir models 2>$null | Where-Object { $_ -match '^\S+\s' } | Select-Object -First 1)
Remove-Item Env:GOOGLE_GEMINI_BASE_URL, Env:GEMINI_API_KEY
$ErrorActionPreference = "Stop"
if ($Model) { $Model = ($Model -split '\s+')[0] } else { $Model = "gemini-3.8-flash-high" }
$Launcher = @"
@echo off
rem kebin.dev: the Antigravity CLI on the model server at ai.kebin.dev. Settings and history live in %USERPROFILE%\.agy-local.
setlocal
for /f "usebackq tokens=1,* delims==" %%a in ("%USERPROFILE%\.config\kebin\aibox.env") do set "%%a=%%b"
set "GOOGLE_GEMINI_BASE_URL=$Base"
set "GEMINI_API_KEY=%AIBOX_KEY%"
for %%c in (mcp models plugin plugins update install changelog help agent agents acp remote-control mic-serve) do if /i "%~1"=="%%c" (agy "--gemini_dir=%USERPROFILE%\.agy-local" %* & exit /b)
agy "--gemini_dir=%USERPROFILE%\.agy-local" --model $Model %*
"@
[IO.File]::WriteAllText((Join-Path $Bin "agy-local.cmd"), ($Launcher -replace "`r?`n", "`r`n"), $NoBom)
Add-ToUserPath $Bin
Write-Host ""
Say "done. open a project folder and run:  agy-local"
Write-Host "Uses qwen3.8-27b on ai.kebin.dev with web search (agy shows it as '$Model'). Your normal 'agy' still uses Google. Open a new terminal if 'agy-local' isn't found yet."
}
