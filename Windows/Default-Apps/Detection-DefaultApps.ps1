<#
  Copyright (c) 2026 Sudeep Gyawali
  Licensed under the MIT License. See the LICENSE file in the repository root.
#>
# Detects unwanted MSI apps (by GUID + DisplayName), HP Documentation marker, HCO orphan key,
# HP & Microsoft Appx (AllUsers + per-user + provisioned), and Poly Edge PWA remnants.
# Arrays are INLINE — edit only the lists below to maintain parity with remediation.
# Exit 1 if anything is present; Exit 0 if clean.
# You can include as many application you want to remove into this script identify the application GUID, APPX and Name that you want to remove and 
# add those details below also for some identify the installed path

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$script:IssuesFound    = $false


# A) HP Wolf stack GUIDs (add main Wolf GUID when you capture it)
$WolfGuids = @(
    '{BC18E78B-DD6C-A3C8-A079-D001E021308A}', # HP Security Update Service
    '{E7420E72-BFE1-4E06-9202-199B629E8149}'  # HP Wolf Security - Console
    # '{D11FAF80-C7CC-4F10-XXXXXXXXXXXX}'     # HP Wolf Security (main app)
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

# D) HP Appx/MSIX families (AD2F1837.* publisher)
$HpAppxFamilies = @(
    'AD2F1837.11510256BE195',           # numeric HP bundle
    'AD2F1837.HPSupportAssistant',
    'AD2F1837.HPPCHardwareDiagnosticsWindows',
    'AD2F1837.HPDesktopSupportUtilities',
    'AD2F1837.HPPrivacySettings',
    'AD2F1837.HPCameraPro',
    'AD2F1837.myHP'
)

# E) Microsoft consumer Appx families
$ConsumerAppxFamilies = @(
    'Microsoft.GamingApp','Microsoft.XboxGamingOverlay','Microsoft.XboxApp',
    'Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay','Microsoft.Xbox.TCUI',
    'Microsoft.BingNews','Microsoft.News','Microsoft.BingWeather','Microsoft.BingSports','Microsoft.BingFinance',
    'Microsoft.MicrosoftSolitaireCollection','king.com.CandyCrushSaga','king.com.CandyCrushFriends','Disney.37853FC22B2CE',
    'Microsoft.MicrosoftOfficeHub','Microsoft.SkypeApp','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.People',
    'Microsoft.ZuneMusic','Microsoft.ZuneVideo'
)

# ===== END INCLUDE LISTS =====

function Add-Issue { param([string]$Text) if ($Text) { Write-Output $Text; $script:IssuesFound = $true } }

function Get-UninstallEntries {
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    $entries = @()
    foreach ($root in $roots) {
        try {
            $keys = Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try { $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue } catch { $p = $null }
                if ($p -and $p.DisplayName) {
                    $entries += [PSCustomObject]@{
                        DisplayName     = $p.DisplayName
                        DisplayVersion  = $p.DisplayVersion
                        Publisher       = $p.Publisher
                        UninstallString = $p.UninstallString
                        QuietUninstall  = $p.QuietUninstallString
                        ProductCode     = $key.PSChildName
                        PSPath          = $key.PSPath
                    }
                }
            }
        } catch { }
    }
    return $entries
}

# ---------- 1) MSI GUID detection ----------
$AllGuids = @() + $WolfGuids + $TargetedMsiGuids
foreach ($g in $AllGuids) {
    $p1 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$g"
    $p2 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$g"
    if ((Test-Path -LiteralPath $p1) -or (Test-Path -LiteralPath $p2)) {
        Add-Issue "MSI GUID present: $g"
    }
}

# ---------- 2) MSI by DisplayName (fallback) ----------
$entries = Get-UninstallEntries
foreach ($name in $RemoveByName) {
    $hits = $entries | Where-Object { $_.DisplayName -eq $name }
    foreach ($h in $hits) { Add-Issue ("MSI by name present: " + $h.DisplayName) }
}

# ---------- 3) HP Documentation marker ----------
if (Test-Path -LiteralPath 'C:\Program Files\HP\Documentation\Doc_Uninstall.cmd') {
    Add-Issue "HP Documentation uninstall script present"
}

# ---------- 4) HCO orphan uninstall key ----------
$HcoKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{6468C4A5-E47E-405F-B675-A70A70983EA6}'
if (Test-Path -LiteralPath $HcoKey) { Add-Issue "HP Connection Optimizer orphan uninstall key present" }

# ---------- 5) Appx/MSIX (AllUsers) ----------
try {
    $appxAll = Get-AppxPackage -AllUsers
    foreach ($n in ($HpAppxFamilies + $ConsumerAppxFamilies)) {
        if ($appxAll | Where-Object { $_.Name -eq $n -or $_.Name -like "$n*" }) {
            Add-Issue "Appx installed (AllUsers): $n"
        }
    }
} catch { Add-Issue ("Get-AppxPackage (-AllUsers) failed: " + $_.Exception.Message) }

# Per-user (stubborn installs)
try {
    $userSIDs = Get-ChildItem "HKU:\" -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match 'S-1-5-21-' } |
               Select-Object -ExpandProperty Name
    foreach ($sid in $userSIDs) {
        foreach ($n in ($HpAppxFamilies + $ConsumerAppxFamilies)) {
            try {
                $u = Get-AppxPackage -User $sid | Where-Object { $_.Name -eq $n -or $_.Name -like "$n*" }
                if ($u) { Add-Issue ("Appx installed (User $sid): $n") }
            } catch { }
        }
    }
} catch { Add-Issue ("Per-user Get-AppxPackage failed: " + $_.Exception.Message) }

# Provisioned (staged)
try {
    $prov = Get-AppxProvisionedPackage -Online
    foreach ($n in ($HpAppxFamilies + $ConsumerAppxFamilies)) {
        $pm = $prov | Where-Object { $_.DisplayName -eq $n -or $_.DisplayName -like "$n*" }
        foreach ($p in $pm) { Add-Issue ("Provisioned package present: " + $p.DisplayName) }
    }
} catch { Add-Issue ("Get-AppxProvisionedPackage failed: " + $_.Exception.Message) }

# ---------- 6) Poly Edge PWA remnants ----------
try {
    $usersRoot = "C:\Users"
    if (Test-Path -LiteralPath $usersRoot) {
        $userDirs = Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue
        foreach ($ud in $userDirs) {
            $profileRoot = Join-Path $ud.FullName "AppData\Local\Microsoft\Edge\User Data"
            if (Test-Path -LiteralPath $profileRoot) {
                $subProfiles = Get-ChildItem -LiteralPath $profileRoot -Directory -ErrorAction SilentlyContinue
                foreach ($sp in $subProfiles) {
                    $webApps = Join-Path $sp.FullName "Web Applications"
                    if (Test-Path -LiteralPath $webApps) {
                        $folders = Get-ChildItem -LiteralPath $webApps -Directory -ErrorAction SilentlyContinue
                        foreach ($f in $folders) {
                            $name = $f.Name.ToLower()
                            if (($name -like "*poly*") -or ($name -like "*camera*")) {
                                Add-Issue ("Poly Edge PWA folder present: " + $f.FullName)
                            }
                        }
                    }
                }
            }
        }
    }
} catch { Add-Issue ("Edge profiles scan failed: " + $_.Exception.Message) }

# ---------- Result ----------
if ($script:IssuesFound) {
    exit 1
} else {
    Write-Host "No unwanted apps or remnants found. Endpoint is clean."
    exit 0
}