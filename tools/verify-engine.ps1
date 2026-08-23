$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$fail = 0

# 1) PowerShell syntax (UTF-8 显式解码，避免 GBK 主机误读中文注释假报语法错误)
$tokens = $null; $errors = $null
$ps1Text = [System.IO.File]::ReadAllText("$root\scripts\Invoke-CDriveCleanup.ps1", [System.Text.Encoding]::UTF8)
[System.Management.Automation.Language.Parser]::ParseInput($ps1Text, [ref]$tokens, [ref]$errors) | Out-Null
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

# 3b) Depth cap must NOT truncate sibling subtrees (PSD regression, 2026-08-23).
# Defect: Recurse flagged BudgetHit when depth > maxDepth; ancestors treated that as a budget
# exhaustion and broke out of their remaining-sibling loops, so one deep chain zeroed/partialized
# the measured size of unrelated siblings under the Fast(3)/Standard(6) presets.
try {
  $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("wincc_depth_{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path "$probe\a\a2\a3\a4" -Force | Out-Null
  New-Item -ItemType Directory -Path "$probe\b" -Force | Out-Null
  [System.IO.File]::WriteAllBytes((Join-Path $probe 'a\a2\a3\a4\pay.bin'), (New-Object byte[] (5MB)))
  [System.IO.File]::WriteAllBytes((Join-Path $probe 'b\pay.bin'), (New-Object byte[] (5MB)))
  try {
    $fast = [ParallelScanner]::Scan(@($probe), @(''), 1, [ScanMode]::Fast)
    $deep = [ParallelScanner]::Scan(@($probe), @(''), 1, [ScanMode]::Deep)
    # Under Fast(depth 3) the a\a2\a3\a4 payload is beyond the cap BY DESIGN (correct value 5MB =
    # sibling 'b' only); the defect zeroed BOTH because 'b' was abandoned after the deep branch.
    if ($fast.Sizes[0] -ne (5MB)) { throw ("Fast preset measured {0} bytes, expected 5242880 (sibling 'b' truncated by deep branch 'a')" -f $fast.Sizes[0]) }
    if ($deep.Sizes[0] -ne (10MB)) { throw ("Deep preset measured {0} bytes, expected 10485760" -f $deep.Sizes[0]) }
    Write-Host '[OK] depth cap does not truncate sibling subtree measurement'
  } finally {
    Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
  }
} catch {
  Write-Host ("[FAIL] depth-cap regression: {0}" -f $_.Exception.Message); $fail = 1
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
