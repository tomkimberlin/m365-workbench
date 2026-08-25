@echo off
setlocal

set "PWSH_ALIAS=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
if not exist "%PWSH_ALIAS%" (
    echo PowerShell 7 is required but was not found.
    echo Install Microsoft PowerShell 7, then launch this utility again.
    pause
    exit /b 1
)

start "" "%PWSH_ALIAS%" -NoLogo -NoProfile -STA -WindowStyle Hidden -File "%~dp0M365Workbench.ps1"
exit /b 0
