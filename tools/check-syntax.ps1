param([string]$Path)
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  foreach ($e in $errors) { Write-Host ("{0}:{1} {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message) }
  exit 1
}
Write-Host 'SYNTAX OK'
exit 0
