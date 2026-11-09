# Removes what claude-install.ps1 set up: the claude-local profile only. Claude Code itself and your ~\.claude are never touched.
#   Invoke-RestMethod https://kebin.dev/cli/claude-uninstall.ps1 | Invoke-Expression
$ErrorActionPreference = "Stop"
$Bin = Join-Path $HOME ".local\bin"
$EnvDir = Join-Path $HOME ".config\kebin"
function Say($m) { Write-Host $m -ForegroundColor Yellow }

Say "claude-local"
foreach ($p in @((Join-Path $Bin "claude-local.cmd"), (Join-Path $HOME ".claude-local"))) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
# the key file is shared with codex-local; keep it while that is still installed
if (-not (Test-Path (Join-Path $Bin "codex-local.cmd"))) { Remove-Item -Force (Join-Path $EnvDir "aibox.env") -ErrorAction SilentlyContinue }
if ((Test-Path $EnvDir) -and -not (Get-ChildItem $EnvDir)) { Remove-Item $EnvDir }
Write-Host "removed claude-local, its settings and history. Claude Code itself and your normal 'claude' are untouched."
Say "done"
