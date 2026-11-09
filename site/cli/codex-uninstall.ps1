# Removes what codex-install.ps1 set up. Your normal `codex` settings in ~\.codex are never touched.
#   Invoke-RestMethod https://kebin.dev/cli/codex-uninstall.ps1 | Invoke-Expression                                 # remove codex-local and its settings/history
#   $env:AIBOX_UNINSTALL_ALL = "1"; Invoke-RestMethod https://kebin.dev/cli/codex-uninstall.ps1 | Invoke-Expression  # also remove Codex itself
$ErrorActionPreference = "Stop"
$All = $env:AIBOX_UNINSTALL_ALL -eq "1"
$Bin = Join-Path $HOME ".local\bin"
$EnvDir = Join-Path $HOME ".config\kebin"
function Say($m) { Write-Host $m -ForegroundColor Yellow }

Say "1/2  codex-local"
foreach ($p in @((Join-Path $Bin "codex-local.cmd"), (Join-Path $HOME ".codex-local"))) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
# the key file is shared with claude-local; keep it while that is still installed
if (-not (Test-Path (Join-Path $Bin "claude-local.cmd"))) { Remove-Item -Force (Join-Path $EnvDir "aibox.env") -ErrorAction SilentlyContinue }
if ((Test-Path $EnvDir) -and -not (Get-ChildItem $EnvDir)) { Remove-Item $EnvDir }
Write-Host "removed codex-local, its settings and history"

Say "2/2  Codex itself"
if ($All) {
    if (Get-Command npm -ErrorAction SilentlyContinue) { try { npm uninstall -g @openai/codex 2>$null | Out-Null } catch {} }
    $left = Get-Command codex -ErrorAction SilentlyContinue
    if ($left) { Write-Host "Codex is still at $($left.Source); remove that by hand" } else { Write-Host "Codex removed (your ~\.codex settings were kept)" }
} else {
    Write-Host 'left installed. Set $env:AIBOX_UNINSTALL_ALL = "1" and run again to remove Codex too (that also removes your normal "codex").'
}
Say "done"
