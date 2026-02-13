<#
  Copyright (c) 2026 Sudeep Gyawali
  Licensed under the MIT License. See the LICENSE file in the repository root.
#>
<#
- Centralized arrays to include ALL apps you uninstall (MSI GUIDs, Appx/MSIX families, DisplayNames)
- Removes HP Wolf stack (via GUIDs + DisplayName fallback), HP/Poly MSI apps, HP Appx (including AD2F1837.myHP),
  Microsoft consumer Appx, Poly Edge PWAs; cleans lingering services/paths
- Logs actions and NOTIFIES users to restart (NO forced reboot)

LOG:   C:\ProgramData\Intune\Logs\Uninstallapps-Full.log
RUN:   powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstallapps-Full.ps1

Edit ONLY the arrays in the "INCLUDE LISTS" section to add more targets.
#>

param(
    [string]$LogPath = "C:\ProgramData\Intune\Logs\Uninstallapps-Full.log",
    [int]$MsiRetrySeconds = 60,
    [switch]$SkipHPPoly,
    [switch]$SkipConsumerApps,
    [switch]$NotifyAlways
)

# ===== INCLUDE LISTS (EDIT THESE ARRAYS) =====

# A) HP Wolf stack GUIDs (from triage) + add main Wolf GUID when collected
$WolfGuids = @(
    '{BC18E78B-DD6C-A3C8-A079-D001E021308A}', # HP Security Update Service
    '{E7420E72-BFE1-4E06-9202-199B629E8149}'  # HP Wolf Security - Console
    # '{D11FAF80-C7CC-4F10-XXXXXXXXXXXX}'     # HP Wolf Security (main app) -> paste full GUID once you capture it
)

# B) MSI GUIDs for HP/Poly targets (add/remove freely)
$TargetedMsiGuids = @(
    '{19F557DE-662A-4FEA-B635-1CACD56CC483}', # HP Notifications
    '{142F2395-3FCA-46F9-8867-A1968186E087}', # HP System Default Settings
    '{9E05E83B-8C88-46DA-B484-3BF4652884DF}', # HP Sure Recover
    '{75B0993A-9D9F-4F9F-A7F5-B0F3AC4C6FE1}', # HP Sure Run Module
    '{558000B1-3B4B-4784-A516-58EBF3560B78}', # Poly Camera Pro Compatibility Add-on
    '{E62BD969-711A-4534-BE3F-F60BFBACFB64}'  # Poly Lens
)

# C) MSI removal by DisplayName (for items without stable GUID)
$RemoveByName = @(
    'HP Wolf Security',
    'HP Wolf Security - Console',
    'HP Security Update Service'
)

# D) HP Appx/MSIX families (AD2F1837.* publisher) — handled for AllUsers + per-user + deprovision
$HpAppxFamilies = @(
    'AD2F1837.11510256BE195',           # numeric bundle (some HP builds)
    'AD2F1837.HPSupportAssistant',
    'AD2F1837.HPPCHardwareDiagnosticsWindows',
    'AD2F1837.HPDesktopSupportUtilities',
    'AD2F1837.HPPrivacySettings',
    'AD2F1837.HPCameraPro',
    'AD2F1837.myHP'                     # explicit for stubborn myHP
)

# E) Microsoft consumer Appx families (adjust as needed)
$ConsumerAppxFamilies = @(
    'Microsoft.GamingApp','Microsoft.XboxGamingOverlay','Microsoft.XboxApp',
    'Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay','Microsoft.Xbox.TCUI',
    'Microsoft.BingNews','Microsoft.News','Microsoft.BingWeather','Microsoft.BingSports','Microsoft.BingFinance',
    'Microsoft.MicrosoftSolitaireCollection','king.com.CandyCrushSaga','king.com.CandyCrushFriends','Disney.37853FC22B2CE',
    'Microsoft.MicrosoftOfficeHub','Microsoft.SkypeApp','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.People',
    'Microsoft.ZuneMusic','Microsoft.ZuneVideo'
)

# ===== END INCLUDE LISTS =====

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$script:AnyRebootNeeded = $false
$script:AnyChange       = $false

# ---------- Logging ----------
try {
    $logDir = Split-Path -Path $LogPath -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
} catch { }
function W { param([string]$Message)
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    "$ts`t$Message" | Add-Content -Path $LogPath
    Write-Host $Message
}
W "=== Full OEM + consumer apps removal starting ==="

# ---------- Helpers ----------
function Test-Guid { param([string]$Text) return ($Text -match '^\{[0-9A-Fa-f\-]{36}\}$') }

