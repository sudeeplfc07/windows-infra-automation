# Hardwarehash Export

PowerShell script for collecting and uploading Windows Autopilot hardware hash to Microsoft Intune via Microsoft Graph API.

## Overview

This script collects the hardware hash from the local device using MDM Bridge and uploads it directly to Windows Autopilot using app-only authentication. Optionally exports to CSV format.

## Script: AutopilotUpload-AppOnly.ps1

### What It Does

- Installs/imports `Microsoft.Graph.Authentication` module only
- Collects local hardware hash via MDM Bridge (requires elevation)
- Authenticates using app-only (Client Secret or Certificate)
- POSTs to Autopilot import API with optional GroupTag
- No user pre-assignment (devices remain unassigned)
- Optional CSV export of serial number and hardware hash
- Auto-relaunches under PowerShell 7 if available (falls back to PowerShell 5.1)
- Retry logic for transient errors (429, 502, 503, 504)

### Prerequisites

- **Windows 10/11** with MDM Bridge
- **PowerShell 5.1** or later (PowerShell 7 preferred)
- **Elevated PowerShell** (Administrator privileges required)
- **Microsoft.Graph.Authentication module** (auto-installed if missing)
- **Azure AD App Registration** with app-only permissions:
  - `DeviceManagementServiceConfig.ReadWrite.All` (admin consent required)

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `TenantId` | String | Yes | Your Azure AD tenant ID |
| `ClientId` | String | Yes | Azure AD app registration client ID |
| `ClientSecret` | String | Yes* | Client secret for app-only auth (*or use CertThumbprint) |
| `CertThumbprint` | String | Yes* | Certificate thumbprint for app-only auth (*or use ClientSecret) |
| `GroupTag` | String | No | Group tag for device categorization in Autopilot |
| `ProductKey` | String | No | Windows product key (optional) |
| `AlsoWriteCsv` | Switch | No | Also export hardware hash to CSV file |

**Note:** Either `ClientSecret` or `CertThumbprint` must be provided for app-only authentication.

### Usage

#### Using Client Secret
```powershell
.\AutopilotUpload-AppOnly.ps1 `
    -TenantId "12345678-1234-1234-1234-123456789012" `
    -ClientId "87654321-4321-4321-4321-210987654321" `
    -ClientSecret "your-client-secret" `
    -GroupTag "Corporate-Laptops"
```

#### Using Certificate
```powershell
.\AutopilotUpload-AppOnly.ps1 `
    -TenantId "12345678-1234-1234-1234-123456789012" `
    -ClientId "87654321-4321-4321-4321-210987654321" `
    -CertThumbprint "A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6E7F8A9B0" `
    -GroupTag "Executive-Devices"
```

#### With CSV Export
```powershell
.\AutopilotUpload-AppOnly.ps1 `
    -TenantId "12345678-1234-1234-1234-123456789012" `
    -ClientId "87654321-4321-4321-4321-210987654321" `
    -ClientSecret "your-client-secret" `
    -GroupTag "IT-Department" `
    -AlsoWriteCsv
```

#### With Product Key
```powershell
.\AutopilotUpload-AppOnly.ps1 `
    -TenantId "12345678-1234-1234-1234-123456789012" `
    -ClientId "87654321-4321-4321-4321-210987654321" `
    -ClientSecret "your-client-secret" `
    -ProductKey "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
