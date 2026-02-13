<#
  Copyright (c) 2026 Sudeep Gyawali
  Licensed under the MIT License. See the LICENSE file in the repository root.
#>
<#
Cleans cached Microsoft 365 identity data on Windows and prevents auto MDM re-enrol prompts.

.DESCRIPTION
    For domain-joined or workgroup PCs where you need to reset M365 sign-in state:
    - Disables auto MDM enrollment (policy key)
    - Clears AAD Broker, OneAuth/WAM, Office identity/licensing caches
    - Clears Outlook AutoDiscover cache (file + registry)
    - Optionally removes Outlook profiles (forces fresh profile on next start)
    - Purges matching Windows Credentials (by pattern list)
    - Shows dsregcmd join state (read-only)
    - Leaves local AD domain join untouched.

.PARAMETER CredentialPatterns
    Strings/regex fragments to match Windows Credentials to delete (Target names).
    Default focuses on Microsoft identity endpoints; pass your own to remove tenant-specific entries.

.PARAMETER SkipOutlookProfiles
    If set, Outlook profiles are NOT removed.
#>

[CmdletBinding()]
param(
    [string[]]$CredentialPatterns = @('tenant','office','outlook','oneauth','login.microsoftonline','azuread'),
    [switch]$SkipOutlookProfiles
)

# --- Guardrails ---
$ErrorActionPreference = 'Stop'
Write-Host "=== M365 T2T Cleanup starting... ===" -ForegroundColor Cyan

# Require Admin
$currIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script from an elevated (Run as administrator) PowerShell window."
}

# Stop common Office/identity processes
$procs = @(
  'outlook','winword','excel','powerpnt','onenote','onenotem','onenoteim',
  'teams','ms-teams','MSTeams','onedrive','identityhelper','webaccountmanager',
  'Microsoft.AAD.BrokerPlugin','RuntimeBroker'
)
Get-Process | Where-Object { $procs -contains $_.Name } | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
}
Start-Sleep -Seconds 2

# --- 1) Disable MDM auto-enrollment (prevents device mgmt prompt loops) ---
$mdmKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
if (-not (Test-Path $mdmKey)) { New-Item -Path $mdmKey -Force | Out-Null }
New-ItemProperty -Path $mdmKey -Name 'AutoEnrollMDM' -PropertyType DWord -Value 0 -Force | Out-Null
Write-Host "[OK] MDM auto-enrollment disabled (HKLM\...\MDM\AutoEnrollMDM=0)."

# --- 2) Clear AAD Broker tokens (critical for 48v35/device management errors) ---
$aadBroker = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'
if (Test-Path $aadBroker) {
    Get-ChildItem $aadBroker -Force | Where-Object { $_.Name -ne 'Settings' } | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-Host "[OK] AAD Broker cache cleared (kept Settings)."
} else {
    Write-Host "[SKIP] AAD Broker folder not found."
}

# --- 3) Clear Office/WAM identity & licensing caches ---
$pathsToPurge = @(
  (Join-Path $env:LOCALAPPDATA 'Microsoft\IdentityCache'),
  (Join-Path $env:LOCALAPPDATA 'Microsoft\OneAuth'),
  (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\Identity'),
  (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\Licensing')
)
foreach ($p in $pathsToPurge) {
    if (Test-Path $p) {
        try { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        Write-Host "[OK] Removed $p"
    } else {
        Write-Host "[SKIP] $p not found."
    }
}

# --- 4) Clear Outlook Autodiscover caches (filesystem + registry) ---
$autoFs = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook\Autodiscover'
if (Test-Path $autoFs) {
    try { Remove-Item $autoFs -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    Write-Host "[OK] Cleared file Autodiscover cache."
}

$autoReg = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\AutoDiscover'
if (Test-Path $autoReg) {
    try { Remove-Item $autoReg -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    Write-Host "[OK] Cleared registry Autodiscover cache."
}

# --- 5) Remove old Outlook profiles (so a fresh profile binds to new tenant) ---
$profilesReg = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
if (Test-Path $profilesReg) {
    try { Remove-Item $profilesReg -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    Write-Host "[OK] Removed old Outlook profiles. A fresh profile will be created on next start."
} else {
    Write-Host "[SKIP] Outlook profiles key not found."
}

# --- 6) Purge Windows Credential Manager entries related to old tenant ---
# Uses 'cmdkey' to enumerate Windows Credentials and delete matching targets.
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
        try {
            cmdkey /delete:$t | Out-Null
            Write-Host "[OK] Deleted Windows Credential: $t"
        } catch {
            Write-Host "[WARN] Could not delete credential: $t"
        }
    }
} else {
    Write-Host "[SKIP] cmdkey returned no credentials or is unavailable."
}

# --- 7) Optional: confirm Workplace/Azure AD state (read-only) ---
try {
    $ds = & dsregcmd /status 2>$null
    if ($LASTEXITCODE -eq 0) {
        ($ds | Select-String -Pattern 'AzureAdJoined|WorkplaceJoined|DomainJoined') | ForEach-Object { $_.ToString() }
    }
} catch {}

Write-Host "=== Cleanup complete. Please RESTART the PC now. ===" -ForegroundColor Green