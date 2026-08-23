#Requires -Version 5.1
<#
.SYNOPSIS
  Regression suite for known security / safety defects.
.DESCRIPTION
  Every test here pins a defect that shipped in v1.0.0 and was fixed afterwards. The existing
  verify_safety.ps1 covers guardrail regexes / tiers / contracts; this file covers the areas that
  had ZERO coverage and were exactly where the real defects lived:

    C1  glob scoping        - glob targets must delete ONLY matching files, never the whole dir
    C2  reparse fence       - deletion must never recurse through a junction/symlink
    H2  diagnostic mode     - read-only audit profile must not be combinable with -Mode Clean
    H3  per-path whitelist  - a target must not smuggle non-whitelisted paths past the fence
    H4  plan scope binding  - Clean must be bound to the ids the Scan actually enumerated
    M1  id injection guard  - quotes/metacharacters in -Ids/-ConfirmIds must be rejected
    M3  7-tuple glob parse  - [name,path,type,bool,meta,bool,glob] must keep its glob
    M7  guard symmetry      - normalized (%WINDIR%\..) forms must match the same guards
    M9  whitelist wildcard  - '*' detection must be a real asterisk test

  ALL filesystem tests run inside a private sandbox under the system temp dir. Nothing on C:\
  outside that sandbox is ever touched, and every case asserts on a canary file that MUST survive.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-regression.ps1
#>
param([switch]$KeepSandbox)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$root   = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$engine = Join-Path $root 'scripts\Invoke-CDriveCleanup.ps1'
$fail = 0
$pass = 0

function Assert-True([bool]$Cond, [string]$Name, [string]$Detail = '') {
  if ($Cond) { $script:pass++; Write-Host ("PASS  {0}" -f $Name) }
  else { $script:fail++; Write-Host ("FAIL  {0}{1}" -f $Name, $(if ($Detail) { "  -> $Detail" } else { '' })) -ForegroundColor Red }
}

# ---------------------------------------------------------------------------
# Sandbox: private tree, removed on exit unless -KeepSandbox
# ---------------------------------------------------------------------------
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("wincc_regress_{0}" -f ([guid]::NewGuid().ToString('N').Substring(0, 10)))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
$cfgDir = Join-Path $sandbox 'cfg'
New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
Write-Host ("sandbox: {0}" -f $sandbox)
Write-Host ''

function New-Fixture([string]$Name) {
  $d = Join-Path $sandbox $Name
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  return $d
}

function New-BigFile([string]$Path, [int]$MB = 8) {
  # The Clean loop short-circuits any target whose measured size rounds to 0.00 GB
  # ("already empty", sizeGB_before -le 0). Get-BytesToGB rounds to 2 decimals, so a fixture must
  # exceed ~5.4 MB to be cleanable at all. Tiny fixtures would make these tests pass/fail for the
  # wrong reason, so anything that MUST be deleted is sized above that threshold.
  [System.IO.File]::WriteAllBytes($Path, (New-Object byte[] ($MB * 1MB)))
}

function New-Canary([string]$Path, [string]$Text) {
  # Canaries only need identity, not size — they must SURVIVE.
  Set-Content -LiteralPath $Path -Value $Text -Encoding ASCII
}

function Write-Config([string]$FileName, [object[]]$Targets, [object[]]$MergeSources = @()) {
  $cfg = [ordered]@{
    version = 2
    drive = 'C'
    mergeSources = $MergeSources
    externalMergeSources = @()
    targets = $Targets
  }
  $p = Join-Path $cfgDir $FileName
  [System.IO.File]::WriteAllText($p, ($cfg | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($true)))
  return $p
}

function Invoke-Engine([string[]]$EngineArgs) {
  # Returns @{ out=<string>; code=<int>; json=<psobject or $null> }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $engine @EngineArgs 2>&1 | Out-String
  $code = $LASTEXITCODE
  $json = $null
  $m = [regex]::Match($out, '(?s)JSON_SUMMARY_BEGIN\s*-*\s*\r?\n(.*?)\r?\n-*\s*JSON_SUMMARY_END')
  if ($m.Success) {
    try { $json = $m.Groups[1].Value.Trim() | ConvertFrom-Json } catch { $json = $null }
  }
  return @{ out = $out; code = $code; json = $json }
}

