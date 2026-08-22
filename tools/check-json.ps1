$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$files = @(
  (Join-Path $root 'config\targets.json'),
  (Join-Path $root 'config\scan-lists.json')
)
$fail = 0
foreach ($f in $files) {
  try {
    Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    Write-Host ("JSON OK  {0}" -f (Split-Path -Leaf $f))
  } catch {
    Write-Host ("JSON FAIL {0}: {1}" -f (Split-Path -Leaf $f), $_.Exception.Message)
    $fail = 1
  }
}
exit $fail
