# Default App Removal

PowerShell script for removing OEM bloatware and Microsoft consumer applications from Windows. Detection and Removal script run from Intune.

### What It Does

Centralized removal of unwanted applications including HP Wolf Security stack, HP/Poly software, and Microsoft consumer apps. Uses MSI GUIDs, AppX packages, and display name matching for comprehensive cleanup.

### Target Applications

#### HP Wolf Security Stack
- HP Wolf Security
- HP Wolf Security - Console
- HP Security Update Service

#### HP/Poly Applications
- HP Notifications
- HP System Default Settings
- HP Sure Recover
- HP Sure Run Module
- HP Documentation
- HP Support Assistant
- HP PC Hardware Diagnostics
- HP Desktop Support Utilities
- HP Privacy Settings
- HP Camera Pro
- myHP
- Poly Camera Pro Compatibility Add-on
- Poly Lens

#### Microsoft Consumer Apps
- Gaming apps (Xbox, Gaming App, etc.)
- Bing apps (News, Weather, Sports, Finance)
- Entertainment (Solitaire, Candy Crush, Disney, Zune)
- Office Hub, Skype, Get Help, Get Started, People

### Prerequisites

- **Windows 10/11**
- **PowerShell 5.1** or later
- **Administrator privileges** (required)

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `LogPath` | String | No | `C:\ProgramData\Intune\Logs\Uninstallapps-Full.log` | Log file path |
| `MsiRetrySeconds` | Int | No | 60 | Wait time when MSI installer is busy (error 1618) |
| `SkipHPPoly` | Switch | No | False | Skip HP/Poly application removal |
| `SkipConsumerApps` | Switch | No | False | Skip Microsoft consumer app removal |
| `NotifyAlways` | Switch | No | False | Always show restart notification to user |


#### Intune Deployment
```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Remove-DefaultApps.ps1
```

### Customization

Edit the **INCLUDE LISTS** section at the top of the script to add/remove targets:
```powershell
# ===== INCLUDE LISTS (EDIT THESE ARRAYS) =====

# A) HP Wolf stack GUIDs
$WolfGuids = @(
    '{BC18E78B-DD6C-A3C8-A079-D001E021308A}',
    '{E7420E72-BFE1-4E06-9202-199B629E8149}'
)

# B) MSI GUIDs for HP/Poly targets
$TargetedMsiGuids = @(
    '{19F557DE-662A-4FEA-B635-1CACD56CC483}',
    # Add more GUIDs here
)

# C) MSI removal by DisplayName
$RemoveByName = @(
    'HP Wolf Security',
    # Add more names here
)

# D) HP Appx/MSIX families
$HpAppxFamilies = @(
    'AD2F1837.HPSupportAssistant',
    # Add more package families here
)

# E) Microsoft consumer Appx families
$ConsumerAppxFamilies = @(
    'Microsoft.GamingApp',
    # Add more package families here
)
```

### Removal Methods

#### 1. MSI Removal (GUIDs)
Uses `msiexec.exe /x {GUID} /qn /norestart`

#### 2. MSI Removal (Display Name)
Searches registry uninstall keys for matching DisplayName, then uninstalls

#### 3. AppX Package Removal
Three-stage process:
- **AllUsers removal** - Removes for all users
- **Per-user removal** - Removes from individual user SIDs (for stubborn packages like myHP)
- **Deprovisioning** - Prevents installation for new user profiles

#### 4. Edge PWA Removal
Scans Edge user profiles and removes Poly/Camera-related Progressive Web Apps

#### 5. Service Cleanup
Stops and deletes lingering services

#### 6. Folder Cleanup
Removes installation directories

### Process & Service Termination

The script stops these before removal:
- **Processes:** `HPNotifications`, `HpSfuService64`, `hpsvcsscan`, `hpqwmiex`, `HPCommRecovery`, `HPWolf`, `HPConnectionOptimizer`, `HPClientSecurityManager`, `PolyLens`
- **Services:** HP Wolf-related, HP Touchpoint, Sure Run services

### Special Handling

#### Error 1618 (Installer Busy)
When MSI returns error 1618 (another installation in progress):
- Script waits `$MsiRetrySeconds` (default: 60 seconds)
- Automatically retries the uninstallation

#### HP Documentation
Runs special uninstall script if present:
```
C:\Program Files\HP\Documentation\Doc_Uninstall.cmd
```

#### Game DVR Disable
For non-removable Xbox components, disables via policy:
- `HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowgameDVR = 0`
- Per-user Game Bar settings disabled

#### HCO Orphan Key
Removes orphaned registry key if HP Connection Optimizer files are gone

### Exit Codes

The script tracks changes and reboot requirements:
- Sets `$script:AnyRebootNeeded` if MSI returns 3010 (reboot required)
- Sets `$script:AnyChange` if any successful removal occurred

### User Notification

If changes were made, notifies user via:
```
msg.exe * "Restart required to complete removal of unwanted applications."
```

**Note:** Script does NOT force restart. User can restart at their convenience.

### Logging

All actions logged to file with timestamp format:
```
yyyy-MM-dd HH:mm:ss    Message
```

Log includes:
- MSI uninstall commands and exit codes
- AppX removal status
- Service/process termination
- Folder cleanup results
- Errors and warnings

### Registry Keys Modified

Game DVR policies (when consumer apps removed):
```
HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR
  └─ AllowgameDVR = 0

Per-User:
HKU:\{SID}\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR
  └─ AppCaptureEnabled = 0
HKU:\{SID}\System\GameConfigStore
  └─ GameDVR_Enabled = 0
```

### Folders Removed

HP/Poly folders (if present):
- `C:\Program Files (x86)\HP\HP Notifications`
- `C:\Program Files (x86)\HP\HP System Default Settings`
- `C:\Program Files\HP\Documentation`
- `C:\Program Files (x86)\Poly\Lens`
- `C:\Program Files\Poly\Lens`

### Error Handling

- Uses `$ErrorActionPreference = 'Stop'` for script-level errors
- Individual operations use `-ErrorAction SilentlyContinue` to continue on failures
- Logs all errors with context

### Best Practices

1. **Test in isolated environment** before production deployment
2. **Review INCLUDE LISTS** to match your organization's needs
3. **Create system restore point** before running (optional)
4. **Monitor log file** after execution for any failures
5. **Restart PC** after script completes

### Use Cases

- **Corporate image cleanup** - Remove bloatware from new PCs
- **Intune deployment** - Automated removal during provisioning
- **End-user experience** - Streamline Start Menu and reduce clutter
- **Security compliance** - Remove unapproved software
- **Performance optimization** - Reduce background processes

### License

MIT License - See LICENSE file in repository root

Copyright (c) 2026 Sudeep Gyawali
