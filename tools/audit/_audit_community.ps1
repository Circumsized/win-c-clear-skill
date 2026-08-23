$c = Get-Content "assets/rules/community_cleaners.json" -Raw -Encoding UTF8 | ConvertFrom-Json
"Total community cleaners entries: $($c.Count)"