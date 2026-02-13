<#
  Copyright (c) 2026 Sudeep Gyawali
  Licensed under the MIT License. See the LICENSE file in the repository root.
#>
# UninstallApp.ps1  (Remove Browser Link shortcuts)
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Name)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logDir  = Join-Path $env:ProgramData 'GenericApp'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ('UninstallApp_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
Start-Transcript -Path $logFile -Append | Out-Null

$targets = @(
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\$Name.lnk",
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\$Name.url",
    "$env:Public\Desktop\$Name.lnk",
    "$env:Public\Desktop\$Name.url"
)
foreach ($p in $targets) { if (Test-Path $p) { Remove-Item -Path $p -Force -ErrorAction SilentlyContinue } }

Write-Output "Removed shortcuts for '$Name'."
Stop-Transcript | Out-Null
exit 0