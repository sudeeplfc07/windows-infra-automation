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

## Usage
 powershell
# Disable Hello and remove any existing PIN/keys (recommended)
.\Disable-WindowsHello.ps1 -Verbose

# Disable Hello policies only (leave NGC intact)
.\Disable-WindowsHello.ps1 -SkipNgcRemoval -Verbose

## keyseys

HKLM\SOFTWARE\Policies\Microsoft\PassportForWork\Enabled=0 maps to Use Windows Hello for Business – Disabled. [learn.microsoft.com], [prajwaldesai.com]
HKLM\SOFTWARE\Policies\Microsoft\Windows\System\AllowDomainPINLogon=0 disables legacy convenience PIN sign‑in for domain users. [tenforums.com]
HKLM\SOFTWARE\Policies\Microsoft\Biometrics\Enabled=0 disables biometrics. [tenforums.com]
HKLM\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowSignInOptions\value=0 hides Hello sign‑in options in Settings on many builds.

## License
Licensed under the MIT License. See the [LICENSE](../LICENSE) file in the repo root for details.
