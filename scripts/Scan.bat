@echo off
rem win-c-clear-skill :: Scan entry (read-only, no deletion)
setlocal
set "SCRIPT=%~dp0Invoke-CDriveCleanup.ps1"
echo Running SCAN (no deletion will happen)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Scan -Tiers safe,caution,dangerous
echo.
pause
