@echo off
rem win-c-clear-skill :: Clean SAFE tier only (UAC prompt only if admin targets selected)
rem caution/dangerous tiers are never cleaned by this entry; use the agent flow for those.
setlocal
set "SCRIPT=%~dp0Invoke-CDriveCleanup.ps1"
echo [1/2] Scanning (generates the cleanup plan required by the safety gate)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Scan -Tiers safe
if errorlevel 4 goto plan_failed
echo.
echo [2/2] Cleaning SAFE tier caches (regenerable only)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Clean -Tiers safe -Elevate
echo.
pause
exit /b 0

:plan_failed
echo.
echo Scan failed or was cancelled; Clean is blocked by the safety gate without a fresh scan plan.
pause
exit /b 1
