<#
=============================================================================
setup-runner-windows.ps1 - install a GitHub Actions self-hosted runner on a
Windows VM (Server 2019+/Windows 10+) as a service, plus the deployment tools.

The workflows use "shell: bash", so Git for Windows (Git Bash) is REQUIRED.

Usage (elevated PowerShell):
  .\setup-runner-windows.ps1 `
      -GitHubUrl   "https://github.com/<org>/<repo>" `
      -RunnerToken "<registration token>" `
      -RunnerName  "nrap-deploy-win-01" `
      -RunnerLabels "databricks-deploy,windows"

RunnerToken: GitHub -> Settings -> Actions -> Runners -> New self-hosted
runner -> copy the value after "--token" (valid for 1 hour).
=============================================================================
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $GitHubUrl,
  [Parameter(Mandatory = $true)] [string] $RunnerToken,
  [string] $RunnerName    = "$env:COMPUTERNAME-databricks",
  [string] $RunnerLabels  = "databricks-deploy",
  [string] $RunnerDir     = "C:\actions-runner",
  [string] $RunnerVersion = "latest",
  [string] $RunnerGroup   = "Default"
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

Step "1/5 Installing tools with winget (Git for Windows, jq, Databricks CLI)"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget not found. Install 'App Installer' from Microsoft, or install Git, jq and Databricks CLI manually."
}
winget install --id Git.Git                 -e --silent --accept-source-agreements --accept-package-agreements
winget install --id jqlang.jq               -e --silent --accept-source-agreements --accept-package-agreements
winget install --id Databricks.DatabricksCLI -e --silent --accept-source-agreements --accept-package-agreements

Step "2/5 Downloading GitHub Actions runner ($RunnerVersion)"
if ($RunnerVersion -eq "latest") {
  $RunnerVersion = (Invoke-RestMethod "https://api.github.com/repos/actions/runner/releases/latest").tag_name.TrimStart("v")
}
New-Item -ItemType Directory -Force -Path $RunnerDir | Out-Null
Set-Location $RunnerDir
$zip = "actions-runner-win-x64-$RunnerVersion.zip"
Invoke-WebRequest -Uri "https://github.com/actions/runner/releases/download/v$RunnerVersion/$zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $RunnerDir -Force
Remove-Item $zip

Step "3/5 Registering runner '$RunnerName' as a Windows service"
.\config.cmd --unattended `
  --url $GitHubUrl `
  --token $RunnerToken `
  --name $RunnerName `
  --labels $RunnerLabels `
  --runnergroup $RunnerGroup `
  --work _work `
  --runasservice `
  --replace

Step "4/5 Making Git Bash available to the runner service"
$gitBin = "C:\Program Files\Git\bin"
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notlike "*$gitBin*") {
  [Environment]::SetEnvironmentVariable("Path", "$machinePath;$gitBin", "Machine")
}
Get-Service "actions.runner.*" | Restart-Service

Step "5/5 Verifying"
& "$gitBin\bash.exe" -lc "databricks --version; jq --version; git --version"
Get-Service "actions.runner.*" | Format-Table Name, Status

Write-Host @"

Runner installed. In GitHub -> Settings -> Actions -> Runners, '$RunnerName' should be Idle.
If you used labels other than 'databricks-deploy', set the repository variable
RUNNER_LABELS, e.g. ["self-hosted","windows","databricks-deploy"].
"@
