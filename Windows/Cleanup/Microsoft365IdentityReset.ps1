<#
    Microsoft 365 Identity Reset – Logging Edition
    Author: Sudeep Gyawali
    Purpose:
        - Resolve Office activation loops
        - Fix Teams sign‑in issues
        - Remove ghost personal Microsoft accounts
        - Reset WAM, AAD, CloudStore, OneAuth, Office identity
        - Disable MDM auto‑enrolment loops
        - Clean Outlook profiles & Autodiscover
        - Purge Windows Credential Manager entries

    Safe for remote execution. Does NOT remove Windows login accounts.
#>

[CmdletBinding()]
param(
    [string[]]$CredentialPatterns = @(
        'tenant','office','outlook','oneauth','login.microsoftonline',
        'azuread','microsoft','teams'
    ),
    [switch]$SkipOutlookProfiles
)

# --- Logging Setup ---
$LogPath = "$env:USERPROFILE\Desktop\M365-Identity-Reset-Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
function Log { param($msg) $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") ; "$timestamp  $msg" | Tee-Object -FilePath $LogPath -Append }

Log "=== Microsoft 365 Identity Reset Starting ==="

$ErrorActionPreference = 'Stop'

# --- Admin Check ---
$currIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Log "ERROR: Script must be run as Administrator."
    throw "Please run this script from an elevated PowerShell window."
}
Log "Admin check passed."

# --- Stop Identity‑Related Processes ---
$procs = @(
  'outlook','winword','excel','powerpnt','onenote','onenotem','onenoteim',
  'teams','ms-teams','MSTeams','onedrive','identityhelper','webaccountmanager',
  'Microsoft.AAD.BrokerPlugin','RuntimeBroker'
)
Get-Process | Where-Object { $procs -contains $_.Name } | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue ; Log "Stopped process: $($_.Name)" } catch {}
}
Start-Sleep -Seconds 2

# --- Disable Auto MDM Enrollment ---
$mdmKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
if (-not (Test-Path $mdmKey)) { New-Item -Path $mdmKey -Force | Out-Null }
New-ItemProperty -Path $mdmKey -Name 'AutoEnrollMDM' -PropertyType DWord -Value 0 -Force | Out-Null
Log "Disabled MDM auto-enrollment."

# --- Clear AAD Broker Tokens ---
$aadBroker = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'
if (Test-Path $aadBroker) {
    Get-ChildItem $aadBroker -Force | Where-Object { $_.Name -ne 'Settings' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Log "Cleared AAD Broker cache."
}

# --- Clear Office/WAM Identity Caches ---
$pathsToPurge = @(
  (Join-Path $env:LOCALAPPDATA 'Microsoft\IdentityCache'),
  (Join-Path $env:LOCALAPPDATA 'Microsoft\OneAuth'),
  (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\Identity'),
  (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\Licensing')
)
foreach ($p in $pathsToPurge) {
    if (Test-Path $p) {
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        Log "Removed: $p"
    }
}

# --- Clear Outlook Autodiscover ---
$autoFs = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook\Autodiscover'
if (Test-Path $autoFs) {
    Remove-Item $autoFs -Recurse -Force -ErrorAction SilentlyContinue
    Log "Cleared Outlook Autodiscover (filesystem)."
}

$autoReg = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\AutoDiscover'
if (Test-Path $autoReg) {
    Remove-Item $autoReg -Recurse -Force -ErrorAction SilentlyContinue
    Log "Cleared Outlook Autodiscover (registry)."
}

# --- Remove Outlook Profiles ---
if (-not $SkipOutlookProfiles) {
    $profilesReg = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
    if (Test-Path $profilesReg) {
        Remove-Item $profilesReg -Recurse -Force -ErrorAction SilentlyContinue
        Log "Removed Outlook profiles."
    }
}

# --- Purge Windows Credential Manager Entries ---
$cmdkeyOut = (cmdkey /list) 2>$null
if ($cmdkeyOut) {
    $targets = $cmdkeyOut | Select-String -Pattern 'Target:' | ForEach-Object {
        ($_ -replace '^\s*Target:\s*','').Trim()
    }
    $toDelete = @()
    foreach ($t in $targets) {
        foreach ($pat in $CredentialPatterns) {
            if ($t -match [Regex]::Escape($pat)) { $toDelete += $t; break }
        }
    }
    $toDelete = $toDelete | Sort-Object -Unique
    foreach ($t in $toDelete) {
        cmdkey /delete:$t | Out-Null
        Log "Deleted Windows Credential: $t"
    }
}

# --- Clear CloudStore (Windows Shell Identity Cache) ---
$cloudStore = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\CloudStore'
if (Test-Path $cloudStore) {
    Remove-Item $cloudStore -Recurse -Force -ErrorAction SilentlyContinue
    Log "Cleared CloudStore identity cache."
}

# --- Clear AAD & IdentityCRL Registry Keys ---
$aadReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AAD'
$idCrl = 'HKCU:\Software\Microsoft\IdentityCRL'

foreach ($reg in @($aadReg, $idCrl)) {
    if (Test-Path $reg) {
        Remove-Item $reg -Recurse -Force -ErrorAction SilentlyContinue
        Log "Removed registry key: $reg"
    }
}

# --- Clear Teams v2 (MSIX) Identity Cache ---
$teamsV2 = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'
if (Test-Path $teamsV2) {
    Remove-Item $teamsV2 -Recurse -Force -ErrorAction SilentlyContinue
    Log "Cleared Teams v2 identity cache."
}

# --- Show Join State ---
try {
    $ds = & dsregcmd /status 2>$null
    ($ds | Select-String -Pattern 'AzureAdJoined|WorkplaceJoined|DomainJoined') | ForEach-Object { Log $_.ToString() }
} catch {}

Log "=== Identity Reset Complete. Restart the PC to apply changes. ==="
Write-Host "Log saved to: $LogPath" -ForegroundColor Green
