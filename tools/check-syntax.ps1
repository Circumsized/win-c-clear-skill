param([string]$Path)
# 缺失/空白路径必须失败；否则 ParseFile 的非终止错误被吞，会假报 SYNTAX OK
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
  Write-Host ("ERROR: file not found: {0}" -f $Path)
  exit 1
}
$tokens = $null
$errors = $null
$srcText = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
[System.Management.Automation.Language.Parser]::ParseInput($srcText, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
  foreach ($e in $errors) { Write-Host ("{0}:{1} {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message) }
  exit 1
}
Write-Host 'SYNTAX OK'
exit 0
