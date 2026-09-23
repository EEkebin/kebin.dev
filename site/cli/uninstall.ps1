# Removes what install.ps1 set up.
#   Invoke-RestMethod https://kebin.dev/cli/uninstall.ps1 | Invoke-Expression                       # remove the kebin.dev profile only
#   $env:AIBOX_UNINSTALL_ALL = "1"; Invoke-RestMethod https://kebin.dev/cli/uninstall.ps1 | Invoke-Expression   # also remove OpenCode itself
$ErrorActionPreference = "Stop"
$CfgDir = Join-Path $HOME ".config\opencode"
$Cfg = Join-Path $CfgDir "opencode.json"
$All = $env:AIBOX_UNINSTALL_ALL -eq "1"
function Say($m) { Write-Host $m -ForegroundColor Yellow }

Say "1/2  kebin.dev profile"
if (Test-Path $Cfg) {
    $bak = Get-ChildItem "$Cfg.bak.*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($bak) {
        Move-Item -Force $bak.FullName $Cfg
        Get-ChildItem "$Cfg.bak.*" -ErrorAction SilentlyContinue | Remove-Item -Force
        Write-Host "restored your previous config from $($bak.Name)"
    } else {
        $d = Get-Content $Cfg -Raw | ConvertFrom-Json
        $hit = $false
        if ($d.provider -and $d.provider.PSObject.Properties.Name -contains "aibox") {
            $hit = $true
            $d.provider.PSObject.Properties.Remove("aibox")
            if ("$($d.model)".StartsWith("aibox/")) { $d.PSObject.Properties.Remove("model") }
            if ($d.provider.PSObject.Properties.Count -eq 0) { $d.PSObject.Properties.Remove("provider") }
        }
        if ($d.mcp -and $d.mcp.PSObject.Properties.Name -contains "searxng") {
            $hit = $true
            $d.mcp.PSObject.Properties.Remove("searxng")
            if ($d.mcp.PSObject.Properties.Count -eq 0) { $d.PSObject.Properties.Remove("mcp") }
        }
        if ($d.permission) {
            foreach ($k in @("searxng_*", "webfetch", "websearch")) {
                if ($d.permission.PSObject.Properties.Name -contains $k) { $hit = $true; $d.permission.PSObject.Properties.Remove($k) }
            }
            if ($d.permission.PSObject.Properties.Count -eq 0) { $d.PSObject.Properties.Remove("permission") }
        }
        if ($hit) {
            $d | ConvertTo-Json -Depth 8 | Set-Content -Path $Cfg -Encoding utf8
            Write-Host "removed the kebin.dev provider and search tool from $Cfg"
        } else { Write-Host "no kebin.dev profile found in $Cfg, left untouched" }
    }
} else { Write-Host "no OpenCode config found" }

Say "2/2  OpenCode itself"
if ($All) {
    if (Get-Command npm -ErrorAction SilentlyContinue) { try { npm uninstall -g opencode-ai 2>$null | Out-Null } catch {} }
    if (Get-Command scoop -ErrorAction SilentlyContinue) { try { scoop uninstall opencode 2>$null | Out-Null } catch {} }
    if (Get-Command choco -ErrorAction SilentlyContinue) { try { choco uninstall -y opencode 2>$null | Out-Null } catch {} }
    foreach ($p in @((Join-Path $HOME ".opencode"), (Join-Path $HOME ".local\share\opencode"), (Join-Path $HOME ".cache\opencode"), $CfgDir)) {
        if (Test-Path $p) { Remove-Item -Recurse -Force $p }
    }
    Write-Host "OpenCode removed (binary, data, cache, config)"
} else {
    Write-Host 'left installed. Set $env:AIBOX_UNINSTALL_ALL = "1" and run again to remove OpenCode too.'
}
Say "done"
