# Export & Upload Windows Autopilot Hardware Hash

This script collects the local device’s **hardware hash (HWID)** using the Windows MDM Bridge and can:

- **Write a local CSV** for intune import.
- **Upload directly to Windows Autopilot** via Microsoft Graph.
- Do **both** in a single run.

## What the script actually does (in order)

1. Ensures the **Microsoft.Graph.Authentication** module is installed/imported.
2. Gathers device info (Manufacturer/Model/Serial, etc.).
3. Reads the **hardware hash** from `root\cimv2\mdm\dmmap: MDM_DevDetail_Ext01.DeviceHardwareData`.  
4. **If `-AlsoWriteCsv` is set:** writes a CSV row to `%TEMP%\AutopilotUploadLogs`.
5. Attempts **app‑only** Graph authentication using either **client secret** or **certificate**.
6. If authenticated, **POSTs** to `deviceManagement/importedWindowsAutopilotDeviceIdentities` with:
   - `serialNumber`, `hardwareIdentifier`, optional `groupTag`, optional `productKey`.
7. Retries the POST on common transient errors (HTTP 429/502/503/504).
8. Logs everything to `%TEMP%\AutopilotUploadLogs`.

---

## Modes (choose one)

### 1) Local **CSV‑only** (no upload)
- Run with `-AlsoWriteCsv`.
- **Do not** provide working Graph credentials (leave placeholders as‑is, or omit secret/cert).
- The script **will still exit non‑zero** after CSV is written because Graph auth fails by design; this is expected for CSV‑only use.

**Example**
powershell
# Run as Administrator
.\Export-HardwareHash.ps1 -AlsoWriteCsv -Verbose
# CSV is written; expect a non-zero exit code due to skipped upload

## License
Licensed under the MIT License. See the [LICENSE](../LICENSE) file in the repo root for details.
