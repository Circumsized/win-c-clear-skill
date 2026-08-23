$sl = Get-Content "config/scan-lists.json" -Raw -Encoding UTF8 | ConvertFrom-Json
"Whitelist enabled: $($sl.whitelist.enabled)"
"Whitelist entries: $($sl.whitelist.entries.Count)"
"Blacklist enabled: $($sl.blacklist.enabled)"
"Blacklist entries: $($sl.blacklist.entries.Count)"
"`n=== SCAN MODES ==="
$sl.scanModes
"`n=== WHITELIST ENTRIES (first 20) ==="
$sl.whitelist.entries | Select-Object -First 20
"`n=== BLACKLIST ENTRIES (first 20) ==="
$sl.blacklist.entries | Select-Object -First 20