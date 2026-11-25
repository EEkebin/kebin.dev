# Removes what agy-install.ps1 set up: the agy-local profile only. The Antigravity CLI itself and your ~\.gemini are never touched.
#   Invoke-RestMethod https://kebin.dev/cli/agy-uninstall.ps1 | Invoke-Expression
# Everything runs inside & { } so that, under `irm | iex`, nothing (error mode, variables, the key) is left behind in
# your session, and a failed check returns instead of closing your PowerShell window.
& {
$ErrorActionPreference = "Stop"
$Bin = Join-Path $HOME ".local\bin"
$EnvDir = Join-Path $HOME ".config\kebin"
function Say($m) { Write-Host $m -ForegroundColor Yellow }

Say "agy-local"
foreach ($p in @((Join-Path $Bin "agy-local.cmd"), (Join-Path $HOME ".agy-local"))) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
# the key file is shared with claude-local and codex-local; keep it while either is still installed
if (-not ((Test-Path (Join-Path $Bin "claude-local.cmd")) -or (Test-Path (Join-Path $Bin "codex-local.cmd")))) { Remove-Item -Force (Join-Path $EnvDir "aibox.env") -ErrorAction SilentlyContinue }
if ((Test-Path $EnvDir) -and -not (Get-ChildItem $EnvDir)) { Remove-Item $EnvDir }
Write-Host "removed agy-local, its settings and history. The Antigravity CLI and your normal 'agy' are untouched."
Say "done"
}
