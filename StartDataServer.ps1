$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot

$docker = (Get-Command docker -ErrorAction Stop).Source
$compose = (Get-Command docker-compose -ErrorAction Stop).Source
$environmentFile = Join-Path $PSScriptRoot '.env.server'

function Test-DockerReady {
    & $docker info --format '{{.ServerVersion}}' *> $null
    return $LASTEXITCODE -eq 0
}

if (-not (Test-DockerReady)) {
    $desktopCandidates = @(
        'D:\Program Files\Docker\Docker\Docker Desktop.exe',
        'C:\Program Files\Docker\Docker\Docker Desktop.exe'
    )
    $desktop = $desktopCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $desktop) {
        throw 'Docker Desktop is not installed.'
    }

    Write-Host 'Starting Docker Desktop...'
    Start-Process -FilePath $desktop

    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 2
        if (Test-DockerReady) {
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        throw 'Docker Desktop did not become ready within two minutes.'
    }
}

Write-Host 'Starting Auth database and API...'
& $compose --env-file $environmentFile -f docker-compose.auth.yml up -d --build
if ($LASTEXITCODE -ne 0) {
    throw 'Auth server failed to start.'
}

Write-Host 'Starting Chat database and API...'
& $compose --env-file $environmentFile -f docker-compose.chat.yml up -d --build
if ($LASTEXITCODE -ne 0) {
    throw 'Chat server failed to start.'
}

function Wait-ForHealth([string]$name, [string]$url) {
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $response = Invoke-RestMethod -Uri $url -TimeoutSec 3
            if ($response.ok -eq $true) {
                Write-Host "$name ready: $url" -ForegroundColor Green
                return
            }
        } catch { }
        Start-Sleep -Seconds 2
    }
    throw "$name did not pass its health check."
}

Wait-ForHealth 'Auth API' 'http://127.0.0.1:3002/health'
Wait-ForHealth 'Chat API' 'http://127.0.0.1:3004/health'

$lanAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -notlike '127.*' -and
        $_.IPAddress -notlike '169.254*' -and
        $_.InterfaceAlias -notmatch 'vEthernet|Loopback'
    } |
    Select-Object -ExpandProperty IPAddress -Unique

Write-Host ''
Write-Host 'Data server is running. Database volumes are persistent.' -ForegroundColor Green
Write-Host 'Local Auth API: http://127.0.0.1:3002'
Write-Host 'Local Chat API: http://127.0.0.1:3004'
foreach ($address in $lanAddresses) {
    Write-Host "LAN Auth API:  http://${address}:3002"
    Write-Host "LAN Chat API:  http://${address}:3004"
}
Write-Host 'Community services were not started.'
