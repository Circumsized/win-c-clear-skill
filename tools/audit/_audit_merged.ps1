if (Test-Path "config/targets.merged.json") {
  $m = Get-Content "config/targets.merged.json" -Raw -Encoding UTF8 | ConvertFrom-Json
  "=== MERGED STATS ==="
  $m.stats | Format-List
  "`n=== TIER HISTOGRAM ==="
  $m.stats.tierHistogram
  "`n=== SIGNALS HISTOGRAM ==="
  $m.stats.signalsHistogram
  "`n=== DANGEROUS ENABLED IN MERGED ==="
  $m.targets | Where-Object { $_.tier -eq 'dangerous' -and $_.enabled -eq $true } | Select-Object id, name, tier, enabled
} else {
  "No merged config found"
}