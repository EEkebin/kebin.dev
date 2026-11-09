# Removes what codex-install.ps1 set up: the codex-local profile only. Codex itself and your ~\.codex are never touched.
#   Invoke-RestMethod https://kebin.dev/cli/codex-uninstall.ps1 | Invoke-Expression
$ErrorActionPreference = "Stop"
$Bin = Join-Path $HOME ".local\bin"
$EnvDir = Join-Path $HOME ".config\kebin"
function Say($m) { Write-Host $m -ForegroundColor Yellow }

Say "codex-local"
foreach ($p in @((Join-Path $Bin "codex-local.cmd"), (Join-Path $HOME ".codex-local"))) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
# the key file is shared with claude-local; keep it while that is still installed
if (-not (Test-Path (Join-Path $Bin "claude-local.cmd"))) { Remove-Item -Force (Join-Path $EnvDir "aibox.env") -ErrorAction SilentlyContinue }
if ((Test-Path $EnvDir) -and -not (Get-ChildItem $EnvDir)) { Remove-Item $EnvDir }
Write-Host "removed codex-local, its settings and history. Codex itself and your normal 'codex' are untouched."
Say "done"