function Invoke-EngineRaw([string]$ArgString) {
  # Deliberately low-level helper: builds the child command line BY HAND so a test controls the
  # exact bytes that reach the child's argv parser. `& powershell -File @args` cannot do this:
  # PowerShell 5.1 native binding wraps an argument containing spaces in quotes WITHOUT escaping
  # embedded quotes, so a payload like `globtest" -Tiers dangerous` is silently split by the CRT
  # into [-Ids globtest] [-Tiers dangerous] and never reaches the engine as one string. Doubling
  # the embedded quotes ("...""...") delivers the literal intact — the same encoding the engine's
  # own elevated relaunch relies on.
  $o = [System.IO.Path]::GetTempFileName()
  $e = [System.IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath powershell -ArgumentList $ArgString -NoNewWindow -Wait -PassThru `
           -RedirectStandardOutput $o -RedirectStandardError $e
    $out = ''
    try { $out = (Get-Content $o -Raw -ErrorAction SilentlyContinue) + (Get-Content $e -Raw -ErrorAction SilentlyContinue) } catch {}
    return @{ out = [string]$out; code = $p.ExitCode; json = $null }
  } finally {
    Remove-Item -LiteralPath $o -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $e -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-ScanThenClean([string]$ConfigPath, [string[]]$CleanArgs, [string[]]$ScanExtra = @()) {
  # The engine plan gate requires a fresh Scan whose id set covers the Clean selection.
  $scanArgs = @('-Mode', 'Scan', '-Config', $ConfigPath, '-Tiers', 'safe,caution', '-PathFilter', 'off') + $ScanExtra
  [void](Invoke-Engine $scanArgs)
  return (Invoke-Engine (@('-Mode', 'Clean', '-Config', $ConfigPath, '-PathFilter', 'off', '-HotMinutes', '0') + $CleanArgs))
}

Write-Host '=== C1: glob targets must delete ONLY matching files (not the whole directory) ==='
# Defect: $items had no `glob` property, so Clear-OnePath received an empty GlobPattern and fell
# through to its whole-directory branch. A "delete thumbcache*.db" rule deleted every child.
$gt = New-Fixture 'globtest'
New-Item -ItemType Directory -Path (Join-Path $gt 'subdir') -Force | Out-Null
New-BigFile (Join-Path $gt 'thumbcache_1.db')       # must be deleted -> needs real size
New-BigFile (Join-Path $gt 'thumbcache_2.db') 2
New-Canary  (Join-Path $gt 'keepme.dat') 'IRREPLACEABLE'
New-Canary  (Join-Path $gt 'subdir\deep.txt') 'IMPORTANT'
$cfgGlob = Write-Config 'glob.json' @(
  [ordered]@{ id = 'globtest'; name = 'glob scope'; enabled = $true; tier = 'safe'; requiresAdmin = $false
    type = 'glob'; paths = @($gt); glob = 'thumbcache*.db'
    preCommands = @(); stopProcesses = @(); stopServices = @(); risk = 'regression fixture' }
)
$r = Invoke-ScanThenClean $cfgGlob @('-Ids', 'globtest', '-Tiers', 'safe')
Assert-True (-not (Test-Path -LiteralPath (Join-Path $gt 'thumbcache_1.db'))) 'C1 matching file deleted'
Assert-True (Test-Path -LiteralPath (Join-Path $gt 'keepme.dat')) 'C1 non-matching file SURVIVED' 'glob scope escaped: whole-directory delete'
Assert-True (Test-Path -LiteralPath (Join-Path $gt 'subdir\deep.txt')) 'C1 subdirectory SURVIVED' 'glob scope escaped into subdirs'
Write-Host ''

Write-Host '=== C2: deletion must never recurse through a junction ==='
# Defect: Clear-OnePath had no reparse-point check. PS 5.1 Remove-Item -Recurse follows directory
# junctions, so cleaning a cache dir that contains a junction destroyed the LINK TARGET's data.
$victim = New-Fixture 'victim'
New-Canary (Join-Path $victim 'precious.txt') 'MUST-SURVIVE'
$cacheDir = New-Fixture 'cachedir'
New-BigFile (Join-Path $cacheDir 'junk.tmp')   # real junk that SHOULD be cleaned
$linkPath = Join-Path $cacheDir 'link_to_victim'
$mk = & cmd /c "mklink /J `"$linkPath`" `"$victim`"" 2>&1
$junctionMade = Test-Path -LiteralPath $linkPath
if (-not $junctionMade) {
  Write-Host ("SKIP  C2 (could not create junction: {0})" -f ($mk -join ' ')) -ForegroundColor Yellow
} else {
  $cfgJunc = Write-Config 'junction.json' @(
    [ordered]@{ id = 'junctest'; name = 'junction fence'; enabled = $true; tier = 'safe'; requiresAdmin = $false
      type = 'dir'; paths = @($cacheDir); glob = ''
      preCommands = @(); stopProcesses = @(); stopServices = @(); risk = 'regression fixture' }
  )
  $r = Invoke-ScanThenClean $cfgJunc @('-Ids', 'junctest', '-Tiers', 'safe')
  Assert-True (Test-Path -LiteralPath (Join-Path $victim 'precious.txt')) 'C2 link TARGET data survived' 'DATA LOSS: deletion recursed through the junction'
  Assert-True (Test-Path -LiteralPath $victim) 'C2 link target directory survived'
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $cacheDir 'junk.tmp'))) 'C2 real junk in the cache dir was still cleaned'
}
Write-Host ''

