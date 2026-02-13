# Windows Automation Scripts

A collection of PowerShell scripts and guides for day‑to‑day Windows and Microsoft 365 administration.

## Repository Structure

- **[Browser-Link](Browser-Link/README.md)**  
  Create URL application shortcuts (.lnk with Edge app window, .url fallback) with icon persistence. Includes install/uninstall scripts and usage.

- **[Hardwarehash Export](Hardwarehash%20Export/README.md)**  
  Export Windows Autopilot hardware hash (HWID). Supports local CSV output and direct upload to Windows Autopilot via Microsoft Graph (app‑only).

- **[Windows](Windows/README.md)**  
  Additional Windows scripts (e.g., default apps removal, Windows Hello disable/remove, profile cleanup), each with its own README.

> Each folder contains a `README.md` describing usage, parameters, outputs, and any caveats.

---

## Quick Start
   bash
# 1) Clone the repo
git clone https://github.com/<your-username>/<repo-name>.git
cd <repo-name>

# 2) Explore folders
# Browser-Link          -> scripts to create/remove URL app shortcuts
# Hardwarehash Export   -> Autopilot HWID export (CSV and/or upload)
# Windows               -> extra Windows scripts

# 3) Run scripts from an elevated PowerShell when noted in the folder README

## License
Licensed under the MIT License. See the [LICENSE](../LICENSE) file in the repo root for details.
