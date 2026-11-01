$ErrorActionPreference = 'Stop'
function Find-ProjectTool([string]$Name) {
    $taskCommand = Get-Command $Name -ErrorAction SilentlyContinue
    if ($taskCommand) { return $taskCommand.Source }
    if ($Name -eq 'node' -and (Test-Path -LiteralPath 'D:\node-v24.16.0-win-x64\node.exe')) { return 'D:\node-v24.16.0-win-x64\node.exe' }
    if ($Name -eq 'flutter') {
        $taskSettings = Join-Path (Split-Path $PSScriptRoot -Parent) '.vscode/settings.json'
        if (Test-Path -LiteralPath $taskSettings) {
            try {
                $taskSdk = (Get-Content -LiteralPath $taskSettings -Raw | ConvertFrom-Json).'dart.flutterSdkPath'
                if ($taskSdk -and (Test-Path -LiteralPath (Join-Path $taskSdk 'bin/flutter.bat'))) { return (Join-Path $taskSdk 'bin/flutter.bat') }
            } catch { }
        }
        if ($env:FLUTTER_ROOT -and (Test-Path -LiteralPath (Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'))) { return (Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat') }
    }
    throw "$Name was not found. Use your existing SDK/tool installation. No system settings were changed."
}