Write-Host '=== C2b: a target path that IS a junction must never expose the link target ==='
$victim2 = New-Fixture 'victim2'
New-Canary (Join-Path $victim2 'precious2.txt') 'MUST-SURVIVE'
New-BigFile (Join-Path $victim2 'bulk.bin')
$linkRoot = Join-Path $sandbox 'link_root'
if (Test-Path -LiteralPath $linkRoot) { [System.IO.Directory]::Delete($linkRoot, $false) }
[void](& cmd /c "mklink /J `"$linkRoot`" `"$victim2`"" 2>&1)
if (-not (Test-Path -LiteralPath $linkRoot)) {
  Write-Host 'SKIP  C2b (junction unavailable)' -ForegroundColor Yellow
} else {
  $cfgJunc2 = Write-Config 'junction-root.json' @(
    [ordered]@{ id = 'juncroot'; name = 'junction as target root'; enabled = $true; tier = 'safe'; requiresAdmin = $false
      type = 'dir'; paths = @($linkRoot); glob = ''
      preCommands = @(); stopProcesses = @(); stopServices = @(); risk = 'regression fixture' }
  )
  $r = Invoke-ScanThenClean $cfgJunc2 @('-Ids', 'juncroot', '-Tiers', 'safe')
  Assert-True (Test-Path -LiteralPath (Join-Path $victim2 'precious2.txt')) 'C2b data behind a junction target root survived' 'DATA LOSS through a link root'
  Assert-True (Test-Path -LiteralPath (Join-Path $victim2 'bulk.bin')) 'C2b bulk data behind the link survived'
  # Two independent guards can fire here, and either is acceptable:
  #   1. the scanner refuses to measure through a reparse root -> size 0.00 GB -> "already empty"
  #   2. Clear-OnePath's reparse fence -> status skipped / message mentions the link
  # What must NOT happen is 'cleaned'. Assert on that, not on which guard won.
  $it = $null
  if ($r.json) { $it = @($r.json.items | Where-Object { $_.id -eq 'juncroot' }) | Select-Object -First 1 }
  Assert-True ($it -and $it.status -ne 'cleaned') 'C2b junction root not reported as cleaned' ("status=" + $(if ($it) { $it.status } else { '(none)' }))
}
Write-Host ''

Write-Host '=== H2: -ScanMode diagnostic must be refused for Clean ==='
# Defect: scan-lists.json diagnostic sets useWhitelist=false/skipBlacklist=false; the engine used
# that as the master switch, so `-Mode Clean -ScanMode diagnostic` silently removed the fence.
$r = Invoke-Engine @('-Mode', 'Clean', '-Config', $cfgGlob, '-Ids', 'globtest', '-Tiers', 'safe', '-ScanMode', 'diagnostic', '-DryRun')
Assert-True ($r.code -eq 3) 'H2 diagnostic+Clean exits 3' ("exit=" + $r.code)
Assert-True ($r.out -match 'read-only audit') 'H2 refusal explains why'

Write-Host ''
Write-Host '=== H3: a target must not smuggle non-whitelisted paths past the whitelist ==='
# Defect: the whitelist was evaluated per TARGET with any-match semantics, then every path of the
# surviving target was deleted -- including paths the whitelist never authorized.
$okDir  = New-Fixture 'wl_allowed'
$badDir = New-Fixture 'wl_not_allowed'
New-BigFile (Join-Path $okDir 'junk.tmp')                            # authorized -> must be cleaned
New-Canary  (Join-Path $badDir 'unauthorized.dat') 'MUST-SURVIVE'    # unauthorized -> must survive
New-BigFile (Join-Path $badDir 'bulk.bin')
$slPath = Join-Path $cfgDir 'scan-lists.json'
$sl = [ordered]@{
  version = 1
  whitelist = [ordered]@{ enabled = $true; entries = @([ordered]@{ id = 'allowed'; name = 'allowed'; paths = @($okDir) }) }
  blacklist = [ordered]@{ enabled = $true; entries = @() }
  scanModes = [ordered]@{
    standard = [ordered]@{ useWhitelist = $true; maxDepth = 3; followJunctions = $false; skipBlacklist = $true }
  }
}
[System.IO.File]::WriteAllText($slPath, ($sl | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($true)))
# origin must be community for the whitelist to apply (builtin/merged are the curated whitelist).
# The engine only loads targets.merged.json when mergeSources resolves to an existing directory, and
# it re-merges when any file under that directory is newer than the merged file. An EMPTY rules dir
# therefore keeps our hand-written merged file intact (max-mtime stays DateTime.MinValue).
$emptyRules = Join-Path $cfgDir 'emptyrules'
New-Item -ItemType Directory -Path $emptyRules -Force | Out-Null
$cfgWl = Write-Config 'targets.json' @(
  [ordered]@{ id = 'placeholder'; name = 'unused'; enabled = $false; tier = 'safe'; requiresAdmin = $false
    type = 'dir'; paths = @((Join-Path $sandbox 'nonexistent')); glob = ''
    preCommands = @(); stopProcesses = @(); stopServices = @(); risk = 'placeholder' }
) @('emptyrules')
$mergedPath = Join-Path $cfgDir 'targets.merged.json'
$merged = [ordered]@{
  version = 1
  targets = @([ordered]@{
      id = 'smuggle'; name = 'multi-path target'; enabled = $true; tier = 'safe'; requiresAdmin = $false
      type = 'dir'; paths = @($okDir, $badDir); glob = ''
      preCommands = @(); stopProcesses = @(); stopServices = @(); risk = 'regression fixture'
      signals = 'safe-signal'; origin = 'c_cleaner_plus'; category = 'general'; sourceFile = 'test'
    })
}
[System.IO.File]::WriteAllText($mergedPath, ($merged | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($true)))
[void](Invoke-Engine @('-Mode', 'Scan', '-Config', $cfgWl, '-Tiers', 'safe', '-RuleSets', 'general', '-PathFilter', 'whitelist'))
$r = Invoke-Engine @('-Mode', 'Clean', '-Config', $cfgWl, '-Ids', 'smuggle', '-Tiers', 'safe', '-RuleSets', 'general', '-PathFilter', 'whitelist', '-HotMinutes', '0')
Assert-True (Test-Path -LiteralPath (Join-Path $badDir 'unauthorized.dat')) 'H3 non-whitelisted path of a kept target SURVIVED' 'whitelist bypassed via path-set piggybacking'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $okDir 'junk.tmp'))) 'H3 whitelisted path still cleaned'
Write-Host ''

