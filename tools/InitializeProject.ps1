$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ProjectTools.ps1')
Set-Location -LiteralPath (Split-Path $PSScriptRoot -Parent)
$taskFlutter = Find-ProjectTool 'flutter'
& $taskFlutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency initialization failed. See the error above.' }
Write-Host 'Project dependencies are ready.'
