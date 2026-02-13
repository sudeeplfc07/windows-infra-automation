<#
  Copyright (c) 2026 Sudeep Gyawali
  Licensed under the MIT License. See the LICENSE file in the repository root.
#>
# InstallApp.ps1  (Create Browser Link shortcuts with persistent icon)
# Creates Start Menu and Public Desktop shortcuts that open a URL in Edge (app window or new window).
# Falls back to default browser via explorer.exe if Edge isn't found unless -StrictEdge is set.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$IconLocation, # incoming icon path (staging)
    [switch]$UseAppWindow,
    [switch]$StrictEdge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Logging / transcript ---
$logDir  = Join-Path $env:ProgramData 'GenericApp'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ('InstallApp_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
Start-Transcript -Path $logFile -Append | Out-Null

function Get-EdgePath {
    $cmd = Get-Command 'msedge.exe' -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) { return $cmd.Source }

    $appPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppPaths\msedge.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\AppPaths\msedge.exe'
    )
    foreach ($ap in $appPaths) {
        if (Test-Path $ap) {
            $candidate = (Get-ItemProperty -Path $ap -ErrorAction SilentlyContinue).'(Default)'
            if ($candidate -and (Test-Path $candidate)) { return $candidate }
        }
    }

    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($r in $roots) {
        if (Test-Path $r) {
            Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $p  = Get-ItemProperty -Path $_.PsPath -ErrorAction Stop
                    $dn = '' + $p.DisplayName
                    if ($dn -and ($dn -match '^(?i)Microsoft Edge(?!.*WebView)')) {
                        if ($p.InstallLocation) {
                            $exe = Join-Path $p.InstallLocation 'msedge.exe'
                            if (Test-Path $exe) { return $exe }
                        }
                        if ($p.DisplayIcon) {
                            $candidate = ($p.DisplayIcon -replace ',\d+$','')
                            if ((Split-Path -Leaf $candidate) -ieq 'msedge.exe' -and (Test-Path $candidate)) { return $candidate }
                        }
                    }
                } catch {}
            }
        }
    }

    foreach ($c in @("$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                     "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe")) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function New-ShortcutLnk {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetExe,
        [string]$Arguments = "",
        [string]$IconLocation = ""
    )
    $dir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $dir)) {
        if ($PSCmdlet.ShouldProcess($dir, "Create directory")) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess($ShortcutPath, "Create .lnk")) {
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut([string]$ShortcutPath)
        $sc.TargetPath = [string]$TargetExe
        if ($Arguments) { $sc.Arguments = [string]$Arguments }
        if ($IconLocation -and (Test-Path $IconLocation)) { $sc.IconLocation = [string]$IconLocation }
        $sc.WindowStyle = 1
        $sc.Save()
    }
}

function New-ShortcutUrl {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPathUrl, # ends with .url
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$IconLocation = ""
    )
    $dir = Split-Path -Parent $ShortcutPathUrl
    if (-not (Test-Path $dir)) {
        if ($PSCmdlet.ShouldProcess($dir, "Create directory")) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess($ShortcutPathUrl, "Create .url")) {
        $content = @("[InternetShortcut]","URL=$Url")
        if ($IconLocation -and (Test-Path $IconLocation)) {
            $content += "IconFile=$IconLocation"
            $content += "IconIndex=0"
        }
        Set-Content -Path $ShortcutPathUrl -Value $content -Encoding ASCII -Force
    }
}

# --- Persist icon to ProgramData so it survives IME cache cleanup ---
$persistIcon = Join-Path $logDir 'GenericApp.ico'
try {
    if (Test-Path $IconLocation) {
        Copy-Item -Path $IconLocation -Destination $persistIcon -Force
        $IconLocation = $persistIcon
    } elseif (Test-Path $persistIcon) {
        $IconLocation = $persistIcon
    } else {
        Write-Warning "Icon not found at '$IconLocation'. Shortcut will be created without icon."
        $IconLocation = ""
    }
} catch {
    Write-Warning ("Failed to persist icon to ProgramData: {0}" -f $_.Exception.Message)
    if (-not (Test-Path $persistIcon)) { $IconLocation = "" } else { $IconLocation = $persistIcon }
}

# --- Resolve browser target (Edge preferred; fallback optional) ---
$edge = Get-EdgePath
[string]$targetExe  = $null
[string]$targetArgs = $null

if ($edge) {
    Write-Verbose "Edge found at: $edge"
    $targetExe = [string]$edge
    if ($UseAppWindow.IsPresent) { $targetArgs = "--app=$Url" } else { $targetArgs = "--new-window $Url" }
} else {
    if ($StrictEdge.IsPresent) { throw "Microsoft Edge not found in PATH/Registry/ProgramFiles for this context." }
    Write-Warning "Edge not found; falling back to default browser via explorer.exe"
    $targetExe  = "$env:WINDIR\explorer.exe"
    $targetArgs = $Url
}

# --- Create shortcuts (All users) ---
$startMenuDir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
$startMenuLnk = Join-Path $startMenuDir "$Name.lnk"
$startMenuUrl = Join-Path $startMenuDir "$Name.url"

$publicDesktop = Join-Path $env:Public 'Desktop'
$desktopLnk    = Join-Path $publicDesktop "$Name.lnk"
$desktopUrl    = Join-Path $publicDesktop "$Name.url"

$created = $false
try {
    New-ShortcutLnk -ShortcutPath $startMenuLnk -TargetExe $targetExe -Arguments $targetArgs -IconLocation $IconLocation
    New-ShortcutLnk -ShortcutPath $desktopLnk    -TargetExe $targetExe -Arguments $targetArgs -IconLocation $IconLocation
    $created = (Test-Path $startMenuLnk) -or (Test-Path $desktopLnk)
} catch {
    Write-Warning ("Failed to create .lnk shortcuts: {0}" -f $_.Exception.Message)
}

if (-not $created) {
    try {
        New-ShortcutUrl -ShortcutPathUrl $startMenuUrl -Url $Url -IconLocation $IconLocation
        New-ShortcutUrl -ShortcutPathUrl $desktopUrl   -Url $Url -IconLocation $IconLocation
        $created = (Test-Path $startMenuUrl) -or (Test-Path $desktopUrl)
    } catch {
        Write-Error ("Failed to create .url shortcuts: {0}" -f $_.Exception.Message)
    }
}

if (-not $created) {
    Stop-Transcript | Out-Null
    Write-Error "No shortcuts were created (.lnk and .url both failed)."
    exit 1
}

Write-Output "Installed shortcuts for '$Name' to Start Menu and Public Desktop."
Stop-Transcript | Out-Null
exit 0