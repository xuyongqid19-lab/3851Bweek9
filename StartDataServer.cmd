@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0StartDataServer.ps1"
if errorlevel 1 (
  echo.
  echo Data server startup failed. Review the error above.
  pause
  exit /b 1
)
pause
endlocal
