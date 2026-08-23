$json = Get-Content "config/targets.json" -Raw -Encoding UTF8 | ConvertFrom-Json
"=== ALL TARGETS ==="
$json.targets | Select-Object id, tier, enabled, type, paths | Format-Table -AutoSize
"`n=== DANGEROUS ENABLED TARGETS ==="
$json.targets | Where-Object { $_.tier -eq 'dangerous' -and $_.enabled -eq $true } | Select-Object id, name, tier, enabled