param([switch]$Rebuild)
$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $taskProjectRoot
$taskRunDirectory = Join-Path $taskProjectRoot '.run'
[IO.Directory]::CreateDirectory($taskRunDirectory) | Out-Null
$taskStatusPath = Join-Path $taskRunDirectory 'deploy-status.json'
Start-Transcript -Path (Join-Path $taskRunDirectory 'deploy.log') -Force | Out-Null
trap {
    $taskFailure = @{ status = 'failed'; message = $_.Exception.Message } | ConvertTo-Json
    [IO.File]::WriteAllText($taskStatusPath, $taskFailure)
    Write-Host $_.Exception.Message -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}
[IO.File]::WriteAllText($taskStatusPath, '{"status":"starting"}')

# Resolve existing tools only; never install tools or change PATH/global settings.
. (Join-Path $PSScriptRoot 'ProjectTools.ps1')
$taskNode = Find-ProjectTool 'node'
$taskDocker = Find-ProjectTool 'docker'
if ($Rebuild -or -not (Test-Path -LiteralPath (Join-Path $taskProjectRoot 'build/web/index.html'))) {
    $taskFlutter = Find-ProjectTool 'flutter'
    & (Join-Path $PSScriptRoot 'InitializeProject.ps1')
}
& $taskDocker info --format '{{.ServerVersion}}'
if ($LASTEXITCODE -ne 0) {
    $taskDesktop = Join-Path $env:ProgramFiles 'Docker/Docker/Docker Desktop.exe'
    if (-not (Test-Path -LiteralPath $taskDesktop)) { throw 'The existing Docker Desktop installation was not found.' }
    Start-Process -FilePath $taskDesktop -WindowStyle Hidden
    $taskDockerReady = $false
    for ($taskWait = 0; $taskWait -lt 60; $taskWait++) {
        Start-Sleep -Seconds 2
        & $taskDocker info --format '{{.ServerVersion}}' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $taskDockerReady = $true; break }
    }
    if (-not $taskDockerReady) { throw 'Docker Desktop could not become ready. No settings were changed.' }
}
# A local .env is optional for login; needed for real password-reset email.
if (-not (Test-Path -LiteralPath (Join-Path $taskProjectRoot '.env'))) {
    Write-Warning 'No local .env: login can start; email reset needs your existing mail configuration copied into this project.'
}

