@echo off
rem win-c-clear-skill :: Clean SAFE tier only (UAC prompt only if admin targets selected)
rem caution/dangerous tiers are never cleaned by this entry; use the agent flow for those.
setlocal
set "SCRIPT=%~dp0Invoke-CDriveCleanup.ps1"
echo Cleaning SAFE tier caches (regenerable only)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Clean -Tiers safe -Elevate
echo.
pause
