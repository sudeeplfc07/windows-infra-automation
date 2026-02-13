# Default Apps / OEM Bloat Removal (Windows)

Detection + remediation to remove targeted OEM (HP/Poly) and Microsoft consumer apps.  
Works for MSI and Appx, including per-user installs and provisioned packages.

## What it does
- **Detect**: flags targeted MSI by ProductCode and DisplayName; HP Doc marker; HCO orphan key; Appx presence for AllUsers/per-user/provisioned; Poly Edge PWA remnants. (Exit **1** if anything found; **0** if clean.)
- **Remediate**: silent MSI uninstall (handles 1618 retry), Appx removal (AllUsers + per-user) and **deprovision**, service/process cleanup, optional **skip** flags, user restart **notification only** (no forced reboot).

## Files
- `Detect-DefaultApps.ps1` – health check/detection.
- `Remove-DefaultApps.ps1` – full removal and cleanup.

## Requirements
- Windows 10/11
- PowerShell 5.1+ (PowerShell 7 supported)
- Run as Administrator (required for HKLM and Program Files changes)

## Parameters (Remove-DefaultApps.ps1)
| Name | Type | Default | Description |
|---|---|---|---|
| `-LogPath` | string | `C:\ProgramData\Intune\Logs\Uninstallapps-Full.log` | Where logs are written. |
| `-MsiRetrySeconds` | int | `60` | Wait/retry if msiexec is busy (1618). |
| `-SkipHPPoly` | switch | — | Skip HP/Poly removals. |
| `-SkipConsumerApps` | switch | — | Skip Microsoft consumer apps. |
| `-NotifyAlways` | switch | — | Always notify a restart, even if no changes detected. |

## Usage (manual)
   powershell
# Detection (exit 1 if cleanup needed)
.\Detect-DefaultApps.ps1; $LASTEXITCODE

# Remediation (all targets)
.\Remove-DefaultApps.ps1 -Verbose

# Skip consumer apps (remove OEM only)
.\Remove-DefaultApps.ps1 -SkipConsumerApps -Verbose

# x86 vs x64: 32‑bit apps often register under
HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall

# Per‑user MSIs: Some installers write under 
HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{GUID}—run the query in the user context if needed.

# Non‑MSI installers (EXE): They do not have MSI ProductCodes and rely on Displayname.

## License
Licensed under the MIT License. See the [LICENSE](../LICENSE) file in the repo root for details.