Write-Host '=== H4: Clean must be bound to the scan plan scope ==='
# Defect: the plan gate only checked that last-scan.json was <30 min old, so a Scan of one id set
# authorized cleaning any other id set.
$a = New-Fixture 'plan_a'
$b = New-Fixture 'plan_b'
New-BigFile (Join-Path $a 'junk.tmp')                        # in-scope -> must be cleaned
New-Canary  (Join-Path $b 'other.dat') 'MUST-SURVIVE'        # out-of-scope -> must survive
New-BigFile (Join-Path $b 'bulk.bin')
$cfgPlan = Write-Config 'plan.json' @(
  [ordered]@{ id = 'plan-a'; name = 'A'; enabled = $true; tier = 'safe'; requiresAdmin = $false
    type = 'dir'; paths = @($a); glob = ''; preCommands = @(); stopProcesses = @(); stopServices = @(); risk = 'f' }
  [ordered]@{ id = 'plan-b'; name = 'B'; enabled = $true; tier = 'safe'; requiresAdmin = $false
    type = 'dir'; paths = @($b); glob = ''; preCommands = @(); stopProcesses = @(); stopServices = @(); risk = 'f' }
)
# Scan ONLY plan-a, then try to Clean plan-b -> must be blocked (exit 4)
[void](Invoke-Engine @('-Mode', 'Scan', '-Config', $cfgPlan, '-Ids', 'plan-a', '-Tiers', 'safe', '-PathFilter', 'off'))
$r = Invoke-Engine @('-Mode', 'Clean', '-Config', $cfgPlan, '-Ids', 'plan-b', '-Tiers', 'safe', '-PathFilter', 'off', '-HotMinutes', '0')
Assert-True ($r.code -eq 4) 'H4 out-of-scope Clean blocked (exit 4)' ("exit=" + $r.code)
Assert-True (Test-Path -LiteralPath (Join-Path $b 'other.dat')) 'H4 out-of-scope target untouched'
# and the in-scope Clean still works
$r = Invoke-ScanThenClean $cfgPlan @('-Ids', 'plan-a', '-Tiers', 'safe')
Assert-True (-not (Test-Path -LiteralPath (Join-Path $a 'junk.tmp'))) 'H4 in-scope Clean still succeeds'
Write-Host ''

