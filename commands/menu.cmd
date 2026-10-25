@echo off
rem Runs menu.ps1 with the Windows PowerShell that ships with Windows. Bypass applies to
rem this process only, so the default execution policy does not block the script.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0menu.ps1" %*
exit /b %ERRORLEVEL%
