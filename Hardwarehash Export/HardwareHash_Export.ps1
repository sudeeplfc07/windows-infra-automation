<#
  Copyright (c) 2026 Sudeep Gyawali
  Licensed under the MIT License. See the LICENSE file in the repository root.
#>
<# 

What it does:
  • Installs/imports Microsoft.Graph.Authentication module only.
  • Collects local hardware hash via MDM Bridge (elevated).
  • App-only login (Client Secret or Certificate).
  • POSTs to Autopilot import API with optional GroupTag and no user pre-assignment.
  • Optional CSV of serial + hash.
#>

[CmdletBinding()]
param(
  [string]$TenantId        = 'XXX',  # your tenant
  [string]$ClientId        = 'XXX',  # your app registration
  [string]$ClientSecret    = 'XXX',  # for app-only (secret)
  [string]$CertThumbprint  = 'xxx',  # for app-only (certificate)
  [string]$GroupTag,
  [string]$ProductKey = '',
  [switch]$AlsoWriteCsv
)

# ---------------- Auto-relaunch under PowerShell 7 (preferred) ----------------
function Restart-Under-Pwsh {
  try {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh -and $PSVersionTable.PSEdition -eq 'Desktop') {
      Write-Host "Re-launching under PowerShell 7 ($($pwsh.Source))..." -ForegroundColor Cyan
      & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @PSBoundParameters
      exit $LASTEXITCODE
    }
  } catch { }
}
Restart-Under-Pwsh

# ---------------- PS 5.1 function-cap bump (if still Desktop) ----------------
if ($PSVersionTable.PSEdition -eq 'Desktop') {
  $Script:MaximumFunctionCount = 32768
  $Script:MaximumVariableCount = 32768
}

# ---------------- Logging ----------------
$LogDir  = Join-Path $env:TEMP 'AutopilotUploadLogs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ('AutopilotUpload_AppOnly-{0}-{1}.log' -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd_HHmmss'))
function Write-Log {
  param([string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
  Write-Host $line
  Add-Content -Path $LogFile -Value $line
}

# ---------------- Minimal Graph bootstrap (Authentication only) ----------------
function Ensure-GraphAuthModule {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue)) { Register-PSRepository -Default }
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    try {
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
      Install-Module PowerShellGet -Scope AllUsers -Force -AllowClobber -ErrorAction SilentlyContinue
    } catch { }
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
      Install-Module -Name Microsoft.Graph.Authentication -Scope AllUsers -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
    }
    Import-Module Microsoft.Graph.Authentication -Force
    return $true
  } catch {
    Write-Log ('Failed to prepare Graph SDK: {0}' -f $_.Exception.Message) 'ERROR'
    return $false
  }
}
function Safe-DisconnectMgGraph {
  $cmd = Get-Command -Name Disconnect-MgGraph -ErrorAction SilentlyContinue
  if ($cmd) { Disconnect-MgGraph -ErrorAction SilentlyContinue }
}

# ---------------- Hardware hash via MDM Bridge ----------------
function Get-DeviceInfo {
  $bios = Get-CimInstance Win32_BIOS
  $cs   = Get-CimInstance Win32_ComputerSystem
  $os   = Get-CimInstance Win32_OperatingSystem
  [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Manufacturer = $cs.Manufacturer
    Model        = $cs.Model
    SerialNumber = $bios.SerialNumber
    OSVersion    = $os.Version
    OSEdition    = $os.Caption
  }
}
function Get-HardwareHash {
  try {
    $dev  = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_DevDetail_Ext01' -ErrorAction Stop
    $hash = $dev.DeviceHardwareData
    if ([string]::IsNullOrWhiteSpace($hash)) { throw 'DeviceHardwareData is empty.' }
    return $hash
  } catch {
    Write-Log ('Failed to read hardware hash via MDM Bridge: {0}' -f $_.Exception.Message) 'ERROR'
    return $null
  }
}

