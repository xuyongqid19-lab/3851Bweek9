@echo off
setlocal
cd /d "%~dp0"
echo This opens the official Microsoft Visual C++ x64 Runtime installer.
echo Review and accept its license in the installer if you choose to install.
echo Windows may request administrator approval. Then run Start.bat again.
start "" /wait "prerequisites\vc_redist.x64.exe"
