$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$files = @()
# 覆盖 config 下全部 JSON（含 targets.example.json）与 assets/rules 下全部规则 JSON
$files += Get-ChildItem -LiteralPath (Join-Path $root 'config') -Filter '*.json' -File | ForEach-Object { $_.FullName }
$rulesDir = Join-Path $root 'assets\rules'
if (Test-Path -LiteralPath $rulesDir) {
  $files += Get-ChildItem -LiteralPath $rulesDir -Filter '*.json' -File | ForEach-Object { $_.FullName }
}
$fail = 0
# 零文件即失败：枚举路径错误时静默 exit 0 会造成"全部通过"的假象
if ($files.Count -eq 0) {
  Write-Host 'JSON FAIL no *.json found under config/ or assets/rules/'
  exit 1
}
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
