$w = Get-Content "assets/rules/winapp2_latest.json" -Raw -Encoding UTF8 | ConvertFrom-Json
"Total winapp2 entries: $($w.Count)"
$w | Select-Object -First 5 | Format-Table -AutoSize