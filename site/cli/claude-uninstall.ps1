# Removes what claude-install.ps1 set up. Your normal `claude` settings in ~\.claude are never touched.
#   Invoke-RestMethod https://kebin.dev/cli/claude-uninstall.ps1 | Invoke-Expression                                 # remove claude-local and its settings/history
#   $env:AIBOX_UNINSTALL_ALL = "1"; Invoke-RestMethod https://kebin.dev/cli/claude-uninstall.ps1 | Invoke-Expression  # also remove Claude Code itself
$ErrorActionPreference = "Stop"
$All = $env:AIBOX_UNINSTALL_ALL -eq "1"
$Bin = Join-Path $HOME ".local\bin"
$EnvDir = Join-Path $HOME ".config\kebin"
function Say($m) { Write-Host $m -ForegroundColor Yellow }

Say "1/2  claude-local"
foreach ($p in @((Join-Path $Bin "claude-local.cmd"), (Join-Path $HOME ".claude-local"))) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
# the key file is shared with codex-local; keep it while that is still installed
if (-not (Test-Path (Join-Path $Bin "codex-local.cmd"))) { Remove-Item -Force (Join-Path $EnvDir "aibox.env") -ErrorAction SilentlyContinue }
if ((Test-Path $EnvDir) -and -not (Get-ChildItem $EnvDir)) { Remove-Item $EnvDir }
Write-Host "removed claude-local, its settings and history"

Say "2/2  Claude Code itself"
if ($All) {
    foreach ($p in @((Join-Path $Bin "claude.exe"), (Join-Path $HOME ".local\share\claude"))) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
    if (Get-Command npm -ErrorAction SilentlyContinue) { try { npm uninstall -g @anthropic-ai/claude-code 2>$null | Out-Null } catch {} }
    $left = Get-Command claude -ErrorAction SilentlyContinue
    if ($left) { Write-Host "Claude Code is still at $($left.Source); remove that by hand" } else { Write-Host "Claude Code removed (your ~\.claude settings were kept)" }
} else {
    Write-Host 'left installed. Set $env:AIBOX_UNINSTALL_ALL = "1" and run again to remove Claude Code too (that also removes your normal "claude").'
}
Say "done"