function Get-UninstallEntries {
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    $entries = @()
    foreach ($root in $roots) {
        try {
            $keys = Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try { $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue } catch { $p = $null }  # PSPath fix
                if ($p -and $p.DisplayName) {
                    $entries += [PSCustomObject]@{
                        DisplayName     = $p.DisplayName
                        DisplayVersion  = $p.DisplayVersion
                        Publisher       = $p.Publisher
                        UninstallString = $p.UninstallString
                        QuietUninstall  = $p.QuietUninstallString
                        InstallLocation = $p.InstallLocation
                        ProductCode     = $key.PSChildName
                        PSPath          = $key.PSPath
                    }
                }
            }
        } catch { }
    }
    return $entries
}

function Wait-IfBusy { param([int]$ExitCode)
    if ($ExitCode -eq 1618) {
        W ("Another installation in progress (1618). Waiting {0}s then retrying..." -f $MsiRetrySeconds)
        Start-Sleep -Seconds $MsiRetrySeconds
        return $true
    }
    return $false
}

function Normalize-InlineMSI {
    param([string]$UninstallString)
    $args = $UninstallString -replace '(?i)^.*msiexec\.exe', ''
    $args = $args.Trim() -replace '(?i)/i(\s*)\{', '/x$1{'
    if ($args -notmatch '(?i)(/quiet|/qn)') { $args = "$args /qn /norestart" }
    return $args
}

function Invoke-MSIByProductCode { param([string]$ProductCode)
    if ([string]::IsNullOrWhiteSpace($ProductCode)) { return 99999 }
    $args = "/x $ProductCode /qn /norestart"
    W ("msiexec {0}" -f $args)
    try {
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
        W ("ExitCode: {0}" -f $p.ExitCode)
        if ($p.ExitCode -eq 3010) { $script:AnyRebootNeeded = $true }
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { $script:AnyChange = $true }
        return $p.ExitCode
    } catch {
        W ("MSI uninstall failed ({0}): {1}" -f $ProductCode, $_.Exception.Message)
        return 99999
    }
}