Write-Host '=== M1: -Ids / -ConfirmIds must reject command-line injection characters ==='
# Defect: these strings were interpolated into the ELEVATED child's command line inside double
# quotes, so an embedded quote injected extra script parameters into an admin process.
$badIds = @(
  @{ label = 'backtick';    value = 'globtest`n-Tiers dangerous' },   # backtick
  @{ label = 'dollar sign'; value = 'globtest$x' }                    # dollar sign
)
foreach ($bad in $badIds) {
  $r = Invoke-Engine @('-Mode', 'Clean', '-Config', $cfgGlob, '-Ids', $bad.value, '-Tiers', 'safe', '-DryRun')
  Assert-True ($r.code -eq 3) ("M1 rejected malicious -Ids: " + $bad.label) ("exit=" + $r.code)
}
# Quote breakout: the payload MUST be delivered through a hand-built command line with doubled
# quotes. Via the array helper, PS 5.1 native quoting splits it at the CRT layer and the engine
# would see innocent separate parameters (exit 0) — testing nothing.
$rawPayload = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode Clean -Config "{1}" -Ids "globtest"" -Tiers dangerous" -Tiers safe -DryRun' -f $engine, $cfgGlob
$r = Invoke-EngineRaw $rawPayload
Assert-True ($r.code -eq 3) 'M1 rejected malicious -Ids: quote breakout (literal delivered)' ("exit=" + $r.code)
Assert-True ($r.out -match 'command-line injection guard') 'M1 rejection names the injection guard'
# Positive control through the SAME raw path: a legitimate quoted id must still exit 0,
# proving the raw harness itself does not mangle ordinary quoting.
$rawOk = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode Clean -Config "{1}" -Ids "globtest" -Tiers safe -DryRun' -f $engine, $cfgGlob
$r = Invoke-EngineRaw $rawOk
Assert-True ($r.code -eq 0) 'M1 raw path accepts legitimate quoted id' ("exit=" + $r.code)
$r = Invoke-Engine @('-Mode', 'Scan', '-Config', $cfgGlob, '-Ids', 'globtest', '-Tiers', 'safe', '-PathFilter', 'off')
Assert-True ($r.code -eq 0) 'M1 legitimate id still accepted'
# CONTRACT PRESERVED: a raw path as an id must still reach the whitelist check and be reported as
# status "error" (not a hard exit) — this is the documented unknown-id behaviour verify_safety tests.
$r = Invoke-Engine @('-Mode', 'Clean', '-Config', $cfgGlob, '-Ids', 'C:\Windows\System32', '-Tiers', 'safe', '-DryRun')
$uid = $null
if ($r.json) { $uid = @($r.json.items | Where-Object { $_.origin -eq 'none' }) | Select-Object -First 1 }
Assert-True ($uid -and $uid.status -eq 'error') 'M1 raw-path id still yields status=error (contract intact)' ("status=" + $(if ($uid) { $uid.status } else { '(no json/item)' }))
Write-Host ''

