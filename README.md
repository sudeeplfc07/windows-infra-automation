# Windows Infrastructure Automation Toolkit

PowerShell scripts for Windows endpoint management and Microsoft 365 administration.

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Maintained](https://img.shields.io/badge/Maintained-Yes-green.svg)](https://github.com/sudeeplfc07/windows-infra-automation)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

</div>

---


## Overview

Collection of PowerShell scripts for automating Windows endpoint configuration, Microsoft 365 identity management, application removal, and Windows Autopilot enrollment.

## Repository Structure

### [Browser-Link](./Browser-Link/)
Create URL application shortcuts (.lnk with Edge app window, .url fallback) with persistent icons.

**Scripts:**
- `InstallApp.ps1` - Creates browser shortcuts in Start Menu and Public Desktop
- `UninstallApp.ps1` - Removes browser shortcuts
- `install.cmd` - Batch wrapper for installation with logging
- `uninstall.cmd` - Batch wrapper for removal with logging

**Key Features:**
- Edge app window mode (opens as standalone app, no browser UI)
- Fallback to default browser if Edge not found
- Persistent icon storage in ProgramData
- Supports both .lnk and .url formats
- All users deployment (Start Menu and Public Desktop)

[Read Documentation →](./Browser-Link/README.md)

---

### [Hardwarehash Export](./Hardwarehash%20Export/)
Export Windows Autopilot hardware hash (HWID) and upload directly to Microsoft Intune via Microsoft Graph API.

**Scripts:**
- `HardwareHash_Export.ps1` - Main script for HWID collection and upload

**Key Features:**
- Collects hardware hash via MDM Bridge
- App-only authentication (Client Secret or Certificate)
- Direct upload to Autopilot via Microsoft Graph API
- Optional CSV export
- Group Tag assignment support
- Auto-relaunches under PowerShell 7 if available
- Retry logic for transient errors (429, 502, 503, 504)

[Read Documentation →](./Hardwarehash%20Export/README.md)

---

### [Windows](./Windows/)
Windows configuration, cleanup, and compliance scripts.

#### Profile & Identity Cleanup
**Script:** `CleanUP-WindowsProfile.ps1`

Cleans cached Microsoft 365 identity data and prevents auto MDM enrollment prompts.

**What It Does:**
- Disables auto MDM enrollment policy
- Clears AAD Broker, OneAuth/WAM, Office identity/licensing caches
- Clears Outlook AutoDiscover cache (filesystem + registry)
- Removes Outlook profiles (optional)
- Purges Windows Credentials by pattern matching
- Shows dsregcmd join state (read-only)

[Read Documentation →](./Windows/Profile-Identity-Cleanup/README.md)

---

#### Default App Removal
**Script:** `Uninstallapps-Full.ps1`

Removes OEM bloatware and Microsoft consumer applications.

**Target Applications:**
- HP Wolf Security stack
- HP/Poly software (Notifications, Camera Pro, Lens, Support Assistant, myHP)
- Microsoft consumer apps (Xbox, Gaming, Bing apps, Solitaire, Candy Crush, Zune)

**Removal Methods:**
- MSI uninstall (by GUID and DisplayName)
- AppX package removal (AllUsers + per-user + deprovisioning)
- Edge PWA cleanup
- Service and folder cleanup

[Read Documentation →](./Windows/Default-App-Removal/README.md)

---

#### Windows Hello Management
**Script:** `Disable-WindowsHello.ps1`

Disables Windows Hello for Business and removes existing PIN/NGC data.

**What It Does:**
- Sets registry policies to disable WHfB, convenience PIN, biometrics, and sign-in options UI
- Optionally removes NGC container (existing PIN/keys)
- Stops/restarts Passport services
- Takes ownership and removes NGC folder with optional backup

[Read Documentation →](./Windows/Windows-Hello-Management/README.md)

---

## Prerequisites

### General Requirements
- Windows 10 or Windows 11
- PowerShell 5.1 or later (PowerShell 7 preferred for some scripts)
- Administrator privileges (required for most scripts)

### Script-Specific Requirements

**Hardwarehash Export:**
- Microsoft.Graph.Authentication module (auto-installed)
- Azure AD app registration with `DeviceManagementServiceConfig.ReadWrite.All` permission
- Elevated PowerShell (for MDM Bridge access)

**Browser-Link:**
- Microsoft Edge (preferred, optional unless `-StrictEdge`)
- .ico file for custom icon

**Windows Scripts:**
- No additional requirements

## Quick Start

### Clone Repository
```bash
git clone https://github.com/sudeeplfc07/windows-infra-automation.git
cd windows-infra-automation
```

### Navigate to Script Folder
```powershell
# Browser shortcuts
cd Browser-Link

# Autopilot enrollment
cd "Hardwarehash Export"

# Windows management
cd Windows
```

### Run Scripts
```powershell
# Elevated PowerShell required for most scripts
# Right-click PowerShell → Run as Administrator

# Example: Create browser shortcut
.\InstallApp.ps1 -Name "App" -Url "https://example.com" -IconLocation ".\app.ico" -UseAppWindow

# Example: Upload Autopilot HWID
.\AutopilotUpload-AppOnly.ps1 -TenantId "xxx" -ClientId "xxx" -ClientSecret "xxx" -GroupTag "Corporate"

# Example: Clean M365 identity
.\Clean-M365Identity.ps1

# Example: Remove bloatware
.\Uninstallapps-Full.ps1

# Example: Disable Windows Hello
.\Disable-WindowsHello.ps1
```

## Documentation

Each folder contains a README.md with:
- Script descriptions and parameters
- Detailed usage examples
- Prerequisites and requirements
- Troubleshooting guidance

## Logging

Scripts create logs in their respective locations:

| Script | Log Location |
|--------|--------------|
| AutopilotUpload-AppOnly.ps1 | `%TEMP%\AutopilotUploadLogs\` |
| InstallApp.ps1 / UninstallApp.ps1 | `%ProgramData%\GenericApp\` |
| Uninstallapps-Full.ps1 | `C:\ProgramData\Intune\Logs\` (configurable) |
| Other Windows scripts | Console output only |

## Common Use Cases

### Autopilot Device Enrollment
```powershell
# Collect HWID and upload to Intune
cd "Hardwarehash Export"
.\AutopilotUpload-AppOnly.ps1 `
    -TenantId "your-tenant-id" `
    -ClientId "your-app-id" `
    -ClientSecret "your-secret" `
    -GroupTag "Corporate-Laptops"
```

### Deploy Web Application Shortcuts
```powershell
# Create Salesforce shortcut
cd Browser-Link
.\InstallApp.ps1 `
    -Name "Salesforce" `
    -Url "https://company.salesforce.com" `
    -IconLocation ".\salesforce.ico" `
    -UseAppWindow
```

### Tenant-to-Tenant Migration Cleanup
```powershell
# Clean M365 identity after migration
cd Windows
.\Clean-M365Identity.ps1
```

### Corporate Image Cleanup
```powershell
# Remove bloatware from new devices
cd Windows
.\Uninstallapps-Full.ps1
```

### HIPAA Compliance
```powershell
# Disable biometric authentication
cd Windows
.\Disable-WindowsHello.ps1
```

## Security Notes

- **No Hardcoded Credentials** - All scripts use parameters for sensitive data
- **App-Only Authentication** - Autopilot script supports Azure AD app authentication
- **Audit Logging** - All operations logged for compliance
- **Least Privilege** - Scripts request minimum required permissions
- **Error Handling** - Comprehensive error handling with graceful failures

## Exit Codes

Scripts use standard exit codes:
- `0` - Success
- `1` - General failure
- `12` - Authentication failure (Autopilot script)
- `21` - Data collection failure (Autopilot script)
- `30` - Upload failure (Autopilot script)

## Contributing

Contributions, issues, and feature requests are welcome.

1. Fork the repository
2. Create feature branch
3. Test thoroughly in isolated environment
4. Submit pull request with detailed description

## License

MIT License - See [LICENSE](./LICENSE) file for details.

Copyright (c) 2026 Sudeep Gyawali

## Author

**Sudeep Gyawali**

Network & Cloud Infrastructure Engineer specializing in:
- Windows endpoint automation and management
- Microsoft 365 & Azure cloud services
- Zero-touch device provisioning
- Enterprise infrastructure automation

**Connect:**
- [LinkedIn](https://www.linkedin.com/in/sudeep-gyawali-089524110/)
- [GitHub](https://github.com/sudeeplfc07)
- Email: sudeeplfc07@gmail.com

## Repository Information

- **Language:** PowerShell (97.2%), Batchfile (2.8%)
- **License:** MIT
- **Topics:** windows, powershell, automation, winops, intune, autopilot, m365, endpoint-management, entra-idcompliance automation, browser shortcuts, HWID collection, Windows Hello, profile cleanup, SysAdmin tools

## License
Licensed under the MIT License. See the [LICENSE](../LICENSE) file in the repo root for details.
