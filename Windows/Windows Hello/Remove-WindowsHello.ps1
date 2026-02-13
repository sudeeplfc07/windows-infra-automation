<#
  Copyright (c) 2026 Sudeep Gyawali
  Licensed under the MIT License. See the LICENSE file in the repository root.
#>
<#
Disables Windows Hello and removes existing PIN/NGC data.

.DESCRIPTION
    - Sets device policies to disable:
        * WHfB provisioning (PassportForWork Enabled=0)
        * Legacy convenience PIN sign-in for domain users (AllowDomainPINLogon=0)
        * Biometrics (Biometrics Enabled=0)
        * Sign-in options UI (AllowSignInOptions=0)
    - Optionally removes the NGC container so any existing PIN/keys are cleared.
    - Stops/starts Passport services around NGC operations and handles ACL/ownership.

    Notes (policy references):
      • Use Windows Hello for Business → Disabled (GPO) / PassportForWork\Enabled=0 (registry)  ⟶ blocks WHfB.  [MS Learn, community refs]  # see links below
      • Turn on convenience PIN sign-in → Disabled / Windows\System\AllowDomainPINLogon=0       ⟶ blocks legacy PIN. # see links below
      • Allow the use of biometrics → Disabled / Biometrics\Enabled=0                           ⟶ blocks biometrics.   # see links below
      • AllowSignInOptions → 0 (PolicyManager)                                                  ⟶ hides Hello options.  # see links below

.PARAMETER SkipNgcRemoval
    If set, only disables policies; does NOT delete the NGC folder.

.PARAMETER NoBackup
    If set with NGC removal, deletes NGC without creating a backup copy first.

.EXAMPLE
    # Disable Hello and remove any existing PIN data
    .\Disable-WindowsHello.ps1 -Verbose

.EXAMPLE
    # Disable Hello policies only (leave existing NGC as-is)
    .\Disable-WindowsHello.ps1 -SkipNgcRemoval -Verbose

.NOTES
    Policy sources used while preparing this script:
      - Windows Hello for Business policy settings (MS Learn)  https://learn.microsoft.com/.../policy-settings
      - Disable Windows Hello using Group Policy (P. Desai)     https://www.prajwaldesai.com/disable-windows-hello-using-group-policy/
      - Disable/Enable Biometrics via registry (TenForums)      https://www.tenforums.com/tutorials/117987-enable-disable-windows-hello-biometrics-windows-10-a.html
      - AllowDomainPINLogon (convenience PIN) policy mapping    https://www.tenforums.com/tutorials/80520-enable-disable-domain-users-sign-pin-windows-10-a.html
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipNgcRemoval,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    throw "Please run from an elevated (Run as administrator) PowerShell session."
}

Write-Host "=== Disabling Windows Hello / WHfB (and optionally removing existing PIN) ===" -ForegroundColor Cyan

# --- 1) Disable Windows Hello / WHfB and related sign-in methods via registry policies ---

# 1a) WHfB (PassportForWork) -> Enabled = 0
#     Equivalent to 'Use Windows Hello for Business: Disabled'  (GPO path: Computer Config > Admin Templates > Windows Components > Windows Hello for Business)
$pfwKey = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'
if (-not (Test-Path $pfwKey)) { New-Item -Path $pfwKey -Force | Out-Null }
New-ItemProperty -Path $pfwKey -Name 'Enabled' -PropertyType DWord -Value 0 -Force | Out-Null

# 1b) Legacy/Convenience PIN sign-in for domain users -> AllowDomainPINLogon = 0
#     (GPO path: Computer Config > Admin Templates > System > Logon > Turn on convenience PIN sign-in)
$pinKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
if (-not (Test-Path $pinKey)) { New-Item -Path $pinKey -Force | Out-Null }
New-ItemProperty -Path $pinKey -Name 'AllowDomainPINLogon' -PropertyType DWord -Value 0 -Force | Out-Null

# 1c) Biometrics -> Enabled = 0
#     (GPO path: Computer Config > Admin Templates > Windows Components > Biometrics > Allow the use of biometrics)
$bioKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics'
if (-not (Test-Path $bioKey)) { New-Item -Path $bioKey -Force | Out-Null }
New-ItemProperty -Path $bioKey -Name 'Enabled' -PropertyType DWord -Value 0 -Force | Out-Null

# 1d) Hide sign-in options UI -> PolicyManager\default\Settings\AllowSignInOptions value=0
#     Makes Hello options unavailable in Settings on many builds.
$pmKey = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowSignInOptions'
if (-not (Test-Path $pmKey)) { New-Item -Path $pmKey -Force | Out-Null }
New-ItemProperty -Path $pmKey -Name 'value' -PropertyType DWord -Value 0 -Force | Out-Null

Write-Host "[OK] Policies set to disable WHfB, convenience PIN, biometrics, and sign-in options."

# --- 2) (Optional) Remove existing NGC (PIN/keys) so Hello cannot be used even if previously configured ---
if (-not $SkipNgcRemoval) {
    $ngcPath = Join-Path $env:WINDIR 'ServiceProfiles\LocalService\AppData\Local\Microsoft\NGC'

    # Stop Passport services before touching NGC
    $services = @('NgcCtnrSvc','NgcSvc')  # Microsoft Passport Container + Microsoft Passport
    foreach ($svc in $services) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne 'Stopped') {
            Write-Verbose "Stopping service: $svc"
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path -LiteralPath $ngcPath) {
        # Take ownership + grant Administrators full control to ensure deletion succeeds
        & takeown.exe /F "$ngcPath" /R /D Y | Out-Null
        & icacls.exe "$ngcPath" /grant Administrators:F /T /C | Out-Null

        $backupPath = "$ngcPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (-not $NoBackup) {
            try {
                Rename-Item -LiteralPath $ngcPath -NewName (Split-Path -Leaf $backupPath) -ErrorAction Stop
                Write-Host "Backed up NGC folder to: $backupPath"
            } catch {
                Write-Warning "Backup (rename) failed: $($_.Exception.Message). Proceeding with direct delete."
            }
        }

        $target = (Test-Path -LiteralPath $backupPath) ? $backupPath : $ngcPath
        try {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Existing Windows Hello container removed."
        } catch {
            Write-Error "Failed to remove NGC container: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "[OK] No NGC folder found—nothing to remove."
    }

    # Restart services (harmless if disabled by policy; ensures system baseline)
    foreach ($svc in $services) {
        $exists = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($exists) {
            Write-Verbose "Starting service: $svc"
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "[SKIP] NGC removal skipped (policies only)."
}

Write-Host "`n=== Completed. Reboot is recommended to fully enforce sign-in policy changes. ===" -ForegroundColor Green
exit 0