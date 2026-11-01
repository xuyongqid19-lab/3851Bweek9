@echo off
setlocal
cd /d "%~dp0"
"runtime\node\node.exe" "launcher\portable.mjs" check
pause
