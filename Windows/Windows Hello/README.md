# Disable Windows Hello / Windows Hello for Business (and optionally remove existing PIN)

This script turns **off** Windows Hello and Windows Hello for Business (WHfB) on a device, and can also remove any existing PIN/NGC data so it can’t be used again.

## What it does
- Sets device policies to disable:
  - **Use Windows Hello for Business** → Disabled (`PassportForWork\Enabled=0`).  
  - **Turn on convenience PIN sign-in** → Disabled (`Windows\System\AllowDomainPINLogon=0`).  
  - **Allow the use of biometrics** → Disabled (`Biometrics\Enabled=0`).  
  - **AllowSignInOptions** → `0` to hide Hello options in Settings.  
- (Optional) Removes the **NGC** folder that stores PIN/keys.
- Stops/restarts Microsoft **Passport** services around NGC operations.

Policy references:  
	– Windows Hello for Business policy settings (MS Learn) [1](https://learn.microsoft.com/en-us/windows/security/identity-protection/hello-for-business/policy-settings)  
	– Disable Windows Hello using Group Policy (article) [2](https://www.prajwaldesai.com/disable-windows-hello-using-group-policy/)  
	– Biometrics policy/registry mapping (tutorial) [3](https://www.tenforums.com/tutorials/117987-enable-disable-windows-hello-biometrics-windows-10-a.html)  
	– Convenience PIN policy (AllowDomainPINLogon) [4](https://www.tenforums.com/tutorials/80520-enable-disable-domain-users-sign-pin-windows-10-a.html)  
	– Hiding Sign‑in options via PolicyManager (examples/guides) [5](https://lansafe.co.uk/disable-windows-hello/)[6](https://community.spiceworks.com/t/disable-login-with-pin-code-to-all-users-windows-11-pro/959880)

## Files
- `Disable-WindowsHello.ps1`

## Requirements
- Windows 10/11
- PowerShell 5.1+
- Run **as Administrator** (policy keys + NGC removal require elevation)

## Parameters
| Name | Type | Default | Description |
|------|------|---------|-------------|
| `-SkipNgcRemoval` | switch | Off | If set, **only** policy disablement is applied; NGC is left intact. |
| `-NoBackup` | switch | Off | When removing NGC, skip the backup/rename step and delete directly. |


### Registry Policies Set

#### 1. Windows Hello for Business (WHfB)
```
HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork
  └─ Enabled = 0 (DWord)
```
**Equivalent GPO:** Computer Configuration > Administrative Templates > Windows Components > Windows Hello for Business > "Use Windows Hello for Business" = Disabled

#### 2. Convenience PIN Sign-in
```
HKLM:\SOFTWARE\Policies\Microsoft\Windows\System
  └─ AllowDomainPINLogon = 0 (DWord)
```
**Equivalent GPO:** Computer Configuration > Administrative Templates > System > Logon > "Turn on convenience PIN sign-in" = Disabled

#### 3. Biometrics
```
HKLM:\SOFTWARE\Policies\Microsoft\Biometrics
  └─ Enabled = 0 (DWord)
```
**Equivalent GPO:** Computer Configuration > Administrative Templates > Windows Components > Biometrics > "Allow the use of biometrics" = Disabled

#### 4. Sign-in Options UI
```
HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowSignInOptions
  └─ value = 0 (DWord)
```
Hides Hello options in Settings app.

### NGC Folder Handling

**Location:** `C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\NGC`

#### Services Managed
- `NgcCtnrSvc` - Microsoft Passport Container
- `NgcSvc` - Microsoft Passport

#### Ownership & Permissions
Script uses:
- `takeown.exe /F "NGC" /R /D Y` - Take ownership recursively
- `icacls.exe "NGC" /grant Administrators:F /T /C` - Grant full control

#### Backup Process (Default)
If NGC folder exists and `-NoBackup` not specified:
1. Attempts to rename NGC folder to `NGC.bak_{timestamp}`
2. If rename fails, proceeds with direct deletion (shows warning)

**Backup filename format:** `NGC.bak_yyyyMMdd_HHmmss`

### Exit Codes

- `0` - Success
- `1` - Failed to remove NGC container
- Exception - Not running as Administrator

### Error Handling

- **Admin Check** - Throws error if not elevated
- **Service Operations** - Uses `-ErrorAction SilentlyContinue` for services that may not exist
- **NGC Removal** - Stops execution with exit code 1 if removal fails

### Console Output

Status messages:
```
=== Disabling Windows Hello / WHfB (and optionally removing existing PIN) ===
[OK] Policies set to disable WHfB, convenience PIN, biometrics, and sign-in options.
[OK] Existing Windows Hello container removed.
[OK] No NGC folder found—nothing to remove.
[SKIP] NGC removal skipped (policies only).

=== Completed. Reboot is recommended to fully enforce sign-in policy changes. ===
```

### Post-Execution Required Action

**Reboot recommended** to fully enforce sign-in policy changes.

Final message displays:
```
=== Completed. Reboot is recommended to fully enforce sign-in policy changes. ===
```

### Use Cases

- **Corporate policy enforcement** - Password-only authentication mandate
- **Regulatory compliance** - No biometric data storage requirements
- **Troubleshooting** - Reset corrupted Hello configuration

### Policy Source References

The script documentation includes references to:
- Windows Hello for Business policy settings (Microsoft Learn)
- Disable Windows Hello using Group Policy (P. Desai)
- Enable/Disable Biometrics via registry (TenForums)
- AllowDomainPINLogon policy mapping (TenForums)

### Important Notes

1. **Reboot Required** - Policies take full effect after restart
2. **NGC Backup** - Default behavior backs up NGC folder before deletion
3. **Service Restart** - Passport services restarted after NGC removal (ensures system baseline)
4. **No User Impact** - If NGC removed, users must use password for sign-in

### License

MIT License - See LICENSE file in repository root

Copyright (c) 2026 Sudeep Gyawali
