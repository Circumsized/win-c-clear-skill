$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
# replicate the exact filter chain from the engine to see what allTargets contains at Analyze time
$cfg = Get-Content -LiteralPath "$root\config\targets.merged.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$lists = Get-Content -LiteralPath "$root\config\scan-lists.json" -Raw -Encoding UTF8 | ConvertFrom-Json

function Expand-EnvPath([string]$PathText) {
  if ([string]::IsNullOrWhiteSpace($PathText)) { return $PathText }
  $t = $PathText
  if ($t.IndexOf('%') -ge 0) {
    foreach ($name in @('LOCALAPPDATA','APPDATA','USERPROFILE','TEMP','TMP','ProgramData','WinDir','ProgramFiles','ProgramFiles(x86)','SystemDrive','PUBLIC','HOMEDRIVE','HOMEPATH')) {
      $v = [Environment]::GetEnvironmentVariable($name, 'Process')
      if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, 'Machine') }
      if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, 'User') }
      if ($v) { $t = [regex]::Replace($t, ('%' + [regex]::Escape($name) + '%'), $v.Replace('$', '$$'), 'IgnoreCase') }
    }
  }
  return [Environment]::ExpandEnvironmentVariables($t)
}

# minimal rule-set filter (builtin category only)
$kept = New-Object System.Collections.Generic.List[object]
foreach ($t in @($cfg.targets)) {
  if (-not $t.enabled) { continue }
  $cat = [string]$t.category
  if (-not $cat) { $cat = if ($t.origin -in @('builtin', 'merged')) { 'builtin' } else { 'general' } }
  if ($cat -eq 'builtin') { $kept.Add($t) }
}
Write-Host ("minimal targets: {0}" -f $kept.Count)

# now resolve roots exactly like the Analyze branch does
$ruleResolvableRoots = New-Object System.Collections.Generic.HashSet[string]
foreach ($t in $kept) {
  foreach ($p in @($t.paths)) {
    $ep = Expand-EnvPath ([string]$p)
    if ($ep -and (Test-Path -LiteralPath $ep -ErrorAction SilentlyContinue)) {
      [void]$ruleResolvableRoots.Add($ep)
    }
  }
}
$roots = @($ruleResolvableRoots)
Write-Host ("resolved roots: {0}" -f $roots.Count)
$roots | Select-Object -First 15
