$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot

$environmentFile = Join-Path $PSScriptRoot '.env.server'
$stateFile = Join-Path $PSScriptRoot '.public-demo.json'
$stdoutLog = Join-Path $PSScriptRoot '.public-tunnel-stdout.txt'
$stderrLog = Join-Path $PSScriptRoot '.public-tunnel-stderr.txt'
$compose = (Get-Command docker-compose -ErrorAction Stop).Source
$googleWebClientId = '848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com'

function Wait-ForHealth([string]$name, [string]$url) {
    for ($i = 0; $i -lt 45; $i++) {
        try {
            $response = Invoke-RestMethod -Uri $url -TimeoutSec 3
            if ($response.ok -eq $true) {
                Write-Host "$name ready" -ForegroundColor Green
                return
            }
        } catch { }
        Start-Sleep -Seconds 2
    }
    throw "$name did not pass its health check: $url"
}

function Find-Cloudflared {
    $command = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        'C:\Program Files\cloudflared\cloudflared.exe',
        'C:\Program Files (x86)\cloudflared\cloudflared.exe',
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\cloudflared.exe"
    )
    return $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $environmentFile)) {
    throw '.env.server is missing. Copy the existing private server configuration before starting.'
}

docker info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Desktop is not running.'
}

$cloudflared = Find-Cloudflared
if (-not $cloudflared) {
    throw 'cloudflared is not installed.'
}

if (Test-Path -LiteralPath $stateFile) {
    try {
        $oldState = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        if ($oldState.tunnelPid) {
            Stop-Process -Id $oldState.tunnelPid -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

Write-Host 'Starting the four backend services...'
& $compose -f docker-compose.yml up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Community service failed to start.' }
& $compose --env-file $environmentFile -f docker-compose.auth.yml up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Auth service failed to start.' }
& $compose --env-file $environmentFile -f docker-compose.family.yml up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Family service failed to start.' }
& $compose --env-file $environmentFile -f docker-compose.chat.yml up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Chat service failed to start.' }

Wait-ForHealth 'Community API' 'http://127.0.0.1:3000/health'
Wait-ForHealth 'Auth API' 'http://127.0.0.1:3002/health'
Wait-ForHealth 'Family API' 'http://127.0.0.1:3003/health'
Wait-ForHealth 'Chat API' 'http://127.0.0.1:3004/health'

Remove-Item -LiteralPath $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue
$tunnel = Start-Process -FilePath $cloudflared `
    -ArgumentList @('tunnel', '--no-autoupdate', '--url', 'http://127.0.0.1:8080') `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -WindowStyle Hidden `
    -PassThru

$publicUrl = $null
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 1
    $logText = ''
    if (Test-Path -LiteralPath $stdoutLog) { $logText += Get-Content -LiteralPath $stdoutLog -Raw }
    if (Test-Path -LiteralPath $stderrLog) { $logText += Get-Content -LiteralPath $stderrLog -Raw }
    $match = [regex]::Match($logText, 'https://[a-z0-9-]+\.trycloudflare\.com')
    if ($match.Success) {
        $publicUrl = $match.Value
        break
    }
    if ($tunnel.HasExited) {
        throw 'Cloudflare Tunnel exited before producing a public URL.'
    }
}
if (-not $publicUrl) {
    Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
    throw 'Timed out waiting for the Cloudflare public URL.'
}

Write-Host "Building Flutter Web for $publicUrl ..."
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
flutter build web --release `
    --dart-define="GOOGLE_WEB_CLIENT_ID=$googleWebClientId" `
    --dart-define="AUTH_API_BASE_URL=$publicUrl" `
    --dart-define="CHAT_API_BASE_URL=$publicUrl" `
    --dart-define="COMMUNITY_API_BASE_URL=$publicUrl" `
    --dart-define="FAMILY_API_BASE_URL=$publicUrl"
if ($LASTEXITCODE -ne 0) { throw 'Flutter Web build failed.' }

& $compose -f docker-compose.public.yml up -d --force-recreate
if ($LASTEXITCODE -ne 0) { throw 'Public gateway failed to start.' }
Wait-ForHealth 'Public gateway' 'http://127.0.0.1:8080/public-health'

[ordered]@{
    publicUrl = $publicUrl
    tunnelPid = $tunnel.Id
    startedAt = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8

Write-Host ''
Write-Host 'Global Village is publicly available at:' -ForegroundColor Green
Write-Host $publicUrl -ForegroundColor Cyan
Write-Host ''
Write-Host 'Keep this computer and Docker Desktop running.'
Write-Host 'Run StopPublicDemo.cmd when the demonstration is finished.'
Start-Process $publicUrl
