$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$fail = 0

# 1) PowerShell syntax
$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile("$root\scripts\Invoke-CDriveCleanup.ps1", [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  Write-Host "[FAIL] PS1 syntax:"; $errors | ForEach-Object { Write-Host ("  line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) }; $fail = 1
} else { Write-Host '[OK] Invoke-CDriveCleanup.ps1 syntax' }

# 2) C# compile checks (same as engine Add-Type)
foreach ($cs in @('ParallelScanner.cs','MftScanner.cs')) {
  $src = Get-Content -LiteralPath "$root\scripts\$cs" -Raw -Encoding UTF8
  try {
    Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
    Write-Host ("[OK] {0} compiles" -f $cs)
  } catch {
    Write-Host ("[FAIL] {0}: {1}" -f $cs, $_.Exception.Message); $fail = 1
  }
}

# 3) ScanMode enum + presets sanity (uses types loaded above)
try {
  $m = [enum]::GetNames([ScanMode])
  if (@($m) -notcontains 'Fast' -or @($m) -notcontains 'Standard' -or @($m) -notcontains 'Deep') { throw "unexpected enum: $($m -join ',')" }
  # backward-compatible 3-param overload must resolve
  $res = [ParallelScanner]::Scan(@($env:TEMP), @(''), 2)
  if ($res.Sizes.Count -lt 1) { throw 'empty result' }
  Write-Host '[OK] ParallelScanner.Scan 3-param smoke (TEMP) -> sizes ok'
} catch {
  Write-Host ("[FAIL] scanner runtime smoke: {0}" -f $_.Exception.Message); $fail = 1
}

# 4) blacklist regex patterns all compile (mirror MftScanner gate semantics)
$lists = Get-Content -LiteralPath "$root\config\scan-lists.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$badRx = 0
foreach ($e in @($lists.blacklist.entries)) {
  foreach ($p in @($e.patterns)) {
    try { [void][regex]::new($p) } catch { Write-Host ("[FAIL] bad blacklist regex '{0}' in {1}: {2}" -f $p, $e.id, $_.Exception.Message); $badRx++ }
  }
}
if ($badRx -eq 0) { Write-Host ('[OK] all {0} blacklist regexes compile' -f @($lists.blacklist.entries | ForEach-Object { @($_.patterns).Count } | Measure-Object -Sum).Sum) } else { $fail = 1 }

exit $fail
