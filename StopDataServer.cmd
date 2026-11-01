@echo off
setlocal
cd /d "%~dp0"
"D:\Program Files\Docker\Docker\resources\bin\docker-compose.exe" --env-file .env.server -f docker-compose.chat.yml stop
"D:\Program Files\Docker\Docker\resources\bin\docker-compose.exe" --env-file .env.server -f docker-compose.auth.yml stop
echo Auth and Chat servers stopped. Database volumes were preserved.
pause
endlocal
