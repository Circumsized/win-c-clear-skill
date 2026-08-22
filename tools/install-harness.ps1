#Requires -Version 5.1
<#
.SYNOPSIS
  Install win-c-clear-skill into agent harness skill directories.
.DESCRIPTION
  Harness conventions (verified against upstream repos, Aug 2026):
    - Claude Code  : ~/.claude/skills/<skill>/          (personal)  + .claude/skills/ (project)
                    source study: github.com/OrcaWhisper/Claude-Code (v2.1.88 source archive)
    - deepseek-harness (dsh): ~/.agents/skills/<skill>/ (user) + .agents/skills/ (project)
                    source study: github.com/deepseek-ai/deepseek-harness (.agents/ convention,
                    Claude-compatible skill format)
    - codex        : ~/.codex/skills/<skill/            (personal) + AGENTS.md pointer
                    source study: github.com/openai/codex (.codex/ convention)
    - Trae / Cursor: ~/.trae/skills, ~/.cursor/skills  (bonus)
.PARAMETER Targets
  Comma-separated: claude,codex,deepseek,trae,cursor,claude-project,deepseek-project
.PARAMETER All
  Install to claude + codex + deepseek (user-level).
.PARAMETER Symlink
  Create a directory junction instead of copying (updates propagate automatically).
.EXAMPLE
  powershell -File tools\install-harness.ps1 -All
  powershell -File tools\install-harness.ps1 -Targets codex -Symlink
#>
param(
  [string]$Targets = '',
  [switch]$All,
  [switch]$Symlink,
  [switch]$List
)
$skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$skillName = Split-Path -Leaf $skillRoot

$map = [ordered]@{
  'claude'         = Join-Path $env:USERPROFILE '.claude\skills'
  'codex'          = Join-Path $env:USERPROFILE '.codex\skills'
  'deepseek'       = Join-Path $env:USERPROFILE '.agents\skills'
  'trae'           = Join-Path $env:USERPROFILE '.trae\skills'
  'cursor'         = Join-Path $env:USERPROFILE '.cursor\skills'
  'claude-project' = '.claude\skills'
  'deepseek-project' = '.agents\skills'
}

if ($List) {
  Write-Output 'Available targets:'
  foreach ($k in $map.Keys) { Write-Output ("  {0,-16} -> {1}" -f $k, $map[$k]) }
  exit 0
}
if ($All) { $Targets = 'claude,codex,deepseek' }
if (-not $Targets) { Write-Host 'No target. Use -All, -Targets <list> or -List.'; exit 1 }

$chosen = @($Targets -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
foreach ($c in $chosen) {
  if (-not $map.Contains($c)) { Write-Host "[SKIP] unknown target: $c"; continue }
  $destRoot = $map[$c]
  $dest = Join-Path $destRoot $skillName
  try {
    if (-not (Test-Path $destRoot)) { New-Item -ItemType Directory -Path $destRoot -Force | Out-Null }
    if (Test-Path $dest) {
      if (-not $Symlink) { Remove-Item $dest -Recurse -Force }
    }
    if ($Symlink) {
      if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
      New-Item -ItemType Junction -Path $dest -Target $skillRoot -ErrorAction Stop | Out-Null
      Write-Host "[OK] junction: $dest -> $skillRoot"
    } else {
      Copy-Item $skillRoot $dest -Recurse -Force
      Write-Host "[OK] copied to: $dest"
    }
  } catch { Write-Host "[FAIL] ${c}: $($_.Exception.Message)" }
}

Write-Host ''
Write-Host 'Post-install hints:'
Write-Host '  Claude Code / deepseek-harness: restart the CLI or start a new session, then say'
Write-Host ('    "C drive full, use {0} to scan" / "C盘满了，用 {0} 扫描"' -f $skillName)
Write-Host '  codex: add one line to AGENTS.md (project or ~/.codex/AGENTS.md):'
Write-Host ('    Windows C: cleanup: use the {0} skill (see .codex/skills/{0}/SKILL.md)' -f $skillName)
Write-Host '  Optional: junction install (-Symlink) keeps the skill in sync with this repo.'
