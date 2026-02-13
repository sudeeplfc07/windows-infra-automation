# Browser-Link

PowerShell scripts and batch wrappers for creating and removing browser shortcuts with persistent icons.

## Overview

Creates Start Menu and Public Desktop shortcuts that open URLs in Microsoft Edge with persistent custom icons. Falls back to default browser if Edge is not found. Supports both .lnk (preferred) and .url (fallback) shortcut formats.

## Scripts Included

### PowerShell Scripts

- **InstallApp.ps1** - Creates browser shortcuts with persistent icons
- **UninstallApp.ps1** - Removes browser shortcuts

### Batch Wrappers

- **install.cmd** - Batch wrapper for InstallApp.ps1 with logging
- **uninstall.cmd** - Batch wrapper for UninstallApp.ps1 with logging

## Prerequisites

- **Windows 10/11**
- **PowerShell 5.1** or later
- **Microsoft Edge** (preferred, but optional unless `-StrictEdge` is used)
- **.ico file** for custom icon

---

## InstallApp.ps1

### Description

Creates Start Menu and Public Desktop shortcuts that open a URL in Microsoft Edge (app window or new window mode). Falls back to default browser via `explorer.exe` if Edge isn't found.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Name` | String | Yes | - | Display name for the shortcut |
| `Url` | String | Yes | - | URL to open (e.g., "https://example.com") |
| `IconLocation` | String | Yes | - | Path to .ico file (staging location) |
| `UseAppWindow` | Switch | No | False | Opens URL in Edge app window mode (no browser UI) |
| `StrictEdge` | Switch | No | False | Fail if Edge not found (no fallback to default browser) |

**Note:** Script supports `-WhatIf` and `-Confirm` (ShouldProcessSupport).

#### Verbose Output
```powershell
.\InstallApp.ps1 `
    -Name "Application" `
    -Url "https://app.example.com" `
    -IconLocation ".\app.ico" `
    -Verbose
```

### Edge Detection

The script searches for Microsoft Edge in this order:

1. **Command lookup** - `Get-Command 'msedge.exe'`
2. **App Paths registry** - `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppPaths\msedge.exe`
3. **Uninstall registry** - Searches for "Microsoft Edge" (excluding WebView) in uninstall keys
4. **Hardcoded paths** - `Program Files\Microsoft\Edge\Application\msedge.exe`

### Edge Launch Modes

#### App Window Mode (`-UseAppWindow`)
```
msedge.exe --app=https://example.com
```
Opens as standalone app window (no browser UI - no address bar, no tabs)

#### New Window Mode (Default)
```
msedge.exe --new-window https://example.com
```
Opens in new browser window with full UI

### Fallback Behavior

If Edge not found and `-StrictEdge` not specified:
```
explorer.exe https://example.com
```
Opens URL in system default browser.

### Icon Persistence

Icons are copied to persistent location to survive cache cleanup:
```
%ProgramData%\GenericApp\GenericApp.ico
```

This ensures icons remain visible even after Windows updates or cache clearing.

### Shortcut Locations

#### Start Menu (All Users)
```
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\{Name}.lnk
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\{Name}.url
```

#### Desktop (Public)
```
C:\Users\Public\Desktop\{Name}.lnk
C:\Users\Public\Desktop\{Name}.url
```

### Shortcut Creation Logic

1. **Attempt .lnk creation** (preferred)
   - Creates `{Name}.lnk` in Start Menu
   - Creates `{Name}.lnk` on Public Desktop
   - Uses WScript.Shell COM object

2. **Fallback to .url** (if .lnk fails)
   - Creates `{Name}.url` in Start Menu
   - Creates `{Name}.url` on Public Desktop
   - Uses INI-style format

### Logging

All operations logged to:
```
%ProgramData%\GenericApp\InstallApp_yyyyMMdd_HHmmss.log
```

Log includes PowerShell transcript with verbose output.

### Exit Codes

- `0` - Success (shortcuts created)
- `1` - Failure (no shortcuts created)

### Error Handling

- **Icon not found** - Proceeds without icon (shows warning)
- **Edge not found** - Falls back to default browser (unless `-StrictEdge`)
- **Strict Edge failure** - Throws error if Edge required but not found
- **.lnk creation fails** - Automatically falls back to .url format
- **Both formats fail** - Exits with error code 1

---

## UninstallApp.ps1

### Description

Removes browser shortcuts created by InstallApp.ps1 from Start Menu and Public Desktop.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Name` | String | Yes | - | Display name of shortcuts to remove (must match install name) |

### Usage
```powershell
.\UninstallApp.ps1 -Name "Salesforce CRM"
```

### Shortcuts Removed

The script removes (if they exist):
```
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\{Name}.lnk
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\{Name}.url
C:\Users\Public\Desktop\{Name}.lnk
C:\Users\Public\Desktop\{Name}.url
```

### Logging

All operations logged to:
```
%ProgramData%\GenericApp\UninstallApp_yyyyMMdd_HHmmss.log
```

### Exit Codes

Always exits with `0` (silent removal - no error if shortcuts don't exist).

---

## Batch Wrappers

### install.cmd

Batch wrapper that calls InstallApp.ps1 with preconfigured values.

#### Configuration Variables (Edit These)
```batch
set "APPNAME=My Web App"
set "APPURL=https://example.com"
set "ICONFILE=MyWebApp.ico"
```

**Important:** `ICONFILE` must be .ico format and located in same directory as install.cmd.

#### Usage

1. Edit configuration variables in install.cmd
2. Place .ico file in same directory as install.cmd
3. Run from command prompt or Intune:
```
   install.cmd
