$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot
$stateFile = Join-Path $PSScriptRoot '.public-demo.json'
$compose = (Get-Command docker-compose -ErrorAction Stop).Source

if (Test-Path -LiteralPath $stateFile) {
    try {
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        if ($state.tunnelPid) {
            Stop-Process -Id $state.tunnelPid -Force -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    }
}

& $compose -f docker-compose.public.yml stop
Write-Host 'The public URL is offline. Backend containers and all database data were kept.' -ForegroundColor Green
