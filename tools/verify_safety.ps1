# Temporary verification harness (read-only checks). Deleted after verification.
$ErrorActionPreference = 'Continue'
# The engine emits UTF-8 on stdout ([Console]::OutputEncoding inside the child). Capturing that
# output with the parent's default codepage (GBK/936 on zh-CN systems) corrupts multibyte text —
# a trailing UTF-8 byte can pair with the NEXT ASCII byte under GBK, EATING the closing quote of
# a JSON string and making ConvertFrom-Json fail mid-object. Decode child output as UTF-8.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script = Join-Path $root 'scripts\Invoke-CDriveCleanup.ps1'
$fail = 0

Write-Host '=== 1. PowerShell syntax check (main script) ==='
$tokens = $null; $errors = $null
$scriptText1 = [System.IO.File]::ReadAllText($script, [System.Text.Encoding]::UTF8)
[System.Management.Automation.Language.Parser]::ParseInput($scriptText1, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -eq 0) { Write-Host 'PASS: Invoke-CDriveCleanup.ps1 syntax OK' }
else {
  $fail++
  Write-Host ('FAIL: ' + $errors.Count + ' syntax errors')
  $errors | Select-Object -First 10 | ForEach-Object { Write-Host ('  line ' + $_.Extent.StartLineNumber + ': ' + $_.Message) }
}

Write-Host ''
Write-Host '=== 2. PowerShell syntax check (all .ps1 in scripts/) ==='
Get-ChildItem (Join-Path $root 'scripts') -Filter *.ps1 | ForEach-Object {
  $t2 = $null; $e2 = $null
  $text2 = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
  [System.Management.Automation.Language.Parser]::ParseInput($text2, [ref]$t2, [ref]$e2) | Out-Null
  if ($e2.Count -eq 0) { Write-Host ('PASS: ' + $_.Name) }
  else { $fail++; Write-Host ('FAIL: ' + $_.Name + ' (' + $e2.Count + ' errors)') }
}

Write-Host ''
Write-Host '=== 3. JSON syntax check (config + assets/rules) ==='
$jsonFiles = @()
$jsonFiles += Get-ChildItem (Join-Path $root 'config') -Filter *.json
$jsonFiles += Get-ChildItem (Join-Path $root 'assets\rules') -Filter *.json
foreach ($j in $jsonFiles) {
  try {
    Get-Content -LiteralPath $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    Write-Host ('PASS: ' + $j.Name)
  } catch {
    $fail++
    Write-Host ('FAIL: ' + $j.Name + ' -> ' + $_.Exception.Message)
  }
}

Write-Host ''
Write-Host '=== 4. Guardrail semantics test (extract functions via AST) ==='
$ast = [System.Management.Automation.Language.Parser]::ParseInput([System.IO.File]::ReadAllText($script, [System.Text.Encoding]::UTF8), [ref]$null, [ref]$null)
$funcs = @('Expand-EnvPath','ConvertTo-NormPath','Get-AutoTier','Test-GuardrailBlocked','Test-PathAgainstWhitelist','Test-PathAgainstBlacklist','Get-EngineGuardPatterns','Get-GroupCounts','Get-GroupSumGB')
$found = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
  if ($funcs -contains $f.Name) { $found[$f.Name] = $f.Extent.Text }
}
foreach ($fn in $funcs) {
  if (-not $found.ContainsKey($fn)) { $fail++; Write-Host ('FAIL: function not found: ' + $fn); continue }
  Invoke-Expression $found[$fn]
}
# GuardPatterns array definition + tier regex variables (script-level assignments)
$assignNames = @('$Script:GuardPatterns','$Script:RxDanger','$Script:RxCaution','$Script:RxSafe','$Script:RxProgDirs')
foreach ($an in $assignNames) {
  $aAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $an }, $true) | Select-Object -First 1
  if ($aAst) { Invoke-Expression $aAst.Extent.Text } else { $fail++; Write-Host ('FAIL: assignment not found: ' + $an) }
}

