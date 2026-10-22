@echo off
chcp 65001 >nul
setlocal
set "PYTHONUTF8=1"
set "PYTHON=%LOCALAPPDATA%\xtool-local\venv-11.42.0\Scripts\python.exe"
if not exist "%~dp0.xtool-local.json" goto init
if not exist "%PYTHON%" goto init
echo 请连接并解锁 iPhone，必要时点击信任此电脑。
"%PYTHON%" -u "%~dp0scripts\local-sign-install.py" %*
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo 操作失败，请查看上方错误；未执行卸载应用操作。
pause
exit /b %RESULT%
:init
echo 请先运行项目中的 初始化.cmd。
pause
exit /b 1