Write-Host '=== M3 / M7 / M9: parser + guard + wildcard unit checks (AST-extracted) ==='
$ast = [System.Management.Automation.Language.Parser]::ParseInput(
  [System.IO.File]::ReadAllText($engine, [System.Text.Encoding]::UTF8), [ref]$null, [ref]$null)
foreach ($fn in @('Expand-EnvPath', 'ConvertTo-NormPath', 'Test-GuardrailBlocked', 'Test-PathAgainstWhitelist')) {
  $f = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true) | Select-Object -First 1
  if ($f) { Invoke-Expression $f.Extent.Text }
}
$gp = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Script:GuardPatterns' }, $true) | Select-Object -First 1
if ($gp) { Invoke-Expression $gp.Extent.Text }

# M7: normalized %WINDIR% forms must hit the same guards as the absolute forms
foreach ($p in @('%WINDIR%\Servicing', '%WINDIR%\Servicing\Packages', '%WINDIR%\inf', '%WINDIR%\inf\oem0.inf',
                 '%WINDIR%\Boot', 'C:\Windows\Boot\BCD', 'C:\Windows\Boot')) {
  Assert-True ([bool](Test-GuardrailBlocked $p)) ("M7 guarded: " + $p)
}
foreach ($p in @('%LOCALAPPDATA%\Temp', '%APPDATA%\Code\Cache', '%WINDIR%\Temp', '%WINDIR%\Logs\CBS')) {
  Assert-True (-not (Test-GuardrailBlocked $p)) ("M7 still allowed: " + $p)
}

# M9: wildcard detection must be a real asterisk test, not `-like '*\*'`
$wlWild = @('C:\Users\X\AppData\Local\Packages\*\TempState')
Assert-True ([bool](Test-PathAgainstWhitelist 'C:\Users\X\AppData\Local\Packages\App1\TempState' $wlWild)) 'M9 wildcard entry matches'
Assert-True (-not (Test-PathAgainstWhitelist 'C:\Users\X\Documents\secret' $wlWild)) 'M9 unrelated path not matched'
Assert-True (-not (Test-PathAgainstWhitelist 'C:\anything' @())) 'M9 empty whitelist denies all (fail-closed)'

# M3: the 7-tuple form keeps its glob (parser branch that previously never read index 6)
$mergeAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ConfigMerge' }, $true) | Select-Object -First 1
$mergeSrc = if ($mergeAst) { $mergeAst.Extent.Text } else { '' }
Assert-True ($mergeSrc -match '\$arr\.Count -ge 7 -and \$arr\[6\] -is \[string\]') 'M3 7-tuple glob is read at index 6'
Assert-True ($mergeSrc -match 'unsupportedType') 'M4 unsupported source type is tracked, not silently coerced'
Assert-True ($mergeSrc -match '-not \(\$ex\.sources -contains \$f\.Name\)') 'M8 -contains precedence parenthesised'
Write-Host ''

Write-Host '=== C1b: glob survives the merge pipeline into the item (end-to-end) ==='
# Regex on the source text is fragile here: the $items hashtable contains nested script blocks,
# and a non-greedy \{.*?\} stops at the FIRST closing brace, long before the glob line. The
# glob-bearing hashtable also lives inside a METHOD CALL ($items.Add(...)), not an assignment,
# so extract that invocation node via the AST and inspect its full extent.
$itemNode = $ast.FindAll(
  { param($n) $n.Extent.Text -match '(?s)^\$items\.Add\(' },
  $true) | Select-Object -First 1
$itemSrc = if ($itemNode) { $itemNode.Extent.Text } else { '' }
Assert-True ($itemSrc -match '(?m)^\s*glob\s*=') 'C1b item object carries glob'
Write-Host ''

