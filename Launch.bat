@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LAUNCH_PS1=%~dp0Launch.ps1"

if not exist "%LAUNCH_PS1%" (
    echo ERROR: Launch.ps1 was not found in %~dp0
    pause
    exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%LAUNCH_PS1%"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo Launch.ps1 exited with code %RC%.
    pause
    exit /b %RC%
)

echo.
exit /b 0