Write-Host 'Starting the existing authentication database...'
& $taskDocker compose -f docker-compose.auth.yml up -d auth-db
if ($LASTEXITCODE -ne 0) { throw 'The authentication database could not be started.' }
$taskDatabaseReady = $false
for ($taskAttempt = 0; $taskAttempt -lt 20; $taskAttempt++) {
    & $taskDocker compose -f docker-compose.auth.yml exec -T auth-db pg_isready -U global_village_auth -d global_village_auth
    if ($LASTEXITCODE -eq 0) { $taskDatabaseReady = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $taskDatabaseReady) { throw 'The authentication database did not become ready.' }

Write-Host 'Saving a backup before updating the authentication service...'
$taskBackupName = 'auth-before-email-reset-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.sql'
& $taskDocker compose -f docker-compose.auth.yml exec -T auth-db pg_dump -U global_village_auth -d global_village_auth --no-owner --no-acl -f "/tmp/$taskBackupName"
if ($LASTEXITCODE -ne 0) { throw 'Database backup failed. The API update has not started.' }
& $taskDocker cp "global-village-auth-db:/tmp/$taskBackupName" (Join-Path $taskRunDirectory $taskBackupName)
if ($LASTEXITCODE -ne 0) { throw 'Could not save the database backup to this computer.' }

Write-Host 'Updating the authentication service...'
& $taskDocker compose -f docker-compose.auth.yml up -d --build auth-api
if ($LASTEXITCODE -ne 0) { throw 'Authentication service deployment failed.' }
$taskApiReady = $false
for ($taskAttempt = 0; $taskAttempt -lt 20; $taskAttempt++) {
    try {
        $taskHealth = Invoke-RestMethod -Uri 'http://127.0.0.1:3002/health' -TimeoutSec 3
        if ($taskHealth.ok) { $taskApiReady = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $taskApiReady) { throw 'The authentication service did not become ready.' }
& $taskDocker compose -f docker-compose.auth.yml exec -T auth-api npm run check:smtp
if ($LASTEXITCODE -ne 0) { Write-Warning 'Email reset is unavailable. Login will still open. Check your local SMTP settings and RESET_CODE_SECRET.' }

# The supplied frontend is already compiled from the included source.
if ($Rebuild -or -not (Test-Path -LiteralPath (Join-Path $taskProjectRoot 'build/web/index.html'))) {
    & $taskFlutter build web --dart-define=GOOGLE_WEB_CLIENT_ID=848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com --dart-define=AUTH_API_BASE_URL=http://localhost:3002 --dart-define=FAMILY_API_BASE_URL=http://localhost:3003 --dart-define=CHAT_API_BASE_URL=http://localhost:3004
    if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed. See the error above.' }
}
$taskExpectedRoot = [IO.Path]::GetFullPath($taskProjectRoot)
$taskWebRunning = $false
try {
    $taskIdentity = Invoke-RestMethod -Uri 'http://127.0.0.1:7357/__project_health' -TimeoutSec 2
    if ($taskIdentity.projectRoot -eq $taskExpectedRoot) { $taskWebRunning = $true }
} catch { }
if (-not $taskWebRunning -and -not $Rebuild) {
    try {
        $taskRemoteBundle = Join-Path $taskRunDirectory 'running-main.dart.js'
        Invoke-WebRequest -Uri 'http://127.0.0.1:7357/main.dart.js' -OutFile $taskRemoteBundle -UseBasicParsing -TimeoutSec 5
        $taskLocalHash = (Get-FileHash -LiteralPath (Join-Path $taskProjectRoot 'build/web/main.dart.js') -Algorithm SHA256).Hash
        $taskRemoteHash = (Get-FileHash -LiteralPath $taskRemoteBundle -Algorithm SHA256).Hash
        if ($taskLocalHash -eq $taskRemoteHash) { $taskWebRunning = $true }
    } catch { }
}
if (-not $taskWebRunning) {
    # Check the port without terminating or reusing an unrelated process.
    $taskPortFree = $false
    $taskProbe = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 7357)
    try { $taskProbe.Start(); $taskPortFree = $true } catch { } finally { $taskProbe.Stop() }
    if (-not $taskPortFree) { throw 'Port 7357 belongs to another preview. Close that preview and retry. No process was stopped automatically.' }
    $taskWebProcess = Start-Process -FilePath $taskNode -ArgumentList @('tools/serve-web.mjs') -WorkingDirectory $taskProjectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRunDirectory 'web.log') -RedirectStandardError (Join-Path $taskRunDirectory 'web-error.log')
    for ($taskAttempt = 0; $taskAttempt -lt 15; $taskAttempt++) {
        try {
            $taskIdentity = Invoke-RestMethod -Uri 'http://127.0.0.1:7357/__project_health' -TimeoutSec 2
            if ($taskIdentity.projectRoot -eq $taskExpectedRoot) { $taskWebRunning = $true; break }
        } catch { }
        if ($taskWebProcess.HasExited) { break }
        Start-Sleep -Seconds 1
    }
    if (-not $taskWebRunning) { throw 'The preview did not start. See .run/web-error.log.' }
}
[IO.File]::WriteAllText($taskStatusPath, (@{ status = 'ready'; url = 'http://localhost:7357'; backup = $taskBackupName } | ConvertTo-Json))
Start-Process 'http://localhost:7357'
Write-Host 'Login preview is ready. Other app modules require their own existing services.'
Stop-Transcript | Out-Null