function Invoke-UninstallString { param([string]$UninstallString)
    if ([string]::IsNullOrWhiteSpace($UninstallString)) { return 99999 }
    $cmd = $UninstallString.Trim()
    if ($cmd -match '(?i)msiexec\.exe') {
        $args = Normalize-InlineMSI -UninstallString $cmd
        W ("msiexec {0}" -f $args)
        try {
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
            W ("ExitCode: {0}" -f $p.ExitCode)
            if ($p.ExitCode -eq 3010) { $script:AnyRebootNeeded = $true }
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { $script:AnyChange = $true }
            return $p.ExitCode
        } catch {
            W ("UninstallString MSI failed: {0}" -f $_.Exception.Message)
            return 99999
        }
    } else {
        $exeOnly = Test-Path -LiteralPath $cmd
        if ($exeOnly) { $cmd = "`"$cmd`"" }
        if ($cmd -notmatch '(?i)(/quiet|/qn|/silent|/s)') { $cmd = "$cmd /S" }
        W ("cmd.exe /c {0}" -f $cmd)
        try {
            $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -PassThru -WindowStyle Hidden
            W ("ExitCode: {0}" -f $p.ExitCode)
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { $script:AnyChange = $true }
            return $p.ExitCode
        } catch {
            W ("UninstallString EXE failed: {0}" -f $_.Exception.Message)
            return 99999
        }
    }
}

function Remove-AppByName {
    param([string[]]$Names)
    $entries = Get-UninstallEntries
    foreach ($n in $Names) {
        $hits = $entries | Where-Object { $_.DisplayName -eq $n }
        if (-not $hits) { W ("Not found by DisplayName: {0}" -f $n); continue }
        foreach ($e in $hits) {
            W ("Uninstalling by name: {0}" -f $e.DisplayName)
            $exit = 99999
            if ($e.ProductCode -and (Test-Guid $e.ProductCode)) {
                $exit = Invoke-MSIByProductCode -ProductCode $e.ProductCode
                if ($exit -eq 1618) { if (Wait-IfBusy -ExitCode $exit) { $exit = Invoke-MSIByProductCode -ProductCode $e.ProductCode } }
            }
            if ($exit -eq 99999) {
                $cmd = $e.QuietUninstall; if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = $e.UninstallString }
                $exit = Invoke-UninstallString -UninstallString $cmd
                if ($exit -eq 1618) { if (Wait-IfBusy -ExitCode $exit) { $exit = Invoke-UninstallString -UninstallString $cmd } }
            }
        }
    }
}

# NEW: Appx remover that does AllUsers + per-user + deprovision for each family name/pattern
function Remove-Appx-Full {
    param([string[]]$NamesOrPatterns)

    # 1) AllUsers removal
    try {
        $pkgs = Get-AppxPackage -AllUsers
        foreach ($name in $NamesOrPatterns) {
            $matches = $pkgs | Where-Object { $_.Name -eq $name -or $_.Name -like "$name*" }
            foreach ($m in $matches) {
                W ("Removing Appx (AllUsers): {0}" -f $m.Name)
                try {
                    Remove-AppxPackage -Package $m.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                    $script:AnyChange = $true
                } catch {
                    W ("Appx removal failed ({0}): {1}" -f $m.Name, $_.Exception.Message)
                }
            }
        }
    } catch {
        W ("Get-AppxPackage (AllUsers) failed: {0}" -f $_.Exception.Message)
    }

    # 2) Per-user fallback (for stubborn installs like AD2F1837.myHP)
    try {
        $userSIDs = Get-ChildItem "HKU:\" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match 'S-1-5-21-' } |
                    Select-Object -ExpandProperty Name
        foreach ($sid in $userSIDs) {
            foreach ($name in $NamesOrPatterns) {
                try {
                    $uPkgs = Get-AppxPackage -User $sid | Where-Object { $_.Name -eq $name -or $_.Name -like "$name*" }
                    foreach ($up in $uPkgs) {
                        W ("Removing Appx for SID {0}: {1}" -f $sid, $up.Name)
                        Remove-AppxPackage -User $sid -Package $up.PackageFullName -ErrorAction SilentlyContinue
                        $script:AnyChange = $true
                    }
                } catch { }
            }
        }
    } catch {
        W ("Per-user Appx removal failed: {0}" -f $_.Exception.Message)
    }

    # 3) Deprovision (so new profiles won’t get them)
    try {
        $prov = Get-AppxProvisionedPackage -Online
        foreach ($name in $NamesOrPatterns) {
            $provMatch = $prov | Where-Object { $_.DisplayName -eq $name -or $_.DisplayName -like "$name*" }
            foreach ($p in $provMatch) {
                W ("Deprovisioning Appx: {0}" -f $p.DisplayName)
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue
                    $script:AnyChange = $true
                } catch {
                    W ("Deprovision failed ({0}): {1}" -f $p.DisplayName, $_.Exception.Message)
                }
            }
        }
    } catch {
        W ("Get-AppxProvisionedPackage failed: {0}" -f $_.Exception.Message)
    }
}

function Disable-GameFeatures {
    try {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Force | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowgameDVR" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        W "Policy set: Disable Game DVR"
    } catch { W ("Failed to set GameDVR policy: {0}" -f $_.Exception.Message) }
    foreach ($sid in (Get-ChildItem "HKU:\" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'S-1-5-21-' })) {
        try {
            $userKey = "$($sid.Name)\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
            New-Item -Path $userKey -Force | Out-Null
            New-ItemProperty -Path $userKey -Name "AppCaptureEnabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            $cfgKey = "$($sid.Name)\System\GameConfigStore"
            New-Item -Path $cfgKey -Force | Out-Null
            New-ItemProperty -Path $cfgKey -Name "GameDVR_Enabled" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            W ("User $($sid.Name): Game Bar / DVR disabled")
        } catch { W ("Failed to disable Game Bar for $($sid.Name): {0}" -f $_.Exception.Message) }
    }
}

# ---------- Stop blockers (services/processes) ----------
function Stop-Blockers {
    try {
        Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match 'HP Wolf|HP Security Update|Touchpoint|Sure Run' -or
            $_.Name -match 'HPWolfService|HpTouchpointAnalyticsService|HPSysInfo|HP.*Update|HP.*Run'
        } | ForEach-Object {
            if ($_.Status -ne 'Stopped') {
                W ("Stopping service: {0} ({1})" -f $_.Name, $_.DisplayName)
                Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { W ("Service scan/stop failed: {0}" -f $_.Exception.Message) }

    foreach ($p in @('HPNotifications','HpSfuService64','hpsvcsscan','hpqwmiex','HPCommRecovery','HPWolf','HPConnectionOptimizer','HPClientSecurityManager','PolyLens')) {
        try {
            Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
                W ("Killing process: {0}" -f $_.Name)
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch { W ("Process kill failed ({0}): {1}" -f $p, $_.Exception.Message) }
    }
}

# ---------- 0) Stop blockers ----------
Stop-Blockers

# ---------- 1) HP Wolf stack ----------
if (-not $SkipHPPoly) {
    foreach ($guid in $WolfGuids) {
        $exit = Invoke-MSIByProductCode -ProductCode $guid
        if ($exit -eq 1618) { if (Wait-IfBusy -ExitCode $exit) { Invoke-MSIByProductCode -ProductCode $guid } }
    }
    Remove-AppByName -Names $RemoveByName
}

# ---------- 2) HP/Poly targeted MSI removals ----------
if (-not $SkipHPPoly) {
    # HP Documentation
    if (Test-Path -LiteralPath 'C:\Program Files\HP\Documentation\Doc_Uninstall.cmd') {
        W "Running HP Documentation uninstall script"
        Invoke-UninstallString -UninstallString 'CMD /C "C:\Program Files\HP\Documentation\Doc_Uninstall.cmd"'
    } else { W "HP Documentation uninstall script not found" }

    foreach ($guid in $TargetedMsiGuids) {
        $exit = Invoke-MSIByProductCode -ProductCode $guid
        if ($exit -eq 1618) { if (Wait-IfBusy -ExitCode $exit) { Invoke-MSIByProductCode -ProductCode $guid } }
    }

    foreach ($f in @(
        'C:\Program Files (x86)\HP\HP Notifications',
        'C:\Program Files (x86)\HP\HP System Default Settings',
        'C:\Program Files\HP\Documentation',
        'C:\Program Files (x86)\Poly\Lens',
        'C:\Program Files\Poly\Lens'
    )) {
        try { if (Test-Path -LiteralPath $f) { W ("Removing folder: {0}" -f $f); Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue } }
        catch { W ("Folder cleanup failed ({0}): {1}" -f $f, $_.Exception.Message) }
    }

    try {
        Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'HP Wolf|HP Security Update' } | ForEach-Object {
            W ("Deleting lingering service: {0} ({1})" -f $_.Name, $_.DisplayName)
            sc.exe delete "$($_.Name)" | Out-Null
        }
    } catch { W ("Service delete failed: {0}" -f $_.Exception.Message) }
}

# ---------- 3) HP Appx cleanup (AllUsers + per-user + deprovision) ----------
if (-not $SkipHPPoly) {
    Remove-Appx-Full -NamesOrPatterns $HpAppxFamilies

    # Poly / Camera Edge PWAs
    try {
        Get-ChildItem -LiteralPath "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $userRoot = $_.FullName
            $ud = Join-Path $userRoot "AppData\Local\Microsoft\Edge\User Data"
            if (Test-Path -LiteralPath $ud) {
                Get-ChildItem -LiteralPath $ud -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $webApps = Join-Path $_.FullName "Web Applications"
                    if (Test-Path -LiteralPath $webApps) {
                        Get-ChildItem -LiteralPath $webApps -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                            $name = $_.Name.ToLower()
                            if ($name -like "*poly*" -or $name -like "*camera*") {
                                W ("Deleting Edge PWA folder: {0}" -f $_.FullName)
                                try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { W ("Failed to delete PWA folder: {0}" -f $_.FullName) }
                                $script:AnyChange = $true
                            }
                        }
                    }
                }
            }
        }
    } catch { W ("Edge profiles scan failed: {0}" -f $_.Exception.Message) }
}

# ---------- 4) Microsoft consumer apps ----------
if (-not $SkipConsumerApps) {
    W "--- Microsoft consumer apps cleanup ---"
    Remove-Appx-Full -NamesOrPatterns $ConsumerAppxFamilies
    W "Non-removable: Microsoft.XboxGameCallableUI → disabling Game Bar/DVR via policy."
    Disable-GameFeatures
}

# ---------- 5) HCO orphan key ----------
$hcoFilesGone = -not (Test-Path -LiteralPath "C:\Program Files (x86)\HP Inc\HP Connection Optimizer")
if ($hcoFilesGone) { try { Remove-Item -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{6468C4A5-E47E-405F-B675-A70A70983EA6}" -Recurse -Force -ErrorAction SilentlyContinue } catch { } }

# ---------- Notify only ----------
if ($script:AnyRebootNeeded -or $script:AnyChange -or $NotifyAlways) {
    W "Notify user: restart recommended to complete clean-up."
    try { Start-Process -FilePath "msg.exe" -ArgumentList "* Restart required to complete removal of unwanted applications." -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null } catch { }
} else {
    W "No critical changes requiring restart were detected."
}

W "=== Full removal completed (no forced restart). ==="