```

#### Logging

Creates log file:
```
%ProgramData%\GenericApp\Install_yyyyMMdd_HHmmss.log
```

#### PowerShell Call
```batch
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\InstallApp.ps1" ^
  -Name "%APPNAME%" -Url "%APPURL%" -IconLocation "%CD%\%ICONFILE%" -UseAppWindow -Verbose
```

**Note:** Uses `-UseAppWindow` by default (opens as app window).

### uninstall.cmd

Batch wrapper that calls UninstallApp.ps1 with preconfigured app name.

#### Configuration Variable (Edit This)
```batch
set "APPNAME=My Web App"
```

**Important:** Must match the `APPNAME` used during installation.

#### Usage

1. Edit `APPNAME` to match install value
2. Run from command prompt or Intune:
```
   uninstall.cmd
```

#### Logging

Creates log file:
```
%ProgramData%\GenericApp\Uninstall_yyyyMMdd_HHmmss.log
```

---

## Deployment Scenarios

### Intune Win32 App Deployment

#### Package Contents
```
MyWebApp.intunewin
├── InstallApp.ps1
├── UninstallApp.ps1
├── install.cmd
├── uninstall.cmd
└── MyWebApp.ico
```

#### Install Command
```
install.cmd
```

#### Uninstall Command
```
uninstall.cmd
```

#### Detection Rule (File)
```
Path: C:\ProgramData\Microsoft\Windows\Start Menu\Programs
File: My Web App.lnk
Detection: File or folder exists
```

#### Detection Rule (Registry)
Create registry marker in install.cmd (optional):
```batch
reg add "HKLM\SOFTWARE\Company\Apps" /v "MyWebApp" /t REG_SZ /d "Installed" /f
```

### Manual Deployment
```powershell
# 1. Copy files to target location
Copy-Item -Path "C:\Source\*" -Destination "C:\Deploy\MyApp" -Recurse

# 2. Run installation
cd "C:\Deploy\MyApp"
.\install.cmd
```

---

## File Structure
```
Browser-Link/
├── InstallApp.ps1          # Main installation script
├── UninstallApp.ps1        # Main removal script
├── install.cmd             # Batch wrapper for install
├── uninstall.cmd           # Batch wrapper for uninstall
└── README.md               # This file

Required for deployment:
├── {YourApp}.ico           # Custom icon file
```

---

Each install.cmd configured for its specific app.

---

## Icon Requirements

- **Format:** .ico file (required)
- **Recommended Size:** 256x256 pixels
- **Bit Depth:** 32-bit with alpha channel
- **Location:** Same directory as install.cmd

### Creating Icons

From PNG/JPG:
1. Use online converter (PNG to ICO)
2. Or use tools like RealWorld Icon Editor
3. Ensure 256x256 resolution

### Icon Persistence

Icons are automatically copied to:
```
%ProgramData%\GenericApp\GenericApp.ico
```

This ensures persistence across:
- Windows updates
- User profile cleanups
- Cache clearing operations

---

## Troubleshooting

### Icon Not Displaying

**Cause:** Icon file not found or invalid format

**Solution:**
1. Verify .ico file exists in script directory
2. Check icon file is valid .ico format (not renamed .png)
3. Clear icon cache:
```
   ie4uinit.exe -show
```
4. Restart Windows Explorer:
```powershell
   Stop-Process -Name explorer -Force
```

### Edge Not Found

**Cause:** Edge not installed or not detected

**Solution 1:** Install Microsoft Edge

**Solution 2:** Use fallback (remove `-StrictEdge`)
- Script will use default browser via `explorer.exe`

**Solution 3:** Check Edge installation
```powershell
Get-Command msedge.exe
```

### Shortcut Opens Wrong Browser

**Cause:** Edge not detected, falling back to default browser

**Solution:** 
1. Ensure Edge is installed
2. Use `-StrictEdge` to fail if Edge not found
3. Or accept default browser behavior

### Shortcut Not Created

**Cause:** Permissions issue or script error

**Solution:**
1. Check log file in `%ProgramData%\GenericApp\`
2. Ensure running with sufficient permissions
3. Verify Start Menu path is writable
4. Check for existing shortcuts with same name

---

## Logging

All operations create detailed logs in:
```
%ProgramData%\GenericApp\
├── InstallApp_yyyyMMdd_HHmmss.log
├── UninstallApp_yyyyMMdd_HHmmss.log
├── Install_yyyyMMdd_HHmmss.log         (from install.cmd)
├── Uninstall_yyyyMMdd_HHmmss.log       (from uninstall.cmd)
└── GenericApp.ico                       (persisted icon)
```

### Log Contents

- Timestamp of operations
- Working directory
- PowerShell transcript (verbose output)
- Warnings and errors
- Exit codes

---

## Best Practices

1. **Test Before Deployment**
   - Test in isolated environment
   - Verify icon displays correctly
   - Check Edge detection works

2. **Icon Management**
   - Always use .ico format (not renamed PNG)
   - Include icon file in deployment package
   - Verify icon file path in install.cmd

3. **Naming Consistency**
   - Use same `APPNAME` in install.cmd and uninstall.cmd
   - Use descriptive names (e.g., "Salesforce CRM" not "App1")
   - Avoid special characters in names

4. **Intune Deployment**
   - Package all files in .intunewin
   - Test install/uninstall locally first
   - Use file-based detection rule
   - Set deployment as Available or Required

5. **Documentation**
   - Document icon source
   - Record exact APPNAME used
   - Keep copy of .ico file

---

## License

MIT License - See LICENSE file in repository root

Copyright (c) 2026 Sudeep Gyawali
