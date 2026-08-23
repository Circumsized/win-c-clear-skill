#Requires -Version 5.1
<#
.SYNOPSIS
  Restore items quarantined by win-c-clear-skill (-RecoveryMode quarantine).
.DESCRIPTION
  Reads the manifest.json written next to the quarantine root and moves every
  item back to its original path (parent directories are recreated as needed).
  Quarantine roots live under <skill-root>\quarantine\: wincc-quarantine_<timestamp>\.
.PARAMETER Manifest
  Path to manifest.json (printed by the engine after a quarantine clean).
.PARAMETER Only
  Optional substring filter: restore only items whose original path matches.
.PARAMETER List
  Only list manifest entries; restore nothing.
.EXAMPLE
  powershell -File tools\restore-quarantine.ps1 -Manifest "...\quarantine\wincc-quarantine_20260821_120000\manifest.json" -List
  powershell -File tools\restore-quarantine.ps1 -Manifest "...\manifest.json"
  powershell -File tools\restore-quarantine.ps1 -Manifest "...\manifest.json" -Only "SomeApp"
#>
param(
  [Parameter(Mandatory = $true)][string]$Manifest,
  [string]$Only = '',
  [switch]$List
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
if (-not (Test-Path -LiteralPath $Manifest)) { Write-Host "manifest not found: $Manifest"; exit 1 }
$m = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($m.items)
if ($Only) { $items = @($items | Where-Object { $_.original -like ('*' + $Only + '*') }) }
Write-Output ("quarantine taken: {0}; items in scope: {1}" -f $m.time, $items.Count)
if ($List) {
  foreach ($i in $items) {
    Write-Output ("  {0,10:N0} B  {1}" -f [int64]$i.sizeBytes, $i.original)
  }
  exit 0
}
$ok = 0; $fail = 0
foreach ($i in $items) {
  try {
    $parent = Split-Path -Parent $i.original
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
      New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $i.original) {
      Write-Output ("[SKIP] target exists, not overwriting: {0}" -f $i.original); $fail++
      continue
    }
    Move-Item -LiteralPath $i.quarantined -Destination $i.original -Force
    Write-Output ("[OK]   {0}" -f $i.original); $ok++
  } catch {
    Write-Output ("[FAIL] {0} ({1})" -f $i.original, $_.Exception.Message); $fail++
  }
}
Write-Output ("restored: {0}, failed/skipped: {1}" -f $ok, $fail)
# mark the manifest as consumed when everything came back
if ($fail -eq 0 -and $items.Count -gt 0) {
  try {
    $m | Add-Member -NotePropertyName restoredAt -NotePropertyValue (Get-Date).ToString('o') -Force
    [System.IO.File]::WriteAllText($Manifest, ($m | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($true)))
    Write-Output ("manifest marked restored: {0}" -f $Manifest)
  } catch {}
}
exit 0