```

### Output Files

All output files are saved to: `%TEMP%\AutopilotUploadLogs\`

#### Log File
- **Format:** `AutopilotUpload_AppOnly-{ComputerName}-{Timestamp}.log`
- **Contains:** Detailed execution log with timestamps and status levels (INFO/WARN/ERROR)

#### CSV File (when using -AlsoWriteCsv)
- **Format:** `AutopilotHashes-{ComputerName}-{Timestamp}.csv`
- **Columns:**
  - Device Serial Number
  - Windows Product ID (empty)
  - Hardware Hash
  - Group Tag
  - Assigned User (empty - no pre-assignment)

### How It Works

1. **PowerShell 7 Check:** Auto-relaunches under PowerShell 7 if available (better performance)
2. **Module Installation:** Installs/imports Microsoft.Graph.Authentication module
3. **Hardware Collection:** 
   - Collects device information (computer name, manufacturer, model, serial number, OS)
   - Retrieves hardware hash via MDM Bridge (WMI namespace: root\cimv2\mdm\dmmap)
4. **CSV Export (Optional):** Writes hardware hash to CSV if `-AlsoWriteCsv` specified
5. **App-Only Authentication:** 
   - Connects to Microsoft Graph using client secret or certificate
   - Verifies app-only context is established
6. **Autopilot Import:**
   - POSTs device to `deviceManagement/importedWindowsAutopilotDeviceIdentities` endpoint
   - Includes serial number, hardware hash, group tag, and product key
   - Does NOT include assigned user (devices remain unassigned)
   - Retry logic handles transient errors (up to 5 retries with exponential backoff)
7. **Cleanup:** Disconnects from Microsoft Graph

### Error Handling

The script includes comprehensive error handling:

- **Retry Logic:** Automatically retries on transient errors (HTTP 429, 502, 503, 504)
- **Exponential Backoff:** Delays increase from 1s to 15s between retries
- **Exit Codes:**
  - `0` - Success
  - `12` - App-only authentication failed
  - `21` - Hardware hash collection failed
  - `30` - Autopilot import failed

### Troubleshooting

#### "Hardware hash is empty"
- **Cause:** Script not running elevated or MDM Bridge unavailable
- **Solution:** Right-click PowerShell → Run as Administrator
- **Verification:** 
```powershell
  Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_DevDetail_Ext01'
```

#### "App-only context not established"
- **Cause:** Authentication failure (invalid credentials or missing permissions)
- **Solution:** 
  - Verify TenantId and ClientId are correct
  - Check ClientSecret hasn't expired
  - Ensure `DeviceManagementServiceConfig.ReadWrite.All` has admin consent
  - Check in Azure AD → App registrations → API permissions → Status column

#### "Graph import failed"
- **Cause:** API error or device already enrolled
- **Solution:** Check log file in `%TEMP%\AutopilotUploadLogs\` for detailed error message
- **Common Causes:**
  - Device already exists in Autopilot
  - Invalid hardware hash
  - Insufficient API permissions

### Azure AD App Setup

1. **Create App Registration:**
   - Azure Portal → Azure Active Directory → App registrations → New registration
   - Name: "Autopilot HWID Upload"
   - Supported account types: Single tenant

2. **Configure API Permissions:**
   - API permissions → Add a permission → Microsoft Graph → Application permissions
   - Add: `DeviceManagementServiceConfig.ReadWrite.All`
   - Click: "Grant admin consent for [Tenant]"

3. **Create Authentication Credential:**
   
   **Option A: Client Secret**
   - Certificates & secrets → Client secrets → New client secret
   - Copy the Value (shown only once)
   
   **Option B: Certificate (More Secure)**
```powershell
   # Generate self-signed certificate
   $cert = New-SelfSignedCertificate `
       -Subject "CN=AutopilotUpload" `
       -CertStoreLocation "Cert:\CurrentUser\My" `
       -KeyExportPolicy Exportable `
       -KeySpec Signature `
       -KeyLength 2048 `
       -KeyAlgorithm RSA `
       -HashAlgorithm SHA256 `
       -NotAfter (Get-Date).AddYears(2)
   
   # Export certificate
   Export-Certificate -Cert $cert -FilePath "C:\Temp\AutopilotUpload.cer"
   
   # Get thumbprint
   $cert.Thumbprint
```
   - Upload .cer file to Azure AD app registration

### Device Information Collected

The script collects:
- Computer Name
- Manufacturer
- Model
- Serial Number
- OS Version
- OS Edition
- Hardware Hash (DeviceHardwareData from MDM Bridge)

### Security Notes

- **No User Pre-Assignment:** Script intentionally does not pre-assign users to devices
- **App-Only Authentication:** Uses application permissions (no user context required)
- **Credential Security:** Supports certificate authentication (more secure than client secret)
- **Logging:** All operations logged for audit purposes
- **No Hardcoded Secrets:** Default values are placeholders ('XXX')

### PowerShell Version Compatibility

- **PowerShell 7:** Preferred (auto-relaunches if available)
- **PowerShell 5.1:** Supported (function count limits increased automatically)
- **Windows PowerShell:** Desktop edition supported with compatibility adjustments

### License

MIT License - See LICENSE file in repository root

Copyright (c) 2026 Sudeep Gyawali
