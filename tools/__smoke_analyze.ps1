# Smoke test: Analyze mode end-to-end, read-only, minimal budget.
# NOTE this used to dot-source the engine and then call `Invoke-CDriveCleanup -Mode Analyze ...`.
# That was wrong twice over: the engine is a SCRIPT, not a function (so the call failed as an
# unknown command), and dot-sourcing it EXECUTED a full default-parameter run (-Mode Scan) in the
# caller's scope, whose terminal `exit 0` then tore down the host. Invoke it as a script instead.
$ErrorActionPreference = 'Stop'
$engine = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Invoke-CDriveCleanup.ps1'
if (-not (Test-Path -LiteralPath $engine)) { Write-Host "engine not found: $engine"; exit 1 }

$transcript = Join-Path $env:TEMP 'ccsmoke_analyze.txt'
Remove-Item -LiteralPath $transcript -Force -ErrorAction SilentlyContinue

& powershell -NoProfile -ExecutionPolicy Bypass -File $engine `
  -Mode Analyze -ScanMode fast -NoMft -TopN 3 -LogPath $transcript
$code = $LASTEXITCODE

Write-Host ''
if ($code -eq 0) { Write-Host 'SMOKE OK (Analyze, read-only)' } else { Write-Host ("SMOKE FAILED: exit {0}" -f $code) }
Write-Host ("log: {0}" -f $transcript)
exit $code