$guardTests = @(
  @{ path = 'C:\Windows\WinSxS\amd64_x'; expect = $true;  name = 'WinSxS subtree' },
  @{ path = 'C:\Windows\System32\config\SAM'; expect = $true; name = 'System32\config' },
  @{ path = 'C:\Windows\System32\drivers\etc'; expect = $true; name = 'System32\drivers' },
  @{ path = 'C:\Windows\System32\DriverStore\FileRepository'; expect = $true; name = 'DriverStore' },
  @{ path = 'C:\Windows\Installer\$PatchCache$'; expect = $true; name = 'Windows\Installer' },
  @{ path = 'C:\Windows\assembly\GAC'; expect = $true; name = 'GAC/Assembly' },
  @{ path = 'C:\Windows\System32\ntoskrnl.exe'; expect = $true; name = 'System32 core exe' },
  @{ path = 'C:\Windows\System32\kernel32.dll'; expect = $true; name = 'System32 core dll' },
  @{ path = 'C:\Users\Bob\NTUSER.DAT'; expect = $true; name = 'NTUSER.DAT' },
  @{ path = 'C:\Users\Bob\AppData\Local\Microsoft\Windows\UsrClass.dat'; expect = $true; name = 'UsrClass.dat' },
  @{ path = 'C:\pagefile.sys'; expect = $true; name = 'pagefile.sys' },
  @{ path = 'C:\swapfile.sys'; expect = $true; name = 'swapfile.sys' },
  @{ path = 'C:\hiberfil.sys'; expect = $true; name = 'hiberfil.sys' },
  @{ path = 'C:\Boot\BCD'; expect = $true; name = 'Boot\BCD' },
  @{ path = 'C:\EFI\Microsoft\Boot'; expect = $true; name = 'EFI partition' },
  @{ path = 'C:\Recovery\WindowsRE'; expect = $true; name = 'Recovery' },
  @{ path = 'C:\Windows\System32\winevt\Logs\System.evtx'; expect = $true; name = 'winevt logs' },
  @{ path = 'C:\Windows\explorer.exe'; expect = $true; name = 'explorer.exe' },
  @{ path = 'C:\Windows\regedit.exe'; expect = $true; name = 'regedit.exe' },
  @{ path = 'C:\Program Files\App\bin.exe'; expect = $true; name = 'Program Files' },
  @{ path = 'C:\Program Files (x86)\App\bin.exe'; expect = $true; name = 'Program Files x86' },
  @{ path = '%PROGRAMFILES%\App\cache'; expect = $true; name = '%PROGRAMFILES% normalized' },
  @{ path = 'C:\Windows.old\Users'; expect = $true; name = 'Windows.old' },
  @{ path = 'C:\Windows'; expect = $true; name = 'Windows root' },
  @{ path = 'C:\Windows\System32'; expect = $true; name = 'System32 root' },
  @{ path = 'C:\Users\Bob\AppData\Local\Temp\..\..\Windows\System32'; expect = $true; name = '.. traversal to System32' },
  @{ path = 'C:\Windows.'; expect = $true; name = 'trailing dot alias of Windows' },
  @{ path = 'C:\Windows '; expect = $true; name = 'trailing space alias of Windows' },
  @{ path = 'C:\'; expect = $true; name = 'drive root expanded (C:\)' },
  @{ path = '%SystemDrive%'; expect = $true; name = 'drive root normalized (%SystemDrive%)' },
  @{ path = 'C:'; expect = $true; name = 'drive root bare (C:)' },
  @{ path = '%LOCALAPPDATA%\Temp\junk.tmp'; expect = $false; name = 'user temp (allowed)' },
  @{ path = '%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache'; expect = $false; name = 'chrome cache (allowed)' },
  @{ path = '%APPDATA%\Code\Cache'; expect = $false; name = 'vscode cache (allowed)' }
)
$gPass = 0; $gFail = 0
foreach ($t in $guardTests) {
  $r = Test-GuardrailBlocked $t.path
  if ($r -eq $t.expect) { $gPass++ }
  else { $gFail++; $fail++; Write-Host ('FAIL guard: ' + $t.name + ' path=' + $t.path + ' got=' + $r + ' expect=' + $t.expect) }
}
Write-Host ('Guardrail tests: ' + $gPass + ' passed, ' + $gFail + ' failed')

Write-Host ''
Write-Host '=== 5. Whitelist fail-closed test ==='
$wlEmpty = Test-PathAgainstWhitelist 'C:\anything' @()
if ($wlEmpty -eq $false) { Write-Host 'PASS: empty whitelist denies all (fail-closed)' }
else { $fail++; Write-Host 'FAIL: empty whitelist allowed a path (fail-open!)' }
$wlHit = Test-PathAgainstWhitelist 'C:\Users\X\AppData\Local\Temp\f.tmp' @('C:\Users\X\AppData\Local\Temp')
if ($wlHit -eq $true) { Write-Host 'PASS: whitelist prefix match works' }
else { $fail++; Write-Host 'FAIL: whitelist prefix match broken' }

Write-Host ''
Write-Host '=== 6. Tier classification test ==='
$tierTests = @(
  @{ p = '%LOCALAPPDATA%\Temp'; e = 'dir'; expect = 'safe' },
  @{ p = '%APPDATA%\Mozilla\Firefox\Profiles\x\cookies.sqlite'; e = 'file'; expect = 'dangerous' },
  @{ p = '%USERPROFILE%\Downloads'; e = 'dir'; expect = 'caution' },
  @{ p = '%LOCALAPPDATA%\SomeUnknownDir'; e = 'dir'; expect = 'dangerous' },
  @{ p = '%APPDATA%\app\login.dat'; e = 'file'; expect = 'dangerous' },
  @{ p = '%LOCALAPPDATA%\NVIDIA\DXCache'; e = 'dir'; expect = 'safe' }
)
foreach ($t in $tierTests) {
  $r = Get-AutoTier $t.p $t.e
  if ($r -eq $t.expect) { Write-Host ('PASS tier: ' + $t.p + ' -> ' + $r) }
  else { $fail++; Write-Host ('FAIL tier: ' + $t.p + ' got=' + $r + ' expect=' + $t.expect) }
}

Write-Host ''
Write-Host '=== 7. ConvertTo-NormPath env-var roundtrip ==='
# %TMP%/%TEMP% and %LOCALAPPDATA%\Temp resolve to the same directory; any env-form is valid
$np = ConvertTo-NormPath ($env:LOCALAPPDATA + '\Temp')
if ($np -match '^%[A-Z0-9()]+%') { Write-Host ('PASS: normalized to env-form ' + $np) }
else { $fail++; Write-Host ('FAIL: got literal path ' + $np + ' expected env-var form') }
$np2 = ConvertTo-NormPath '%LOCALAPPDATA%\Temp'
if ($np2 -match '^%[A-Z0-9()]+%') { Write-Host ('PASS: env-form preserved: ' + $np2) }
else { $fail++; Write-Host ('FAIL: env-form got ' + $np2) }
$np3 = ConvertTo-NormPath ($env:APPDATA + '\Code\Cache')
if ($np3 -eq '%APPDATA%\Code\Cache') { Write-Host ('PASS: ' + $np3) }
else { $fail++; Write-Host ('FAIL: got ' + $np3 + ' expected %APPDATA%\Code\Cache') }

Write-Host ''
Write-Host '=== 8. C# scanner compile check (PowerShell 5.1 Add-Type) ==='
foreach ($cs in @('ParallelScanner.cs','MftScanner.cs')) {
  $csPath = Join-Path $root ('scripts\' + $cs)
  if (-not (Test-Path $csPath)) { Write-Host ('SKIP: ' + $cs + ' not present'); continue }
  try {
    Add-Type -TypeDefinition (Get-Content -LiteralPath $csPath -Raw -Encoding UTF8) -Language CSharp -ErrorAction Stop
    Write-Host ('PASS: ' + $cs + ' compiled')
  } catch {
    $fail++
    Write-Host ('FAIL: ' + $cs + ' compile error: ' + $_.Exception.Message)
  }
}

Write-Host ''
Write-Host '=== 9. Report grouping stats test (category/tier aggregates) ==='
$sampleItems = @(
  [pscustomobject]@{ category = 'dev';   tier = 'safe'; freedGB = 0.5 },
  [pscustomobject]@{ category = 'dev';   tier = 'safe'; freedGB = 1.5 },
  [pscustomobject]@{ category = 'cn';    tier = 'caution'; freedGB = 0.2 },
  [pscustomobject]@{ category = '';      tier = 'safe'; freedGB = 0.1 },
  [pscustomobject]@{ category = 'ai';    tier = 'dangerous'; freedGB = 3.0 }
)
$gc = Get-GroupCounts $sampleItems 'category'
$catProps = @($gc.PSObject.Properties)
if ($catProps.Count -eq 4) { Write-Host ('PASS: group count by category = 4 groups (dev/cn/ai/unknown)') }
else { $fail++; Write-Host ('FAIL: expected 4 category groups, got ' + $catProps.Count + ' [' + (($catProps.Name) -join ',') + ']') }
$devCount = $gc.dev
if ($devCount -eq 2) { Write-Host 'PASS: dev count = 2' } else { $fail++; Write-Host ('FAIL: dev count = ' + $devCount) }
$unkCount = $gc.unknown
if ($unkCount -eq 1) { Write-Host 'PASS: empty category -> unknown = 1' } else { $fail++; Write-Host ('FAIL: unknown count = ' + $unkCount) }

$gs = Get-GroupSumGB $sampleItems 'tier' 'freedGB'
$safeSum = [double]$gs.safe
if ([math]::Abs($safeSum - 2.1) -lt 0.001) { Write-Host 'PASS: tier sum safe = 2.10 GB' } else { $fail++; Write-Host ('FAIL: safe sum = ' + $safeSum) }
$dangerSum = [double]$gs.dangerous
if ([math]::Abs($dangerSum - 3.0) -lt 0.001) { Write-Host 'PASS: tier sum dangerous = 3.00 GB' } else { $fail++; Write-Host ('FAIL: dangerous sum = ' + $dangerSum) }

Write-Host ''
Write-Host '=== 10. Unknown-id contract regression (DryRun, zero deletion) ==='
# Contract: -Ids referencing a non-whitelist id (e.g. a raw protected path) must surface as
# status "error" and be counted in totals.errors — never downgraded to "skipped" by the
# tier/exists gates. Regression for the gate-override bug.
try {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Mode Clean -Ids 'C:\Windows\System32' -Tiers safe -DryRun 2>&1 | Out-String
  # Anchor on the END marker instead of "first } + newline": the compact JSON is one long line
  # that console capture may wrap; a non-greedy \{.*?\} can stop inside a nested object.
  $m = [regex]::Match($out, '(?s)JSON_SUMMARY_BEGIN\s*-+\s*(.*?)\s*-{3,}\s*JSON_SUMMARY_END')
  if ($m.Success) {
    $js = $m.Groups[1].Value.Trim() | ConvertFrom-Json
    $uid = @($js.items | Where-Object { $_.origin -eq 'none' }) | Select-Object -First 1
    if ($uid -and $uid.status -eq 'error') { Write-Host 'PASS: unknown id -> status "error"' }
    else { $fail++; Write-Host ('FAIL: unknown id status = ' + $(if ($uid) { $uid.status } else { '(missing)' }) + ' (expect error)') }
    if ($js.totals.errors -ge 1) { Write-Host ('PASS: totals.errors = ' + $js.totals.errors) }
    else { $fail++; Write-Host 'FAIL: totals.errors = 0 (unknown id not counted as error)' }
    if ($js.totals.freedGB -eq 0 -and $js.totals.cleaned -eq 0) { Write-Host 'PASS: nothing freed/cleaned (safe)' }
    else { $fail++; Write-Host 'FAIL: unexpected freed/cleaned for unknown id' }
  } else { $fail++; Write-Host 'FAIL: could not locate JSON_SUMMARY in engine output' }
} catch {
  $fail++
  Write-Host ('FAIL: unknown-id regression test error: ' + $_.Exception.Message)
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL VERIFICATION CHECKS PASSED' }
else { Write-Host ('VERIFICATION FAILURES: ' + $fail) }
exit $fail
