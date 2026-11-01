param(
    [ValidateSet('database', 'auth', 'community', 'family', 'web')]
    [string]$Service = 'web',
    [string]$WorkDirectory = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $WorkDirectory) {
    $WorkDirectory = Join-Path (Split-Path (Split-Path $projectRoot -Parent) -Parent) 'work'
}
$WorkDirectory = [IO.Path]::GetFullPath($WorkDirectory)
function Get-NodePath {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCommand) { return $nodeCommand.Source }
    $bundledNode = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'
    if (Test-Path -LiteralPath $bundledNode) { return $bundledNode }
    throw 'Node.js 24.14 or newer is required. Install Node.js or add it to PATH.'
}

if ($Service -eq 'database') {
    $pgCtl = Join-Path $WorkDirectory 'pgsql16/pgsql/bin/pg_ctl.exe'
    $pgData = Join-Path $WorkDirectory 'pgdata0909'
    if (-not (Test-Path -LiteralPath $pgCtl) -or -not (Test-Path -LiteralPath (Join-Path $pgData 'PG_VERSION'))) {
        throw 'This machine has no prepared local PostgreSQL cluster. See DOCUMENTATION.INTEGRATION.0909.md for Docker setup.'
    }
    & $pgCtl -D $pgData status
    if ($LASTEXITCODE -eq 0) { Write-Host 'Local PostgreSQL is already running.'; exit 0 }
    & $pgCtl -D $pgData -l (Join-Path $WorkDirectory 'pg0909.log') -o '-h 127.0.0.1 -p 55439' -w start
    exit $LASTEXITCODE
}

if ($Service -eq 'web') {
    Set-Location -LiteralPath $projectRoot
    & flutter run -d chrome --web-hostname localhost --web-port 7357 --dart-define=GOOGLE_WEB_CLIENT_ID=848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com --dart-define=AUTH_API_BASE_URL=http://localhost:3002 --dart-define=FAMILY_API_BASE_URL=http://localhost:3003
    exit $LASTEXITCODE
}

$nodePath = Get-NodePath
$nodeVersion = [version]((& $nodePath -p 'process.versions.node'))
if ($nodeVersion -lt [version]'24.14.0') { throw 'Use Node.js 24.14 or newer for the Family SQLite API.' }
if ($Service -eq 'auth' -or $Service -eq 'community') {
    $passwordPath = Join-Path $WorkDirectory 'pg-password0909.txt'
    if (-not (Test-Path -LiteralPath $passwordPath)) { throw 'Local database credentials are missing. Follow the Docker setup guide on another computer.' }
    $dbPassword = [Uri]::EscapeDataString(([IO.File]::ReadAllText($passwordPath)).Trim())
    $dbName = if ($Service -eq 'auth') { 'global_village_auth' } else { 'global_village' }
    $env:DATABASE_URL = "postgres://postgres:${dbPassword}@127.0.0.1:55439/$dbName"
}
switch ($Service) {
    'auth' {
        $env:PORT = '3002'
        $env:GOOGLE_WEB_CLIENT_ID = '848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com'
        $jwtPath = Join-Path $WorkDirectory 'local-auth-jwt0909.txt'
        if (-not (Test-Path -LiteralPath $jwtPath)) {
            $random = New-Object byte[] 48
            $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $generator.GetBytes($random) } finally { $generator.Dispose() }
            [IO.File]::WriteAllText($jwtPath, [Convert]::ToBase64String($random))
        }
        $env:JWT_SECRET = ([IO.File]::ReadAllText($jwtPath)).Trim()
        Set-Location -LiteralPath (Join-Path $projectRoot 'auth-server')
    }
    'community' {
        $env:PORT = '3000'
        $env:AUTH_API_ME_URL = 'http://127.0.0.1:3002/auth/me'
        Set-Location -LiteralPath (Join-Path $projectRoot 'server')
    }
    'family' {
        $env:PORT = '3003'
        $env:HOST = '127.0.0.1'
        $env:AUTH_API_ME_URL = 'http://127.0.0.1:3002/auth/me'
        $env:ALLOWED_ORIGINS = 'http://localhost:7357'
        $env:FAMILY_DB_PATH = Join-Path $projectRoot 'family-server/data/family.sqlite'
        Set-Location -LiteralPath (Join-Path $projectRoot 'family-server')
    }
}
Write-Host "Starting $Service in this terminal. Press Ctrl+C to stop it."
& $nodePath src/index.js
exit $LASTEXITCODE
