# Browser Link (Generic URL Shortcut)

Creates Start Menu and Public Desktop shortcuts that open a specified URL.
Prefers Microsoft Edge (app window or new window); optionally falls back to default browser.

## What it does
- Persists an icon in `%ProgramData%\GenericApp\GenericApp.ico` so the shortcut icon survives cache cleanups.
- Creates both `.lnk` shortcuts (preferred); if that fails, creates `.url` shortcuts as a fallback.
- Writes install/uninstall transcripts to `%ProgramData%\GenericApp\`.

## Files
- `InstallApp.ps1` — Creates shortcuts.
- `UninstallApp.ps1` — Removes shortcuts.
- `Install.cmd` — Wrapper for Intune / software deployment tools (sets `APPNAME`, `APPURL`, `ICONFILE`).
- `Uninstall.cmd` — Wrapper for removal; uses the same `APPNAME`.

## Requirements as tested with
- Windows 10+
- PowerShell 5.1+ 
- Admin context recommended (writes to ProgramData / Public Desktop)
- Microsoft Edge installed (unless you’re okay with fallback to default browser)

## Parameters (InstallApp.ps1)
| Name            | Type    | Required | Description |
|-----------------|---------|----------|-------------|
| `-Name`         | string  | Yes      | Display name for the shortcuts. |
| `-Url`          | string  | Yes      | Target web URL to open. |
| `-IconLocation` | string  | Yes      | Path to a `.ico` file (will be copied to ProgramData). |
| `-UseAppWindow` | switch  | No       | If set, opens Edge in app-window mode (`--app=`). Otherwise new window. |
| `-StrictEdge`   | switch  | No       | If set and Edge is not found, install fails instead of falling back to default browser. |

## Usage (manual)
```powershell
# From the folder containing the scripts and icon:
.\InstallApp.ps1 -Name "My Web App" -Url "https://example.com" -IconLocation ".\MyWebApp.ico" -UseAppWindow -Verbose
# To uninstall:
.\UninstallApp.ps1 -Name "My Web App" -Verbose

## License
Licensed under the MIT License. See the [LICENSE](../LICENSE) file in the repo root for details.