# ---------------- CSV writer (optional) ----------------
function Write-HashCsv {
  param([string]$Serial,[string]$Hash,[string]$GroupTag)
  $csvPath = Join-Path $LogDir ('AutopilotHashes-{0}-{1}.csv' -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd_HHmmss'))
  $row = [pscustomobject]@{
    'Device Serial Number' = $Serial
    'Windows Product ID'   = ''
    'Hardware Hash'        = $Hash
    'Group Tag'            = $GroupTag
    'Assigned User'        = ''    # empty (no pre-assignment)
  }
  $exists = Test-Path $csvPath
  $row | Export-Csv -Path $csvPath -NoTypeInformation -Append:$exists -Encoding UTF8
  Write-Log ('Wrote CSV row to {0}' -f $csvPath)
}

# ---------------- App-only auth (Client Secret / Certificate) ----------------
function Connect-Graph-AppOnly {
  param([string]$Tenant,[string]$Client,[string]$Secret,[string]$Thumb)
  try {
    Safe-DisconnectMgGraph
    if (-not (Ensure-GraphAuthModule)) { return $false }

    if ($Thumb) {
      Write-Log 'Connecting Graph (App-only, certificate)...'
      Connect-MgGraph -TenantId $Tenant -ClientId $Client -CertificateThumbprint $Thumb | Out-Null
    } elseif ($Secret) {
      Write-Log 'Connecting Graph (App-only, client secret)...'
      $secure = ConvertTo-SecureString $Secret -AsPlainText -Force
      $cred   = New-Object System.Management.Automation.PSCredential ($Client, $secure)
      try {
        Connect-MgGraph -TenantId $Tenant -ClientSecretCredential $cred | Out-Null
      } catch {
        Connect-MgGraph -TenantId $Tenant -ClientId $Client -ClientSecret $Secret | Out-Null
      }
    } else {
      throw 'Provide ClientSecret or CertThumbprint for AppOnly.'
    }

    $c = Get-MgContext
    if (-not $c -or $c.AuthType -ne 'AppOnly') { throw 'App-only context not established.' }
    Write-Log 'App-only connection established.'
    return $true
  } catch {
    Write-Log ('App-only connect failed: {0}' -f $_.Exception.Message) 'ERROR'
    Write-Log 'Ensure application permission DeviceManagementServiceConfig.ReadWrite.All has admin consent.' 'WARN'
    return $false
  }
}

# ---------------- Autopilot import (app-only) ----------------
function Invoke-WithRetry {
  param([Parameter(Mandatory=$true)][ScriptBlock]$Action,[int]$MaxRetries=5,[int]$InitialDelayMs=1000)
  $attempt = 0; $delay = $InitialDelayMs
  while ($true) {
    try { $attempt++; return & $Action }
    catch {
      $msg = $_.Exception.Message
      if ($attempt -ge $MaxRetries -or ($msg -notmatch '429|502|503|504')) { throw }
      Write-Log ("Transient '{0}' - retry {1}/{2} in {3} ms" -f $msg,$attempt,$MaxRetries,$delay) 'WARN'
      Start-Sleep -Milliseconds $delay
      $delay = [Math]::Min($delay * 2, 15000)
    }
  }
}

function Import-Autopilot {
  param(
    [Parameter(Mandatory=$true)][string]$Serial,
    [Parameter(Mandatory=$true)][string]$HardwareHash,
    [string]$Tag,
    [string]$ProdKey
  )

  $uri = 'https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities'

  # Build payload; we intentionally DO NOT include assignedUserPrincipalName (no pre-assign)
  $payloadObj = [pscustomobject]@{
    serialNumber       = $Serial
    hardwareIdentifier = $HardwareHash
    groupTag           = $Tag
    productKey         = $ProdKey
  }
  $json = $payloadObj | ConvertTo-Json -Depth 6

  # Simple retry loop (no $using:, no remoting)
  $maxRetries = 5
  $delaySec   = 1
  for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    try {
      $res = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $json -ContentType 'application/json'
      Write-Log ('Import accepted. Serial={0}; GroupTag={1}; ImportId={2}; State={3}' -f $res.serialNumber,$res.groupTag,$res.importId,$res.state)
      return $true
    }
    catch {
      $msg = $_.Exception.Message
      if ($attempt -eq $maxRetries -or ($msg -notmatch '429|502|503|504')) {
        Write-Log ("Graph import failed: {0}" -f $msg) 'ERROR'
        return $false
      }
      Write-Log ("Transient '{0}' - retry {1}/{2} in {3}s" -f $msg,$attempt,$maxRetries,$delaySec) 'WARN'
      Start-Sleep -Seconds $delaySec
      $delaySec = [Math]::Min($delaySec * 2, 15)
    }
  }
}


# ---------------- Main ----------------
Write-Log 'Starting Autopilot upload (App-only).'

# 1) Collect hardware hash first
$info = Get-DeviceInfo
$hash = Get-HardwareHash
if (-not $hash) {
  Write-Log 'Hardware hash is empty. Ensure elevated PowerShell and Windows 10/11 with MDM Bridge.' 'ERROR'
  exit 21
}
Write-Log ("Device info: Name={0} Serial={1} Model={2}" -f $info.ComputerName,$info.SerialNumber,$info.Model)

if ($AlsoWriteCsv) { Write-HashCsv -Serial $info.SerialNumber -Hash $hash -GroupTag $GroupTag }

# 2) App-only login (secret or certificate)
$connected = Connect-Graph-AppOnly -Tenant $TenantId -Client $ClientId -Secret $ClientSecret -Thumb $CertThumbprint
if (-not $connected) { exit 12 }

# 3) Import to Autopilot (no user pre-assignment)
$ok = Import-Autopilot -Serial $info.SerialNumber -HardwareHash $hash -Tag $GroupTag -ProdKey $ProductKey

Safe-DisconnectMgGraph
if ($ok) { Write-Log 'Upload completed successfully.'; exit 0 }
else     { Write-Log 'Upload failed.' 'ERROR'; exit 30 }