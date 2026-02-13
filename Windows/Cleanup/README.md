# Windows Profile / M365 Identity Cleanup

Resets cached Microsoft 365 sign-in state on Windows machines and prevents auto MDM re-enrol prompts.  
Useful after tenant-to-tenant migrations or when Outlook/Office/OneAuth tokens are stuck.

## What it does
- Disables **auto MDM enrollment** (policy key).
- Clears **AAD Broker**, **OneAuth/WAM**, and **Office identity/licensing** caches.
- Clears Outlook **AutoDiscover** cache (file + registry).
- Optionally **removes Outlook profiles** (forces fresh profile next launch).
- Purges matching **Windows Credentials** (by target-name pattern list).
- Prints **dsregcmd** join state (AzureAdJoined / WorkplaceJoined / DomainJoined).

## Files
- `Clean-WindowsProfile.ps1`

## Requirements
- Windows 10/11
- PowerShell 5.1+
- Run **as Administrator** (HKLM policy and credential delete require elevation)

## Parameters
| Name | Type | Default | Description |
|---|---|---|---|
| `-CredentialPatterns` | string[] | `tenant, office, outlook, oneauth, login.microsoftonline, azuread` | Target-name fragments to match in Windows Credentials. Add your tenant/brand strings here. |
| `-SkipOutlookProfiles` | switch | — | If set, Outlook profiles are **not** removed. |

## Usage
   powershell
# Standard cleanup (will remove Outlook profiles)
.\Clean-WindowsProfile.ps1 -Verbose

# Keep Outlook profiles intact
.\Clean-WindowsProfile.ps1 -SkipOutlookProfiles -Verbose

# Include tenant-specific strings for credential cleanup
.\Clean-WindowsProfile.ps1 -CredentialPatterns 'tenant','contoso','login.microsoftonline','azuread' -Verbose

## License
Licensed under the MIT License. See the [LICENSE](../LICENSE) file in the repo root for details.
