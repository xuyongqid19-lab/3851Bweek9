@echo off
setlocal
cd /d "%~dp0"
if not exist "runtime\node\node.exe" (
  echo This is the source launcher. Use the complete Global_Village_Portable folder.
  pause
  exit /b 1
)
"runtime\node\node.exe" "launcher\portable.mjs" start %*
if errorlevel 1 pause