Write-Host '=== INV: a state source must never re-enable an entry classified dangerous ==='
# Defect: the dedupe branch let a "state" source (cdisk_cleaner_config*) overwrite `enabled` using a
# tier computed from ITS OWN row, while the surviving entry kept the more conservative tier from an
# earlier source. The red line "dangerous => disabled" was only holding because tier happened to be
# a pure function of the path; as soon as tier depends on source metadata (an unsupported type such
# as BleachBit's "contents"), a state row with checkbox=1 could switch a dangerous entry back on.
$invRules = Join-Path $sandbox 'invrules'
New-Item -ItemType Directory -Path $invRules -Force | Out-Null
$sharedPath = '%LOCALAPPDATA%\ZzRegressionProbe\Cache'
# curated file (rank 0, processed first): unsupported type => forced dangerous + disabled
$firstTuple = @(, @('probe entry', $sharedPath, 'contents', $false, 'unsupported type on purpose'))
# ConvertTo-Json via the PIPELINE enumerates the outer array (classic PS gotcha), flattening
# [[tuple]] into [tuple]; every "row" then parses as a bare string and the whole file silently
# fails. -InputObject serializes the nested shape intact.
[System.IO.File]::WriteAllText(
  (Join-Path $invRules 'a_first_rules.json'),
  (ConvertTo-Json -InputObject $firstTuple -Depth 5),
  (New-Object System.Text.UTF8Encoding($true)))
# state export (rank 2, processed last): same path, plain dir, checkbox = 1 => wants enabled
$stateTupleJson = (@('probe entry', $sharedPath, 'dir', 'state row', $false, '') | ConvertTo-Json -Compress)
$stateElem = (@($stateTupleJson, 1) | ConvertTo-Json -Compress)
$stateDoc = [ordered]@{ version = 2; key_mode = 'rule_token'; order = @($stateElem) }
[System.IO.File]::WriteAllText(
  (Join-Path $invRules 'cdisk_cleaner_config.json'),
  ($stateDoc | ConvertTo-Json -Depth 5),
  (New-Object System.Text.UTF8Encoding($true)))

$invCfgDir = Join-Path $sandbox 'invcfg'
New-Item -ItemType Directory -Path $invCfgDir -Force | Out-Null
$invCfg = Join-Path $invCfgDir 'targets.json'
[System.IO.File]::WriteAllText($invCfg, ([ordered]@{
      version = 2; drive = 'C'
      mergeSources = @($invRules)      # absolute path -> used as-is
      externalMergeSources = @()
      targets = @()
    } | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($true)))

$r = Invoke-Engine @('-Mode', 'MergeConfig', '-Config', $invCfg)
Assert-True ($r.code -eq 0) 'INV MergeConfig completed' ("exit=" + $r.code)
$invMerged = Join-Path $invCfgDir 'targets.merged.json'
if (-not (Test-Path -LiteralPath $invMerged)) {
  Assert-True $false 'INV merged artifact written' 'targets.merged.json missing'
} else {
  $md = Get-Content -LiteralPath $invMerged -Raw -Encoding UTF8 | ConvertFrom-Json
  $probe = @($md.targets | Where-Object { ([string]$_.paths) -like '*ZzRegressionProbe*' }) | Select-Object -First 1
  Assert-True ($null -ne $probe) 'INV probe entry present in merged output'
  if ($probe) {
    Assert-True ([string]$probe.tier -eq 'dangerous') 'INV unsupported type forced tier=dangerous' ("tier=" + $probe.tier)
    Assert-True (-not [bool]$probe.enabled) 'INV dangerous entry NOT enabled by the state source' 'RED LINE BREACH: state override enabled a dangerous target'
  }
  $viol = @($md.targets | Where-Object { [string]$_.tier -eq 'dangerous' -and [bool]$_.enabled })
  Assert-True ($viol.Count -eq 0) 'INV zero dangerous+enabled entries in artifact' ("violations=" + $viol.Count)
  if ($r.json -and $r.json.merge) {
    Assert-True ([int]$r.json.merge.dangerousEnabledViolations -eq 0) 'INV stats report zero violations' ("reported=" + $r.json.merge.dangerousEnabledViolations)
  }
}
Write-Host ''

# ---------------------------------------------------------------------------
if (-not $KeepSandbox) {
  # Remove the sandbox WITHOUT following the junctions we created.
  foreach ($lp in @($linkPath, $linkRoot)) {
    if ($lp -and (Test-Path -LiteralPath $lp)) {
      try { [System.IO.Directory]::Delete($lp, $false) } catch {}
    }
  }
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Host ("sandbox kept: {0}" -f $sandbox)
}

Write-Host ''
Write-Host ('RESULT: {0} passed, {1} failed' -f $pass, $fail)
if ($fail -eq 0) { Write-Host 'ALL REGRESSION CHECKS PASSED' -ForegroundColor Green }
exit $fail
