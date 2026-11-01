@echo off
setlocal
cd /d "%~dp0"
"runtime\node\node.exe" "launcher\portable.mjs" stop
if errorlevel 1 pause
