# Installs the OpenCode CLI on Windows and points it at the kebin.dev model server.
#   Invoke-RestMethod https://kebin.dev/cli/install.ps1 | Invoke-Expression
#   $env:AIBOX_KEY = "..."; Invoke-RestMethod https://kebin.dev/cli/install.ps1 | Invoke-Expression    (non-interactive)
# Everything runs inside & { } so that, under `irm | iex`, nothing (error mode, variables, the key) is left behind in
# your session, and a failed check returns instead of closing your PowerShell window.
& {
$ErrorActionPreference = "Stop"
$Api = "https://ai.kebin.dev/v1"
$Search = "https://search.kebin.dev"
$CfgDir = Join-Path $HOME ".config\opencode"
$Cfg = Join-Path $CfgDir "opencode.json"

function Say($m) { Write-Host $m -ForegroundColor Yellow }

Say "1/3  OpenCode"
# OpenCode 1 and 2 share the `opencode` command, and Scoop and Chocolatey only carry 1.x, so any package-managed 1.x has to go first.
$OcVer = $null
if (Get-Command opencode -ErrorAction SilentlyContinue) {
    $m = [regex]::Match((opencode --version 2>$null | Select-Object -First 1), '\d+\.\d+\.\d+')
    if ($m.Success) { $OcVer = $m.Value }
}
if ($OcVer -and [int]($OcVer.Split('.')[0]) -ge 2) {
    Write-Host "already installed: OpenCode $OcVer"
} else {
    if ($OcVer) {
        Write-Host "replacing OpenCode $OcVer with OpenCode 2"
        if (Get-Command npm -ErrorAction SilentlyContinue) { try { npm uninstall -g opencode-ai 2>$null | Out-Null } catch {} }
        if (Get-Command scoop -ErrorAction SilentlyContinue) { try { scoop uninstall opencode 2>$null | Out-Null } catch {} }
        if (Get-Command choco -ErrorAction SilentlyContinue) { try { choco uninstall -y opencode 2>$null | Out-Null } catch {} }
    }
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm install -g @opencode/cli
    } else {
        # no npm: the standalone binary from the release, into ~/.opencode/bin on the user's PATH
        $Ver = (Invoke-RestMethod https://registry.npmjs.org/@opencode/cli/latest).version
        $Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $Bin = Join-Path $HOME ".opencode\bin"
        New-Item -ItemType Directory -Force -Path $Bin | Out-Null
        $Zip = Join-Path $env:TEMP "opencode-$Ver.zip"
        Invoke-WebRequest -UseBasicParsing "https://github.com/anomalyco/opencode/releases/download/v$Ver/opencode-windows-$Arch.zip" -OutFile $Zip
        Expand-Archive -Force $Zip $Bin
        Remove-Item $Zip
        $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($UserPath -notlike "*$Bin*") { [Environment]::SetEnvironmentVariable('Path', "$Bin;$UserPath", 'User') }
        $env:Path = "$Bin;$env:Path"
    }
}
if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    Write-Host "OpenCode didn't install. Grab the Windows binary from https://github.com/anomalyco/opencode/releases, put it on your PATH, then rerun."
    return
}

Say "2/3  API key"
$Key = $env:AIBOX_KEY
if (-not $Key) { $Key = Read-Host "Paste the ai.kebin.dev API key" }
if (-not $Key) { Write-Host "no key given" -ForegroundColor Red; return }
try { Invoke-WebRequest -Uri "$Api/models" -Headers @{ Authorization = "Bearer $Key" } -UseBasicParsing | Out-Null; Write-Host "key accepted" }
catch { Write-Host "key rejected by $Api" -ForegroundColor Red; return }
try { Invoke-WebRequest -Uri "$Search/health" -Headers @{ Authorization = "Bearer $Key" } -UseBasicParsing | Out-Null; Write-Host "web search reachable" }
catch { Write-Host "warning: $Search not reachable, web search may not work right now" -ForegroundColor DarkYellow }

Say "3/3  config -> $Cfg"
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
if (Test-Path $Cfg) { Copy-Item $Cfg "$Cfg.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" }
$json = @{
    '$schema' = "https://opencode.ai/config.json"
    model = "aibox/qwen3.8-27b"
    provider = @{ aibox = @{
        npm = "@ai-sdk/openai-compatible"
        name = "kebin.dev (ai.kebin.dev)"
        options = @{ baseURL = $Api; apiKey = $Key }
        models = @{
            'qwen3.8-27b' = @{ name = "Qwen3.8 27B (vision, 262K)"; attachment = $true; modalities = @{ input = @("text","image"); output = @("text") }; limit = @{ context = 262144; output = 32768 } }
        }
    } }
    mcp = @{ searxng = @{
        type = "remote"
        url = "$Search/mcp"
        headers = @{ Authorization = "Bearer $Key" }
        oauth = $false
        enabled = $true
        timeout = 60000
    } }
    permission = @{ webfetch = "allow"; websearch = "deny"; 'searxng_*' = "allow"; external_directory = "ask" }
}
$json | ConvertTo-Json -Depth 8 | Set-Content -Path $Cfg -Encoding utf8
Write-Host ""
Say "done. open a project folder and run:  opencode"
Write-Host "switch models inside OpenCode with /models. Web search (searxng_web_search) and page fetch are on. Re-run this script any time to update."
}
