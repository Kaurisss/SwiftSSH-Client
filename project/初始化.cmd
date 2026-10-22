@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\init-xtool.ps1"
set "RESULT=%ERRORLEVEL%"
pause
exit /b %RESULT%
