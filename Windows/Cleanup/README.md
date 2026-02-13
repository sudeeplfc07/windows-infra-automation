# Profile & Identity Cleanup

PowerShell script for cleaning cached Microsoft 365 identity data and preventing auto MDM enrollment prompts.

### What It Does

Cleans cached Microsoft 365 identity data on Windows and prevents auto MDM re-enrollment prompts. Designed for domain-joined or workgroup PCs where M365 sign-in state needs to be reset.

### Actions Performed

1. **Disables auto MDM enrollment** - Sets policy key to prevent device management prompt loops
2. **Clears AAD Broker tokens** - Removes Microsoft.AAD.BrokerPlugin cache (critical for error codes like 48v35)
3. **Clears Office/WAM identity & licensing caches** - Removes IdentityCache, OneAuth, Office Identity, and Licensing folders
4. **Clears Outlook AutoDiscover caches** - Removes both filesystem and registry AutoDiscover data
5. **Removes Outlook profiles** - Forces fresh profile creation on next start (optional via parameter)
6. **Purges Windows Credentials** - Removes matching credentials from Windows Credential Manager
7. **Shows dsregcmd join state** - Displays Azure AD/Workplace/Domain join status (read-only)

**Important:** Does NOT touch local AD domain join.

### Prerequisites

- **Windows 10/11**
- **PowerShell 5.1** or later
- **Administrator privileges** (required)

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `CredentialPatterns` | String[] | No | See below | Strings/regex fragments to match Windows Credentials for deletion |
| `SkipOutlookProfiles` | Switch | No | False | If set, Outlook profiles are NOT removed |

**Default CredentialPatterns:**
```powershell
@('tenant','office','outlook','oneauth','login.microsoftonline','azuread')
```

### Process Termination

The script automatically stops these processes before cleanup:
- Office applications: `outlook`, `winword`, `excel`, `powerpnt`, `onenote`, `onenotem`, `onenoteim`
- Microsoft Teams: `teams`, `ms-teams`, `MSTeams`
- Other: `onedrive`, `identityhelper`, `webaccountmanager`, `Microsoft.AAD.BrokerPlugin`, `RuntimeBroker`

### Registry Keys Modified

#### MDM Auto-Enrollment (Disabled)
```
HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM
  └─ AutoEnrollMDM = 0 (DWord)
```

#### Outlook AutoDiscover (Cleared)
```
HKCU:\Software\Microsoft\Office\16.0\Outlook\AutoDiscover
  └─ (entire key removed)
```

#### Outlook Profiles (Removed, unless -SkipOutlookProfiles)
```
HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles
  └─ (entire key removed)
```

### Folders Cleared

| Path | Purpose |
|------|---------|
| `%LOCALAPPDATA%\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy` | AAD Broker cache (Settings folder preserved) |
| `%LOCALAPPDATA%\Microsoft\IdentityCache` | Identity cache |
| `%LOCALAPPDATA%\Microsoft\OneAuth` | OneAuth tokens |
| `%LOCALAPPDATA%\Microsoft\Office\16.0\Identity` | Office identity data |
| `%LOCALAPPDATA%\Microsoft\Office\16.0\Licensing` | Office licensing cache |
| `%LOCALAPPDATA%\Microsoft\Outlook\Autodiscover` | Outlook AutoDiscover file cache |

### Credential Manager Cleanup

The script uses `cmdkey` to:
1. List all Windows Credentials
2. Match Target names against `CredentialPatterns`
3. Delete matching credentials using `cmdkey /delete:`

**Matching is case-insensitive and uses regex escape.**

### Device Join Status Display

After cleanup, the script displays (read-only):
- `AzureAdJoined` - Azure AD join status
- `WorkplaceJoined` - Workplace join status  
- `DomainJoined` - Domain join status

Uses `dsregcmd /status` command.

### Output

The script provides console output with status indicators:
- `[OK]` - Action completed successfully
- `[SKIP]` - Item not found, action skipped
- `[WARN]` - Warning message

### Post-Cleanup Required Action

**You MUST restart the PC after running this script.**

Final message:
```
=== Cleanup complete. Please RESTART the PC now. ===
```

### Use Cases

- **Tenant-to-tenant migration** - Clean old tenant identity before joining new tenant
- **Reset M365 sign-in** - Clear corrupted identity cache
- **Remove MDM prompts** - Stop persistent device management enrollment prompts
- **Fresh Outlook profile** - Force new profile after email migration
- **Credential cleanup** - Remove stored credentials from old tenant

### Error Handling

- **Requires elevation** - Script exits with error if not run as Administrator
- **Process termination** - Uses `-ErrorAction SilentlyContinue` to handle missing processes
- **Folder removal** - Gracefully handles missing folders
- **Credential deletion** - Continues on individual credential deletion failures (shows WARN)

### Important Notes

1. **Restart Required** - Changes take full effect only after restart
2. **Domain Join Preserved** - Does NOT unjoin from Active Directory domain
3. **Fresh Outlook Profile** - User will need to reconfigure Outlook (unless `-SkipOutlookProfiles`)
4. **Credential Patterns** - Customize patterns to match your specific tenant/environment

### License

MIT License - See LICENSE file in repository root

Copyright (c) 2026 Sudeep Gyawali
