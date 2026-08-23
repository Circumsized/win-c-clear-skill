# Deep audit of winapp2 entries
$w = Get-Content "assets/rules/winapp2_latest.json" -Raw -Encoding UTF8 | ConvertFrom-Json

# Check for entries with missing fields
Write-Host "=== WINAPP2: INCOMPLETE ENTRIES (missing fields) ==="
$missingFields = 0
$badEntries = @()
$i = 0
foreach ($entry in $w) {
    $i++
    $has = $null -ne $entry
    if (-not $entry.PSObject.Properties.Name.Contains('Name')) {
        $badEntries += $i
        $missingFields++
    }
}
Write-Host "Entries with missing 'Name' field: $missingFields"
if ($badEntries.Count -gt 0) { Write-Host "First 10 bad indices: $($badEntries[0..9])" }

# Check for potentially dangerous file removal patterns
Write-Host "`n=== WINAPP2: CHECKING FOR DANGEROUS PATTERNS ==="
$dangerousCount = 0
$dangerousPatterns = @()
$dangerousKeywords = @("REMOVESELF", "System32", "Windows\", "SystemDrive\boot", "SystemDrive\Windows")
foreach ($entry in $w) {
    $entryStr = $entry | ConvertTo-Json -Compress
    if ($entryStr -match "REMOVESELF") { $dangerousCount++ }
}
Write-Host "Entries with REMOVESELF: $dangerousCount"

# Check community cleaners
$c = Get-Content "assets/rules/community_cleaners.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "`n=== COMMUNITY CLEANERS ANALYSIS ==="
Write-Host "Total entries: $($c.Count)"
# Check for null entries
$nullEntries = 0
foreach ($entry in $c) {
    if ($null -eq $entry -or $null -eq $entry.Name) { $nullEntries++ }
}
Write-Host "Null or missing Name entries: $nullEntries"

# Check cdisk_cleaner_config.json
$cc = Get-Content "assets/rules/cdisk_cleaner_config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "`n=== CDISK_CLEANER_CONFIG ==="
Write-Host "Properties: $($cc.PSObject.Properties.Name -join ', ')"
if ($cc.PSObject.Properties.Name -contains 'stats') {
    Write-Host "Stats:"
    $cc.stats | Format-List
}
if ($cc.PSObject.Properties.Name -contains 'totalEntries') {
    Write-Host "Total entries: $($cc.totalEntries)"
}
if ($cc.PSObject.Properties.Name -contains 'targets') {
    Write-Host "Target count: $($cc.targets.Count)"
}

# Check cdisk_cleaner_custom_rules.json
$cr = Get-Content "assets/rules/cdisk_cleaner_custom_rules.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "`n=== CDISK_CLEANER_CUSTOM_RULES ==="
Write-Host "Properties: $($cr.PSObject.Properties.Name -join ', ')"
if ($cr.PSObject.Properties.Name -contains 'stats') {
    Write-Host "Stats:"
    $cr.stats | Format-List
}
if ($cr.PSObject.Properties.Name -contains 'totalEntries') {
    Write-Host "Total entries: $($cr.totalEntries)"
}
if ($cr.PSObject.Properties.Name -contains 'targets') {
    Write-Host "Target count: $($cr.targets.Count)"
}

# Check for guardrail demoted entries in merged
Write-Host "`n=== MERGED: GUARDRAIL DEMOTED DETAILS ==="
$m = Get-Content "config/targets.merged.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "Guardrail demoted count: $($m.stats.guardrailDemoted)"
Write-Host "Path collisions: $($m.stats.pathCollisionsWithBuiltin)"
Write-Host "Unparsed entries: $($m.stats.unparsedCount)"

# Check the dangerous tier entries in merged
$dangerousMerged = $m.targets | Where-Object { $_.tier -eq 'dangerous' }
Write-Host "`n=== MERGED: DANGEROUS TIER TARGETS ==="
$dangerousMerged | Select-Object id, name, enabled, @{N='pathsCount';E={($_.paths | Measure-Object).Count}} | Format-Table -AutoSize

# Check for targets that have both enabled and dangerous in merged
$dangerousEnabledMerged = $dangerousMerged | Where-Object { $_.enabled -eq $true }
Write-Host "`nDangerous AND enabled targets in merged: $($dangerousEnabledMerged.Count)"
$dangerousEnabledMerged | Select-Object id, name, tier, enabled | Format-Table -AutoSize

# Check scan-lists blacklist for dangerous patterns
Write-Host "`n=== SCAN-LISTS: FULL BLACKLIST ANALYSIS ==="
$sl = Get-Content "config/scan-lists.json" -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $sl.blacklist.entries) {
    Write-Host "`nID: $($entry.id)"
    Write-Host "Name: $($entry.name)"
    Write-Host "Patterns: $($entry.patterns -join ', ')"
    Write-Host "Reason: $($entry.reason)"
}

# Analyze whitelist for paths that might overlap with protected areas
Write-Host "`n=== SCAN-LISTS: WHITELIST FULL PATHS ==="
foreach ($entry in $sl.whitelist.entries) {
    Write-Host "`nID: $($entry.id)"
    Write-Host "Name: $($entry.name)"
    $pathsStr = $entry.paths -join ', '
    if ($pathsStr.Length -gt 200) { $pathsStr = $pathsStr.Substring(0, 200) + '...' }
    Write-Host "Paths: $pathsStr"
}

# Check for format issues in targets.json
Write-Host "`n=== TARGETS.JSON: FORMAT CHECKS ==="
$tj = Get-Content "config/targets.json" -Raw -Encoding UTF8 | ConvertFrom-Json
# Check for duplicate IDs
$ids = $tj.targets | Select-Object -ExpandProperty id
$dupes = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
if ($dupes.Count -gt 0) {
    Write-Host "DUPLICATE IDs FOUND:"
    $dupes | Format-Table -AutoSize
} else {
    Write-Host "No duplicate IDs found"
}
# Check for null/empty IDs
$nullIds = $tj.targets | Where-Object { [string]::IsNullOrEmpty($_.id) }
Write-Host "Null/empty IDs: $($nullIds.Count)"
# Check for targets with no paths
$noPaths = $tj.targets | Where-Object { $null -eq $_.paths -or $_.paths.Count -eq 0 -and $_.type -ne 'special' }
Write-Host "Targets with no paths (non-special): $($noPaths.Count)"
if ($noPaths.Count -gt 0) {
    $noPaths | Select-Object id, name, type, enabled | Format-Table -AutoSize
}

# Final summary
Write-Host "`n`n==================== AUDIT SUMMARY ===================="
Write-Host "Rule files checked:"
Write-Host "  - targets.json (builtin): $($tj.targets.Count) targets"
Write-Host "  - targets.merged.json: $($m.targets.Count) targets (when merged)"
Write-Host "  - winapp2_latest.json: $($w.Count) entries"
Write-Host "  - community_cleaners.json: $($c.Count) entries"
Write-Host "  - cdisk_cleaner_config.json: $($cc.Count) entries"
Write-Host "  - scan-lists.json: $($sl.whitelist.entries.Count) whitelist, $($sl.blacklist.entries.Count) blacklist"
Write-Host "Dangerous builtin targets enabled: $($dangerousEnabledMerged.Count)"
Write-Host "Guardrail demotions in merge: $($m.stats.guardrailDemoted)"
Write-Host "Path collisions with builtin: $($m.stats.pathCollisionsWithBuiltin)"
Write-Host "Unparsed entries: $($m.stats.unparsedCount)"