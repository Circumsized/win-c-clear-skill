#Requires -Version 5.1
<#
.SYNOPSIS
  win-c-clear-skill engine: scan / clean / analyze / merge-config for Windows C: drive caches.
.DESCRIPTION
  Agent-adaptive C: drive cleanup engine with three-tier risk model, scan-before-delete,
  c_cleaner_plus rule merge pipeline, runspace-parallel scanning, elevation with result
  pass-back, and a stable JSON_SUMMARY contract for agent parsing.
  Console output is English (encoding stability). The agent translates for the user.
.PARAMETER Mode
  Scan | Clean | Analyze | MergeConfig
.PARAMETER Config
  Path to targets.json (defaults to ../config/targets.json next to this script)
.PARAMETER Ids
  Comma-separated target ids to include (optional filter)
.PARAMETER Tiers
  Comma-separated tiers: safe,caution,dangerous (default: Scan=safe,caution / Clean=safe)
.PARAMETER ConfirmIds
  REQUIRED for cleaning caution/dangerous targets: comma-separated ids the user explicitly confirmed
.PARAMETER Elevate
  Re-launch elevated (UAC) when selected targets require admin
.PARAMETER LogPath
  Optional log file path (default: <skill-root>\logs\win-c-clear-skill_log_<timestamp>.txt)
.PARAMETER DryRun
  Walk the full clean pipeline but delete nothing (audit / rehearsal)
.PARAMETER MaxThreads
  Override parallel thread count (default: logical processor count)
.PARAMETER AllowStop
  Permit stopping processes/services listed in target stopProcesses/stopServices
.PARAMETER BackupDangerous
  Back up dangerous-tier targets to Desktop before deletion
.PARAMETER TrimWorkingSet
  After clean, trim working set (EmptyWorkingSet) of processes named in cleaned targets
.PARAMETER CCPDirs
  Comma-separated c_cleaner_plus rule directories (overrides config mergeSources)
.PARAMETER ResultFile
  Internal: path where an elevated child writes its JSON_SUMMARY back to the parent
.PARAMETER ReportFile
  Optional: path for the structured Chinese Markdown cleanup report (.md).
  Defaults to <skill-root>\reports\win-c-clear-report_<timestamp>.md
#>
param(
  [ValidateSet('Scan','Clean','Analyze','MergeConfig')]
  [string]$Mode = 'Scan',
  [string]$Config = '',
  [string]$Ids = '',
  [string]$Tiers = '',
  [string]$ConfirmIds = '',
  [switch]$Elevate,
  [string]$LogPath = '',
  [switch]$DryRun,
  [int]$MaxThreads = 0,
  [switch]$AllowStop,
  [switch]$BackupDangerous,
  [switch]$TrimWorkingSet,
  [string]$CCPDirs = '',
  [string]$ResultFile = '',
  [string]$ReportFile = '',
  [int]$TopN = 60,
  [switch]$PrettyJson,
  [ValidateSet('conservative','standard','deep')]
  [string]$Policy = 'standard',
  [switch]$NoCache,
  [ValidateSet('permanent','recycle','quarantine')]
  [string]$RecoveryMode = 'permanent',
  [int]$HotMinutes = 30,
  [string]$RuleSets = 'minimal',
  [ValidateSet('fast','standard','deep')]
  [string]$ScanMode = 'standard',
  [switch]$NoMft,
  [string]$PlanFile = '',
  [ValidateSet('off','whitelist','blacklist','both')]
  [string]$PathFilter = 'whitelist',
  [switch]$NoWhitelist,
  [switch]$NoBlacklist
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$Script:StartedAt = Get-Date
# UTF-8 console output so JSON_SUMMARY parses correctly regardless of system codepage
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ============================================================
# Basic utilities
# ============================================================
function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Expand-EnvPath([string]$PathText) {
  if ([string]::IsNullOrWhiteSpace($PathText)) { return $PathText }
  # [Environment]::ExpandEnvironmentVariables only knows the PROCESS env block;
  # user/shell vars (%LOCALAPPDATA%, %APPDATA%, %ProgramFiles%, %WinDir%) are NOT in it,
  # so expand via PowerShell's own provider first (it resolves the full registry set),
  # then let .NET handle any leftovers.
  $t = $PathText
  if ($t.IndexOf('%') -ge 0) {
    # robust route: expand using Process -> Machine -> User env lookups
    foreach ($name in @('LOCALAPPDATA','APPDATA','USERPROFILE','TEMP','TMP','ProgramData','WinDir','ProgramFiles','ProgramFiles(x86)','SystemDrive','PUBLIC','HOMEDRIVE','HOMEPATH')) {
      $v = [Environment]::GetEnvironmentVariable($name, 'Process')
      if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, 'Machine') }
      if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, 'User') }
      if ($v) { $t = [regex]::Replace($t, ('%' + [regex]::Escape($name) + '%'), $v.Replace('$', '$$'), 'IgnoreCase') }
    }
  }
  return [Environment]::ExpandEnvironmentVariables($t)
}

function Get-Round2([double]$v) { return [math]::Round($v, 2) }
function Get-BytesToGB([double]$bytes) { return [math]::Round($bytes / 1GB, 2) }

function Get-OSInfo {
  $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
  $caption = if ($os) { [string]$os.Caption } else { 'Unknown' }
  $build = if ($os) { [string]$os.BuildNumber } else { '' }
  $isServer = $caption -match 'Server'
  return @{ caption = $caption; build = $build; isServer = [bool]$isServer }
}

function Get-DriveFreeGB([string]$letter) {
  try {
    $d = Get-PSDrive -Name $letter -ErrorAction Stop
    return [math]::Round($d.Free / 1GB, 2)
  } catch { return -1 }
}

# ============================================================
# Path normalization (merge pipeline step 3)
# ============================================================
function ConvertTo-NormPath([string]$RawPath) {
  if ([string]::IsNullOrWhiteSpace($RawPath)) { return '' }
  # Use the same Process -> Machine -> User expansion as Expand-EnvPath so that
  # normalization is consistent across hosts/users (portability red line).
  $full = Expand-EnvPath $RawPath
  $full = $full -replace '/', '\'
  $full = $full -replace '\\+', '\'
  $full = $full.TrimEnd('\')
  if ([string]::IsNullOrWhiteSpace($full)) { return '' }
  # Longest-prefix env replacement wins (TEMP before LOCALAPPDATA before USERPROFILE ...)
  $map = @{}
  foreach ($name in @('LOCALAPPDATA','APPDATA','USERPROFILE','TEMP','TMP','ProgramData','WinDir','ProgramFiles','ProgramFiles(x86)','SystemDrive','PUBLIC')) {
    $v = [Environment]::GetEnvironmentVariable($name, 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, 'Machine') }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, 'User') }
    if ($v) { $map[$name] = $v.TrimEnd('\') }
  }
  $pairs = $map.GetEnumerator() | Sort-Object { $_.Value.Length } -Descending
  foreach ($kv in $pairs) {
    $v = $kv.Value
    if ($full.StartsWith($v, [StringComparison]::OrdinalIgnoreCase)) {
      $rest = $full.Substring($v.Length)
      if ($rest -eq '' -or $rest.StartsWith('\')) {
        $out = '%' + $kv.Key + '%' + ($rest -replace '\\+', '\')
        return $out
      }
    }
  }
  return $full
}

# ============================================================
# Tier classification v2 (merge pipeline step 5)
# Compiled-regex signal classes, precedence: dangerous > caution > safe.
# Unknown -> dangerous (red line: never guess safe).
# Studied: bleachbit cleaners semantics + winapp2 community conventions +
# WindowsClear/zhenhuaDiskCleaner conservative handling of user data.
# ============================================================
$Script:RxDanger = [regex]'(?i)(backup|\.met$|\.bak$|\.cfg$|\.dat$|\.evtx$|\.sqlite|\.db$|\.wallet$|cookies?|history|password|passwds?|session|bookmark|known|clients|saved|wallet|token|credential|login|signin|autologon|seed|keystore|windows\.old|\.key$|\.pem$|\.kdbx$)'
$Script:RxCaution = [regex]'(?i)(download|package|installer|prefetch|deliveryoptimization|softwaredistribution|setupapi|windowsupdate|windowsdefender|panther|recycle|\.old$)'
$Script:RxSafe = [regex]'(?i)(cache|temp|tmp|^log|logs$|log$|dump|crash|shader|webcache|htmlcache|crashpad|gpucache|d3ds|thumb|icon|\.log$|\.dmp$|\.etl$|\.tmp$|tmp~|\\wer($|\\)|crashdumps)'
$Script:RxProgDirs = [regex]'(?i)\\(bin|src|lib|lib64|site-packages|node_modules|include|share)(\\|$)'

function Get-AutoTier([string]$NormPath, [string]$EntryType) {
  if ([string]::IsNullOrWhiteSpace($NormPath)) { return 'dangerous' }
  $p = $NormPath.ToLowerInvariant()
  $leaf = ($p -split '\\')[-1]
  # 1) dangerous signals win first (conservative precedence)
  if ($Script:RxDanger.IsMatch($leaf) -or $Script:RxDanger.IsMatch($p)) { return 'dangerous' }
  # 2) program main dirs
  if ($Script:RxProgDirs.IsMatch($p)) { return 'dangerous' }
  # 3) caution signals
  if ($Script:RxCaution.IsMatch($leaf) -or $Script:RxCaution.IsMatch($p)) { return 'caution' }
  # 4) safe signals
  if ($Script:RxSafe.IsMatch($leaf)) { return 'safe' }
  # 5) file-type entries are usually data files -> dangerous
  if ($EntryType -eq 'file') { return 'dangerous' }
  # 6) unknown -> dangerous (never guess safe)
  return 'dangerous'
}

function Get-TierSignals([string]$NormPath, [string]$EntryType) {
  # transparency helper: which signal class fired (for merged JSON audit)
  if ([string]::IsNullOrWhiteSpace($NormPath)) { return 'empty' }
  $p = $NormPath.ToLowerInvariant()
  $leaf = ($p -split '\\')[-1]
  if ($Script:RxDanger.IsMatch($leaf) -or $Script:RxDanger.IsMatch($p)) { return 'danger-signal' }
  if ($Script:RxProgDirs.IsMatch($p)) { return 'program-dir' }
  if ($Script:RxCaution.IsMatch($leaf) -or $Script:RxCaution.IsMatch($p)) { return 'caution-signal' }
  if ($Script:RxSafe.IsMatch($leaf)) { return 'safe-signal' }
  if ($EntryType -eq 'file') { return 'file-type' }
  return 'unknown'
}

function Get-PathHash8([string]$NormPath) {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($NormPath.ToLowerInvariant())
  $hash = $md5.ComputeHash($bytes)
  return (($hash[0..3] | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-SrcTag([string]$FileName) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLowerInvariant()
  $tag = ($base -replace '[^a-z0-9]', '')
  if ($tag.Length -gt 10) { $tag = $tag.Substring(0, 10) }
  if ([string]::IsNullOrWhiteSpace($tag)) { $tag = 'ccp' }
  return $tag
}

# ============================================================
# Scan Lists (whitelist/blacklist) - R5-1
# ============================================================
$Script:ScanLists = $null
function Load-ScanLists {
  param([string]$ConfigDir)
  if ($Script:ScanLists) { return $Script:ScanLists }
  $path = Join-Path $ConfigDir 'scan-lists.json'
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Host "[WARN] scan-lists.json not found at $path; path filtering disabled"
    return $null
  }
  try {
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $Script:ScanLists = $json | ConvertFrom-Json
    return $Script:ScanLists
  } catch {
    Write-Host "[WARN] Failed to load scan-lists.json: $($_.Exception.Message)"
    return $null
  }
}

function Expand-ScanListPaths([object[]]$Entries) {
  $expanded = @()
  foreach ($e in $Entries) {
    foreach ($p in @($e.paths)) {
      $ep = Expand-EnvPath ([string]$p)
      if ($ep) { $expanded += $ep }
    }
    if ($e.special) { $expanded += $e.id }
  }
  return $expanded
}

function Get-WhitelistPaths {
  param([string]$ConfigDir)
  $lists = Load-ScanLists $ConfigDir
  if (-not $lists -or -not $lists.whitelist -or -not $lists.whitelist.enabled) { return @() }
  return Expand-ScanListPaths $lists.whitelist.entries
}

function Get-BlacklistPatterns {
  param([string]$ConfigDir)
  # 防御纵深：scan-lists.json 黑名单 ∪ 引擎删除点 GuardPatterns（系统核心区域严禁扫描）
  $patterns = @()
  $lists = Load-ScanLists $ConfigDir
  if ($lists -and $lists.blacklist -and $lists.blacklist.enabled) {
    foreach ($e in $lists.blacklist.entries) {
      $patterns += @($e.patterns)
    }
  }
  # Engine guards are unconditional — never gated by -NoBlacklist / -PathFilter
  $patterns += @(Get-EngineGuardPatterns)
  return $patterns
}

function Get-EngineGuardPatterns {
  # RED LINE: engine-level system guard patterns are HARDCODED and can NEVER be
  # disabled by -PathFilter, -NoBlacklist, or any configuration parameter.
  # These protect OS core areas at both scan-time and deletion-time.
  return @($Script:GuardPatterns)
}

function Test-PathAgainstWhitelist([string]$Path, [string[]]$WhitelistPaths) {
  # RED LINE: empty whitelist in whitelist mode = deny all (fail-closed, not fail-open)
  if (-not $WhitelistPaths -or $WhitelistPaths.Count -eq 0) { return $false }
  $lower = $Path.ToLowerInvariant()
  foreach ($wp in $WhitelistPaths) {
    $wpLower = $wp.ToLowerInvariant()
    if ($lower -eq $wpLower -or $lower.StartsWith($wpLower + '\')) { return $true }
    # handle wildcards in whitelist (e.g., %LOCALAPPDATA%\Packages\*\TempState)
    if ($wpLower -like '*\*') {
      $pattern = '^' + [regex]::Escape($wpLower).Replace('\*', '.*') + '$'
      if ($lower -match $pattern) { return $true }
    }
  }
  return $false
}

function Test-PathAgainstBlacklist([string]$Path, [string[]]$BlacklistPatterns) {
  if (-not $BlacklistPatterns -or $BlacklistPatterns.Count -eq 0) { return $false }
  $lower = $Path.ToLowerInvariant()
  foreach ($pat in $BlacklistPatterns) {
    # 正则语义（与引擎 GuardPatterns 同源）：pattern 内含正则元字符，直接匹配
    if ($lower -match $pat) { return $true }
  }
  return $false
}

function Get-ScanModeConfig {
  param([string]$ScanMode)
  $lists = $Script:ScanLists
  if (-not $lists -or -not $lists.scanModes -or -not $lists.scanModes.$ScanMode) {
    # RED LINE: default config must enforce blacklist filtering.
    # NOTE: skipBlacklist=true means "filter out blacklisted targets" (apply the check);
    # only the 'diagnostic' audit mode sets it to false (scan all, report hits).
    return @{ useWhitelist = $true; maxDepth = 3; followJunctions = $false; skipBlacklist = $true }
  }
  return $lists.scanModes.$ScanMode
}

function Get-TierRank([string]$tier) {
  switch ($tier) {
    'safe' { return 0 }
    'caution' { return 1 }
    default { return 2 }
  }
}

# ============================================================
# Scan Rating/Grading (R5-2)
# 评级反映「系统堆积状态」：A=很干净 … F=严重堆积。
# - clutterScore：可清理垃圾总量（越多越脏）
# - accessPenalty：扫描中真实 skipped/error（访问受限，非白名单过滤）
# - blacklistPenalty：黑名单命中（规则越界，安全信号）
# 注意：白名单过滤掉的规则数（whitelistSkipped）是**设计行为**
#       （规则库 15k 中只保留白名单内目标），不参与扣分。
# ============================================================
function Get-ScanRating {
  param(
    [double]$TotalFreedGB,
    [int]$SafeItemsCleaned = 0,
    [int]$CautionItemsCleaned = 0,
    [int]$DangerousItemsCleaned = 0,
    [int]$ItemsSkipped = 0,
    [int]$ItemsErrors = 0,
    [int]$BlacklistHits = 0,
    [int]$WhitelistSkipped = 0
  )

  # 垃圾堆积分（按可清理总量）
  $clutterScore = 0
  if ($TotalFreedGB -gt 50) { $clutterScore = 50 }
  elseif ($TotalFreedGB -gt 20) { $clutterScore = 35 }
  elseif ($TotalFreedGB -gt 10) { $clutterScore = 25 }
  elseif ($TotalFreedGB -gt 5) { $clutterScore = 15 }
  elseif ($TotalFreedGB -gt 1) { $clutterScore = 10 }
  elseif ($TotalFreedGB -gt 0.5) { $clutterScore = 5 }

  # 访问受限惩罚（真实 skip/error，上限 20 防失真）
  $accessPenalty = [math]::Min(($ItemsSkipped + $ItemsErrors) * 2, 20)

  # 黑名单命中惩罚（规则越界信号，上限 15）
  $blacklistPenalty = [math]::Min($BlacklistHits * 5, 15)

  $finalScore = [math]::Max(0, 100 - $clutterScore - $accessPenalty - $blacklistPenalty)
  
  $grade = 'F'
  if ($finalScore -ge 90) { $grade = 'A' }
  elseif ($finalScore -ge 80) { $grade = 'B' }
  elseif ($finalScore -ge 70) { $grade = 'C' }
  elseif ($finalScore -ge 60) { $grade = 'D' }
  elseif ($finalScore -ge 50) { $grade = 'E' }
  
  $status = switch ($grade) {
    'A' { 'Excellent - System very clean' }
    'B' { 'Good - Minor clutter' }
    'C' { 'Fair - Moderate clutter' }
    'D' { 'Poor - Significant clutter' }
    'E' { 'Bad - Heavy clutter' }
    default { 'Critical - Severe clutter or access issues' }
  }

  return @{
    score = $finalScore
    grade = $grade
    status = $status
    clutterScore = $clutterScore
    accessPenalty = $accessPenalty
    blacklistPenalty = $blacklistPenalty
  }
}

# ============================================================
# Engine-level guardrail: protected system paths (red line)
# Blocks direct deletion of OS core areas; special handlers use
# native commands (wevtutil/powercfg) instead of file deletion.
# ============================================================
# Patterns match BOTH normalized (%WINDIR%\...) and expanded (c:\windows\...) forms,
# because guard checks run against both rule normPaths and real filesystem paths.
$Script:GuardPatterns = @(
  # Component store & servicing
  '\\winsxs($|\\)',
  '\\windows\\servicing($|\\)',
  '\\windows\\installer($|\\)',
  '^%windir%\\installer($|\\)',
  # Registry hives & system32 core
  '\\system32\\config($|\\)',
  '\\system32\\drivers($|\\)',
  '\\driverstore($|\\)',
  '\\assembly($|\\)',
  '^%windir%\\system32$',
  '^%windir%\\syswow64$',
  '^[a-z]:\\windows\\system32$',
  '^[a-z]:\\windows\\syswow64$',
  '^%windir%$',
  '^[a-z]:\\windows$',
  # Critical system binaries & libraries
  '\\system32\\[^\\]+\.(dll|exe|sys|drv)$',
  '\\syswow64\\[^\\]+\.(dll|exe|sys|drv)$',
  '\\explorer\.exe$',
  '\\regedit\.exe$',
  '\\bootmgr$',
  # Memory management files
  'pagefile\.sys$',
  'swapfile\.sys$',
  'hiberfil\.sys$',
  'dumpstack\.log\.tmp$',
  # User registry hives
  'ntuser\.dat',
  'usrclass\.dat',
  # Boot / BCD / EFI / Recovery
  '^%systemdrive%\\boot$',
  '^[a-z]:\\boot$',
  '\\boot\\bcd',
  '^[a-z]:\\efi($|\\)',
  '^[a-z]:\\recovery($|\\)',
  '^\\\\\?\\volume\{',
  # Event logs (must use wevtutil, never direct delete)
  '\\system32\\winevt($|\\)',
  '\\system32\\winevt\\logs\\[^\\]+\.evtx$',
  # Driver INF & WMI repository
  '\\windows\\inf($|\\)',
  '\\wbem\\repository($|\\)',
  # Installed application binaries (expanded + normalized %PROGRAMFILES% forms)
  '\\program files($|\\)',
  '\\program files \(x86\)($|\\)',
  '^%programfiles%($|\\)',
  '^%programfiles\(x86\)%($|\\)',
  # Previous Windows installation
  '\\windows\.old($|\\)'
)
function Test-GuardrailBlocked([string]$NormPath) {
  if ([string]::IsNullOrWhiteSpace($NormPath)) { return $false }
  $lower = $NormPath.ToLowerInvariant()
  foreach ($pat in $Script:GuardPatterns) {
    if ($lower -match $pat) { return $true }
  }
  return $false
}

# ============================================================
# Restart Manager (rstrtmgr.dll): report which processes lock a path.
# Technique adopted from WindowsClear (Rust, MIT). Report-only here:
# closing apps stays behind -AllowStop / user confirmation.
# ============================================================
$Script:RmTypeLoaded = $false
function Initialize-RmType {
  if ($Script:RmTypeLoaded) { return $true }
  $src = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WinRm {
  [StructLayout(LayoutKind.Sequential)]
  public struct RM_UNIQUE_PROCESS { public int dwProcessId; public long ProcessStartTime; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct RM_PROCESS_INFO {
    public RM_UNIQUE_PROCESS Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
    public int ApplicationType; public uint AppStatus; public uint TSSessionId;
    [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
  }
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmEndSession(uint pSessionHandle);
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, RM_UNIQUE_PROCESS[] rgApplications, uint nServices, string[] rgsServiceNames);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);
  public static string GetLockers(string path) {
    uint handle;
    string key = Guid.NewGuid().ToString();
    if (RmStartSession(out handle, 0, key) != 0) return "";
    try {
      string[] files = new string[] { path };
      if (RmRegisterResources(handle, 1, files, 0, null, 0, null) != 0) return "";
      uint needed = 0, count = 0, reasons = 0;
      int res = RmGetList(handle, out needed, ref count, null, ref reasons);
      if (res == 234 && needed > 0) { // ERROR_MORE_DATA
        var infos = new RM_PROCESS_INFO[needed];
        count = needed;
        if (RmGetList(handle, out needed, ref count, infos, ref reasons) == 0) {
          var sb = new StringBuilder();
          for (int i = 0; i < count; i++) {
            if (sb.Length > 0) sb.Append(", ");
            sb.Append(infos[i].strAppName);
            sb.Append("("); sb.Append(infos[i].Process.dwProcessId); sb.Append(")");
          }
          return sb.ToString();
        }
      }
      return "";
    } finally { RmEndSession(handle); }
  }
}
'@
  try { Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop; $Script:RmTypeLoaded = $true; return $true }
  catch { return $false }
}

function Get-PathLockers([string]$Path) {
  if (-not (Initialize-RmType)) { return '' }
  try { return [WinRm]::GetLockers($Path) } catch { return '' }
}

# ============================================================
# Modern scanners (C#, loaded on demand):
#   ParallelScanner — Task.WhenAll + SemaphoreSlim async recursive scan
#   MftScanner      — NTFS MFT direct read (Analyze fast path)
# ============================================================
$Script:PsScannerLoaded = $false
function Initialize-ParallelScanner {
  if ($Script:PsScannerLoaded) { return $true }
  $cs = Join-Path (Split-Path -Parent $PSCommandPath) 'ParallelScanner.cs'
  if (-not (Test-Path -LiteralPath $cs)) { return $false }
  try {
    Add-Type -TypeDefinition (Get-Content -LiteralPath $cs -Raw -Encoding UTF8) -Language CSharp -ErrorAction Stop
    $Script:PsScannerLoaded = $true; return $true
  } catch { return $false }
}

# ============================================================
# Feature engine v3: magic-byte verification (Czkawka-style).
# Detects files whose extension lies about their real content.
# ============================================================
function Get-MagicType([string]$Path) {
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
      $b = New-Object byte[] 8
      $n = $fs.Read($b, 0, 8)
      if ($n -lt 4) { return '' }
      if ($b[0] -eq 0x4D -and $b[1] -eq 0x5A) { return 'executable' }                       # MZ
      if ($b[0] -eq 0x50 -and $b[1] -eq 0x4B) { return 'zip-archive' }                        # PK
      if ($b[0] -eq 0x52 -and $b[1] -eq 0x61 -and $b[2] -eq 0x72 -and $b[3] -eq 0x21) { return 'rar-archive' }
      if ($b[0] -eq 0x37 -and $b[1] -eq 0x7A -and $b[2] -eq 0xBC -and $b[3] -eq 0xAF) { return '7z-archive' }
      if ($n -ge 16) {
        $head = [System.Text.Encoding]::ASCII.GetString($b[0..3])
        $head2 = [System.Text.Encoding]::ASCII.GetString($b[0..5])
        $fs.Seek(0, 'Begin') | Out-Null
        $b16 = New-Object byte[] 16
        [void]$fs.Read($b16, 0, 16)
        if ($head2 -eq 'SQLite') { return 'sqlite-database' }
        if ($head -eq '%PDF') { return 'pdf' }
        if ([System.Text.Encoding]::ASCII.GetString($b16[0..5]) -eq 'GIF89a') { return 'image' }
      }
      return ''
    } finally { $fs.Dispose() }
  } catch { return '' }
}

# dangerous-extension fence: these extensions are never permanently deleted in
# safe/caution tiers unless the target is a curated builtin that owns them.
$Script:RiskyExtPattern = [regex]'(?i)\.(exe|dll|sys|msi|bat|cmd|ps1|vbs|js|jar|scr|cpl|drv|ocx|ttf|fon|lnk)$'
function Test-RiskyExtension([string]$Path) { return $Script:RiskyExtPattern.IsMatch($Path) }

# ============================================================
# Config merge pipeline (MergeConfig mode)
# Steps: discover -> parse -> normalize -> dedupe -> tier -> merge -> persist
# Source classes (policy):
#   curated   : hand-curated c_cleaner_plus rules (rules_*, common_custom_rules) - safe tier auto-enabled
#   community : fresh upstream dumps (winapp2_latest, community_cleaners,
#               cdisk_cleaner_custom_rules) - ALWAYS disabled (opt-in)
#   state     : cdisk_cleaner_config app-state export (checkbox states)        - user state wins
# ============================================================
function Get-SourceClass([string]$FileName) {
  $n = $FileName.ToLowerInvariant()
  # fresh upstream dumps (winapp2 v260730 / BleachBit cleaners) + c_cleaner_plus custom-rule exports: opt-in only
  if ($n -like 'winapp2_latest*' -or $n -like 'community_cleaners*' -or $n -like 'cdisk_cleaner_custom_rules*') { return 'community' }
  # only the app-state config (double-encoded checkbox states) carries real user intent
  if ($n -like 'cdisk_cleaner_config*') { return 'state' }
  return 'curated'
}

# rule-set category for guided selection (-RuleSets)
function Get-CategoryForSource([string]$FileName) {
  $n = $FileName.ToLowerInvariant()
  if ($n -like 'rules_cn_apps*') { return 'cn' }
  if ($n -like 'rules_dev_tools*' -or $n -like 'rules_mobile_dev_tools*') { return 'dev' }
  if ($n -like 'rules_design_3d_cad*') { return 'design' }
  if ($n -like 'rules_ai_tools*') { return 'ai' }
  if ($n -like 'rules_game_platforms*') { return 'game' }
  if ($n -like 'rules_media_creation*') { return 'media' }
  if ($n -like 'winapp2_latest*' -or $n -like 'community_cleaners*') { return 'community' }
  if ($n -like 'cdisk_cleaner*') { return 'system' }
  return 'general'
}
function Invoke-ConfigMerge {
  param(
    [string[]]$Dirs,
    [string]$BuiltinConfigPath,
    [string]$OutMergedPath,
    [string]$OverridesPath
  )
  $builtin = Get-Content -LiteralPath $BuiltinConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $builtinByPath = @{}
  foreach ($t in @($builtin.targets)) {
    foreach ($p in @($t.paths)) {
      $np = ConvertTo-NormPath ([string]$p)
      if ($np) { $builtinByPath[$np.ToLowerInvariant()] = $t }
    }
  }

  $ccpEntries = @{}     # normPathLower -> entry
  $unparsed = @()
  $sourceStats = @()
  $totalDiscovered = 0

  foreach ($dir in $Dirs) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $files = Get-ChildItem -LiteralPath $dir -Recurse -File -Include *.json, *.ini, *.txt, *.yaml, *.yml -ErrorAction SilentlyContinue
    # deterministic order: curated first, community second, state exports last (state wins on enable)
    $rank = @{ curated = 0; community = 1; state = 2 }
    $files = @($files | Sort-Object @{ Expression = { $rank[(Get-SourceClass $_.Name)] } }, Name)
    foreach ($f in $files) {
      $srcClass = Get-SourceClass $f.Name
      $parsedCount = 0
      $failedCount = 0
      $rows = $null
      if ($f.Extension -eq '.json') {
        try {
          $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
          $data = $raw | ConvertFrom-Json
          if ($data -is [System.Array]) { $rows = $data }
          elseif ($data.PSObject.Properties['order']) {
            # v2 double-encoded format: order elements are strings "[ ""[...tuple...]"", state ]"
            $rows = @()
            foreach ($el in @($data.order)) {
              try {
                $inner = $el
                if ($inner -is [string]) { $inner = $inner | ConvertFrom-Json }
                if ($inner -is [System.Array] -and $inner.Count -ge 1) {
                  $tuple = $inner[0]
                  if ($tuple -is [string]) { $tuple = $tuple | ConvertFrom-Json }
                  $state = 1
                  if ($inner.Count -ge 2 -and $inner[1] -is [int]) { $state = [int]$inner[1] }
                  $rows += , @($tuple, $state)
                }
              } catch { $failedCount++ }
            }
          }
        } catch { $unparsed += @{ file = $f.Name; reason = 'json parse failed: ' + $_.Exception.Message }; $sourceStats += @{ file = $f.Name; parsed = 0; failed = 1 }; continue }
      } else {
        $unparsed += @{ file = $f.Name; reason = 'non-json format not supported yet' }
        $sourceStats += @{ file = $f.Name; parsed = 0; failed = 0 }
        continue
      }
      if (-not $rows) { $sourceStats += @{ file = $f.Name; parsed = 0; failed = $failedCount }; continue }
      foreach ($row in $rows) {
        $totalDiscovered++
        try {
          $tuple = $row
          $stateOverride = $null
          if ($row -is [System.Array] -and $row.Count -eq 2 -and ($row[0] -is [System.Array] -or $row[0] -is [string])) {
            $tuple = $row[0]
            if ($row[0] -is [string]) { $tuple = $row[0] | ConvertFrom-Json }
            if ($row[1] -is [int]) { $stateOverride = [int]$row[1] }
          }
          if ($tuple -is [string]) { $tuple = $tuple | ConvertFrom-Json }
          $arr = @($tuple)
          if ($arr.Count -lt 3) { throw 'tuple too short' }
          $name = [string]$arr[0]
          $rawPath = [string]$arr[1]
          $entryType = ([string]$arr[2]).ToLowerInvariant()
          if ($entryType -ne 'dir' -and $entryType -ne 'file' -and $entryType -ne 'glob') { $entryType = 'dir' }
          $requiresAdmin = $false
          $meta = ''
          $globPattern = ''
          if ($arr.Count -ge 4 -and $arr[3] -is [bool]) {
            $requiresAdmin = [bool]$arr[3]
            if ($arr.Count -ge 5 -and $arr[4] -is [string]) { $meta = [string]$arr[4] }
            if ($arr.Count -ge 6 -and $arr[5] -is [bool] -and $arr[5]) { $meta = ('[advanced] ' + $meta) }
          } elseif ($arr.Count -ge 4 -and $arr[3] -is [string]) {
            $meta = [string]$arr[3]
            if ($arr.Count -ge 5 -and $arr[4] -is [bool]) { $requiresAdmin = [bool]$arr[4] }
            if ($arr.Count -ge 6 -and $arr[5] -is [string]) { $globPattern = [string]$arr[5] }
          }
          $norm = ConvertTo-NormPath $rawPath
          if (-not $norm) { throw 'empty path' }
          $normLower = $norm.ToLowerInvariant()
          # infer admin for system-level paths when not given
          if (-not $requiresAdmin) {
            if ($normLower -match '^(%windir%|%programdata%|%programfiles%|%systemdrive%\\windows)') { $requiresAdmin = $true }
          }
          $tier = Get-AutoTier $norm $entryType
          # guardrail: protected system paths are demoted to dangerous+disabled, never guess-safe
          $guardBlocked = Test-GuardrailBlocked $norm
          if ($guardBlocked) { $tier = 'dangerous' }
          # enable policy by source class
          $enabled = $null
          if ($srcClass -eq 'community') { $enabled = $false }                    # opt-in only
          elseif ($null -ne $stateOverride) { $enabled = ($stateOverride -eq 1) } # app checkbox state
          elseif ($arr.Count -ge 5 -and $arr[4] -is [bool] -and -not ($arr[3] -is [bool])) { $enabled = [bool]$arr[4] }
          if ($null -eq $enabled) { $enabled = ($tier -eq 'safe') }
          if ($tier -eq 'dangerous') { $enabled = $false }
          if ($guardBlocked) { $meta = ('[guardrail:protected-path] ' + $meta) }

          if ($ccpEntries.ContainsKey($normLower)) {
            $ex = $ccpEntries[$normLower]
            # keep more conservative tier
            if ((Get-TierRank $tier) -gt (Get-TierRank $ex.tier)) { $ex.tier = $tier }
            # state sources may enable/disable; community/curated duplicates never override first-wins
            if ($srcClass -eq 'state') { $ex.enabled = $enabled }
            if (-not $ex.sources -contains $f.Name) { $ex.sources = @($ex.sources + $f.Name) }
            if (-not $ex.meta -and $meta) { $ex.meta = $meta }
            if ($guardBlocked) { $ex.meta = ('[guardrail:protected-path] ' + $ex.meta) }
          } else {
            $ccpEntries[$normLower] = @{
              normPath = $norm
              name = $name
              type = $entryType
              glob = $globPattern
              requiresAdmin = $requiresAdmin
              meta = $meta
              tier = $tier
              signals = (Get-TierSignals $norm $entryType)
              enabled = $enabled
              sources = @($f.Name)
            }
          }
          $parsedCount++
        } catch {
          $failedCount++
          $unparsed += @{ file = $f.Name; reason = 'entry parse failed: ' + $_.Exception.Message }
        }
      }
      $sourceStats += @{ file = $f.Name; parsed = $parsedCount; failed = $failedCount }
    }
  }

  # Build merged target list: builtin first (never overwritten), then ccp entries
  $mergedTargets = New-Object System.Collections.Generic.List[object]
  $collisions = 0
  foreach ($t in @($builtin.targets)) {
    $obj = [ordered]@{
      id = [string]$t.id
      name = [string]$t.name
      enabled = [bool]$t.enabled
      tier = [string]$t.tier
      requiresAdmin = [bool]$t.requiresAdmin
      type = [string]$t.type
      paths = @($t.paths)
      glob = [string]$t.glob
      preCommands = @($t.preCommands)
      stopProcesses = @($t.stopProcesses)
      stopServices = @($t.stopServices)
      risk = [string]$t.risk
      signals = 'builtin-curated'
      origin = 'builtin'
      sourceFile = ''
    }
    $mergedTargets.Add([pscustomobject]$obj)
  }
  foreach ($key in @($ccpEntries.Keys | Sort-Object)) {
    $e = $ccpEntries[$key]
    if ($builtinByPath.ContainsKey($key)) {
      # path collision with builtin: builtin wins, annotate collision
      $collisions++
      $bt = $builtinByPath[$key]
      foreach ($mt in $mergedTargets) {
        if ($mt.id -eq [string]$bt.id) {
          $mt.origin = 'merged'
          $mt.sourceFile = ($e.sources -join ',')
          break
        }
      }
      continue
    }
    $id = 'ccp-' + (Get-SrcTag ($e.sources | Select-Object -First 1)) + '-' + (Get-PathHash8 $e.normPath)
    $mergedTargets.Add([pscustomobject][ordered]@{
      id = $id
      name = $e.name
      enabled = [bool]$e.enabled
      tier = [string]$e.tier
      requiresAdmin = [bool]$e.requiresAdmin
      type = $e.type
      paths = @($e.normPath)
      glob = [string]$e.glob
      preCommands = @()
      stopProcesses = @()
      stopServices = @()
      risk = [string]$e.meta
      signals = [string]$e.signals
      origin = 'c_cleaner_plus'
      category = (Get-CategoryForSource ([string]($e.sources | Select-Object -First 1)))
      sourceFile = ($e.sources -join ',')
    })
  }

  $merged = [ordered]@{
    version = 1
    generatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    builtinConfig = $BuiltinConfigPath
    sources = $sourceStats
    stats = [ordered]@{
      discovered = $totalDiscovered
      parsed = ($totalDiscovered - (@($unparsed)).Count)
      uniqueCcpEntries = $ccpEntries.Count
      pathCollisionsWithBuiltin = $collisions
      unparsedCount = (@($unparsed)).Count
      builtinTargets = @($builtin.targets).Count
      totalMergedTargets = $mergedTargets.Count
      guardrailDemoted = @($mergedTargets | Where-Object { ([string]$_.risk).Contains('[guardrail:protected-path]') }).Count
      tierHistogram = [ordered]@{
        safe = @($mergedTargets | Where-Object { $_.tier -eq 'safe' }).Count
        caution = @($mergedTargets | Where-Object { $_.tier -eq 'caution' }).Count
        dangerous = @($mergedTargets | Where-Object { $_.tier -eq 'dangerous' }).Count
      }
      signalsHistogram = (@($mergedTargets | Group-Object signals | Sort-Object Count -Descending | ForEach-Object { @{ $_.Name = $_.Count } }) | ForEach-Object { $_ })
    }
    unparsed = $unparsed
    targets = $mergedTargets
  }
  $mergedJson = $merged | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($OutMergedPath, $mergedJson, (New-Object System.Text.UTF8Encoding($true)))
  if (-not (Test-Path -LiteralPath $OverridesPath)) {
    $init = '{"version":1,"enabled":{}}'
    [System.IO.File]::WriteAllText($OverridesPath, $init, (New-Object System.Text.UTF8Encoding($true)))
  }
  return $merged
}

# ============================================================
# Effective config loading (builtin + merged + user overrides)
# ============================================================
function Resolve-ConfigPath([string]$ConfigPath) {
  if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) { return (Resolve-Path -LiteralPath $ConfigPath).Path }
  $here = Split-Path -Parent $PSCommandPath
  $candidates = @(
    (Join-Path $here '..\config\targets.json'),
    (Join-Path $here 'config\targets.json'),
    (Join-Path (Get-Location) 'config\targets.json'),
    (Join-Path (Get-Location) 'targets.json')
  )
  foreach ($c in $candidates) {
    $full = [IO.Path]::GetFullPath($c)
    if (Test-Path -LiteralPath $full) { return $full }
  }
  throw 'targets.json not found. Pass -Config or place config/targets.json next to scripts/.'
}

function Get-CCPDirsFromConfig($cfg, [string]$CCPDirsParam, [string]$BaseDir) {
  if ($CCPDirsParam) {
    return @($CCPDirsParam -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  $dirs = New-Object System.Collections.Generic.List[string]
  # built-in reference rules (self-contained; relative paths resolved against config dir)
  if ($cfg.PSObject.Properties['mergeSources'] -and $cfg.mergeSources) {
    foreach ($s in @($cfg.mergeSources)) {
      $p = [string]$s
      if (-not $p) { continue }
      if (-not [System.IO.Path]::IsPathRooted($p)) { $p = [IO.Path]::GetFullPath((Join-Path $BaseDir $p)) }
      if (Test-Path -LiteralPath $p) { $dirs.Add($p) }
    }
  }
  # optional external upgrade sources (e.g. original c_cleaner_plus download dirs)
  if ($cfg.PSObject.Properties['externalMergeSources'] -and $cfg.externalMergeSources) {
    foreach ($s in @($cfg.externalMergeSources)) {
      $p = [string]$s
      if (-not $p) { continue }
      if (-not [System.IO.Path]::IsPathRooted($p)) { $p = [IO.Path]::GetFullPath((Join-Path $BaseDir $p)) }
      if ((Test-Path -LiteralPath $p) -and (-not $dirs.Contains($p))) { $dirs.Add($p) }
    }
  }
  return @($dirs)
}

function Get-EffectiveTargets {
  param($BuiltinCfg, $MergedData, $OverridesData)
  $list = New-Object System.Collections.Generic.List[object]
  if ($MergedData -and $MergedData.PSObject.Properties['targets']) {
    foreach ($t in @($MergedData.targets)) { $list.Add($t) }
  } else {
    foreach ($t in @($BuiltinCfg.targets)) {
      $list.Add([pscustomobject][ordered]@{
        id = [string]$t.id; name = [string]$t.name; enabled = [bool]$t.enabled
        tier = [string]$t.tier; requiresAdmin = [bool]$t.requiresAdmin; type = [string]$t.type
        paths = @($t.paths); glob = [string]$t.glob; preCommands = @($t.preCommands)
        stopProcesses = @($t.stopProcesses); stopServices = @($t.stopServices)
        risk = [string]$t.risk; origin = 'builtin'; sourceFile = ''
        category = if ($t.PSObject.Properties['category']) { [string]$t.category } else { 'builtin' }
      })
    }
  }
  # apply user overrides
  if ($OverridesData -and $OverridesData.PSObject.Properties['enabled'] -and $OverridesData.enabled) {
    foreach ($t in $list) {
      $prop = $OverridesData.enabled.PSObject.Properties[$t.id]
      if ($prop) { $t.enabled = [bool]$prop.Value }
    }
  }
  return $list
}

# ============================================================
# Parallel size measurement (runspace pool, batched small tasks,
# robocopy native fallback for access-denied dirs)
# ============================================================
$Script:MeasureScript = @'
param($Items)
function Measure-One([string]$Path, [string]$GlobPattern) {
  $bytes = [int64]0
  $denied = $false
  try {
    if (-not (Test-Path -LiteralPath $Path)) { return @{ bytes = 0; denied = $false } }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item -is [System.IO.FileInfo]) { return @{ bytes = [int64]$item.Length; denied = $false } }
    if ($GlobPattern) {
      try { foreach ($f in $item.EnumerateFiles($GlobPattern)) { $bytes += $f.Length } }
      catch { $denied = $true }
      return @{ bytes = $bytes; denied = $denied }
    }
    $stack = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
    $stack.Push($item)
    $isRoot = $true
    while ($stack.Count -gt 0) {
      $di = $stack.Pop()
      try { foreach ($fi in $di.EnumerateFiles()) { $bytes += $fi.Length } }
      catch { if ($isRoot) { $denied = $true } }
      try { foreach ($sd in $di.EnumerateDirectories()) { $stack.Push($sd) } }
      catch { if ($isRoot) { $denied = $true } }
      $isRoot = $false
    }
    # native robocopy fallback when .NET enumeration was denied (list-only, no copy)
    if ($denied) {
      $out = cmd /c "robocopy `"$Path`" NULL /L /S /BYTES /NFL /NDL /NJH /NP /NC /XJ /R:0 /W:0" 2>$null | Out-String
      $ziJie = [string]::new([char[]]@(0x5B57, 0x8282)) # localized "Bytes" label
      if ($out -match ("{0}:\s*(\d+)" -f [regex]::Escape($ziJie))) { return @{ bytes = [int64]$Matches[1]; denied = $false } }
      if ($out -match 'Bytes\s*:\s*(\d+)') { return @{ bytes = [int64]$Matches[1]; denied = $false } }
    }
    return @{ bytes = $bytes; denied = $denied }
  } catch { return @{ bytes = -1; denied = $true } }
}
$out = @()
foreach ($it in $Items) {
  $r = Measure-One $it.p $it.g
  $out += ,@{ k = $it.k; b = [int64]$r.bytes; d = [bool]$r.denied }
}
return $out
'@

function Invoke-MeasureParallel {
  # Jobs: array of @{ Items = @( @{k;p;g}, ... ) }.
  # Hot path: C# ParallelScanner (Task.WhenAll + SemaphoreSlim). Fallback: runspace pool.
  param([object[]]$MeasureJobs, [int]$ThreadCount, [string]$ScanMode = 'standard')
  $results = @{}
  if (-not $MeasureJobs -or $MeasureJobs.Count -eq 0) { return $results }
  if ($ThreadCount -lt 1) { $ThreadCount = 1 }
  # I/O friendly: drop priority while scanning so the system stays responsive
  $prevPrio = $null
  try {
    $prevPrio = [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass
    [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal'
  } catch {}
  try {
    if (Initialize-ParallelScanner) {
      $keys = New-Object System.Collections.Generic.List[string]
      $paths = New-Object System.Collections.Generic.List[string]
      $globs = New-Object System.Collections.Generic.List[string]
      foreach ($j in $MeasureJobs) {
        foreach ($it in @($j.Items)) {
          $keys.Add([string]$it.k); $paths.Add([string]$it.p); $globs.Add([string]$it.g)
        }
      }
      $scanModeEnum = [ScanMode]$ScanMode
      $r = [ParallelScanner]::Scan($paths.ToArray(), $globs.ToArray(), $ThreadCount, $null, $scanModeEnum)
      for ($i = 0; $i -lt $keys.Count; $i++) {
        $results[$keys[$i]] = @{ bytes = [int64]$r.Sizes[$i]; denied = ($r.Denied[$i] -eq 1) }
      }
      # robocopy /L native fallback for denied roots
      for ($i = 0; $i -lt $keys.Count; $i++) {
        if ($r.Denied[$i] -eq 1 -and [string]$globs[$i] -eq '') {
          $out = cmd /c ("robocopy `"{0}`" NULL /L /S /BYTES /NFL /NDL /NJH /NP /NC /XJ /R:0 /W:0" -f $paths[$i]) 2>$null | Out-String
          $ziJie = [string]::new([char[]]@(0x5B57, 0x8282))
          if ($out -match ("{0}:\s*(\d+)" -f [regex]::Escape($ziJie))) { $results[$keys[$i]] = @{ bytes = [int64]$Matches[1]; denied = $false } }
          elseif ($out -match 'Bytes\s*:\s*(\d+)') { $results[$keys[$i]] = @{ bytes = [int64]$Matches[1]; denied = $false } }
        }
      }
      return $results
    }
  } catch {
    Write-Host '[WARN] ParallelScanner failed; falling back to runspace pool.'
  }
  # fallback: runspace pool
  $iss = [initialsessionstate]::CreateDefault()
  $pool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount, $iss, $Host)
  $pool.Open()
  $jobs = New-Object System.Collections.Generic.List[object]
  foreach ($j in $MeasureJobs) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($Script:MeasureScript).AddArgument(@($j.Items))
    $jobs.Add([pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() })
  }
  foreach ($j in $jobs) {
    try {
      foreach ($r in @($j.PS.EndInvoke($j.Handle))) {
        if ($r -and $r.k) { $results[$r.k] = @{ bytes = $r.b; denied = $r.d } }
      }
    } catch {}
    $j.PS.Dispose()
  }
  $pool.Close()
  $pool.Dispose()
  if ($prevPrio) { try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = $prevPrio } catch {} }
  return $results
}

function Get-TargetPathsExpanded($t) {
  $expanded = @()
  foreach ($p in @($t.paths)) {
    $ep = Expand-EnvPath ([string]$p)
    if ($ep) { $expanded += $ep }
  }
  return $expanded
}

# ============================================================
# Clean helpers
# ============================================================
function Clear-OnePath {
  # Recovery modes:
  #   permanent  — direct deletion (current default; only mode that reclaims space immediately)
  #   recycle    — send to Recycle Bin via Microsoft.VisualBasic (SHFileOperation under the hood)
  #   quarantine — move into the quarantine root + manifest (restore via tools/restore-quarantine.ps1)
  # Safety fences (all modes): guardrail re-assert, hot-file skip (modified < HotMinutes),
  # risky-extension skip for non-builtin safe/caution targets in permanent mode.
  param(
    [string]$Path,
    [string]$GlobPattern,
    [string]$Mode = 'permanent',
    [string]$TargetId = '',
    [string]$TargetOrigin = '',
    [string]$Tier = 'safe',
    [int]$HotMin = 30,
    [string]$QuarantineRoot = ''
  )
  $script:LastHotSkipped = 0
  $script:LastRiskSkipped = 0
  if (-not (Test-Path -LiteralPath $Path)) { return 'missing' }
  # defense-in-depth: re-assert guardrail at the deletion point
  $np = ConvertTo-NormPath $Path
  if (Test-GuardrailBlocked $np) { return 'blocked' }

  $hotCutoff = (Get-Date).AddMinutes(-[math]::Max(0, $HotMin))

  # --- single file ---
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($item -is [System.IO.FileInfo]) {
    if ($item.LastWriteTime -gt $hotCutoff) { $script:LastHotSkipped = 1; return 'hot' }
    if ($Mode -eq 'permanent' -and $Tier -ne 'dangerous' -and $TargetOrigin -ne 'builtin' -and (Test-RiskyExtension $Path)) {
      $script:LastRiskSkipped = 1; return 'risky-ext'
    }
    if ($Mode -eq 'quarantine') { return (Move-FileToQuarantine $Path $QuarantineRoot) }
    if ($Mode -eq 'recycle') { return (Send-ToRecycleBin $Path $false) }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) { return 'locked' }
    return 'ok'
  }

  # --- glob dir (only matching root-level files) ---
  if ($GlobPattern) {
    $locked = 0
    $files = @(Get-ChildItem -LiteralPath $Path -Filter $GlobPattern -Force -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
      # RED LINE: final per-item guardrail assertion at the actual deletion point
      if (Test-GuardrailBlocked $f.FullName) { $script:LastRiskSkipped++; continue }
      if ($f.LastWriteTime -gt $hotCutoff) { $script:LastHotSkipped++; continue }
      if ($Mode -eq 'permanent' -and $Tier -ne 'dangerous' -and $TargetOrigin -ne 'builtin' -and (Test-RiskyExtension $f.FullName)) { $script:LastRiskSkipped++; continue }
      if ($Mode -eq 'quarantine') { $r = Move-FileToQuarantine $f.FullName $QuarantineRoot; if ($r -ne 'ok') { $locked++ }; continue }
      if ($Mode -eq 'recycle') { $r = Send-ToRecycleBin $f.FullName $false; if ($r -ne 'ok') { $locked++ }; continue }
      Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
      if (Test-Path -LiteralPath $f.FullName) { $locked++ }
    }
    if ($locked -gt 0) { return 'locked' }
    return 'ok'
  }

  # --- directory: per-top-level-child handling (hot subtree skip = active use) ---
  $children = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
  $locked = 0
  foreach ($c in $children) {
    # RED LINE: final per-item guardrail assertion at the actual deletion point
    if (Test-GuardrailBlocked $c.FullName) { $script:LastRiskSkipped++; continue }
    if ($c.LastWriteTime -gt $hotCutoff) { $script:LastHotSkipped++; continue }
    if ($Mode -eq 'permanent' -and $Tier -ne 'dangerous' -and $TargetOrigin -ne 'builtin' -and (Test-RiskyExtension $c.FullName)) { $script:LastRiskSkipped++; continue }
    if ($Mode -eq 'quarantine') { $r = Move-FileToQuarantine $c.FullName $QuarantineRoot; if ($r -ne 'ok') { $locked++ }; continue }
    if ($Mode -eq 'recycle') { $r = Send-ToRecycleBin $c.FullName ($c.PSIsContainer); if ($r -ne 'ok') { $locked++ }; continue }
    Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $c.FullName) { $locked++ }
  }
  if ($Mode -eq 'permanent') {
    # only remove the root dir when EMPTY: hot/risky-skipped children must survive
    # (never blanket-Remove-Item -Recurse here — that would defeat the fences above)
    $remaining = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
      Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
      New-Item -ItemType Directory -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
    }
  }
  if ($locked -gt 0) { return 'locked' }
  return 'ok'
}

$Script:QuarantineManifest = $null
function Get-QuarantineRoot {
  # 隔离区放 skill 根目录 quarantine/（可移植，不再写桌面）
  $base = Join-Path (Get-SkillRootDir) 'quarantine'
  if (-not (Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
  $root = Join-Path $base ("wincc-quarantine_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
  if ($null -eq $Script:QuarantineManifest) {
    $Script:QuarantineManifest = [pscustomobject]@{
      time = (Get-Date).ToString('o')
      items = New-Object System.Collections.Generic.List[object]
    }
  }
  return $root
}
function Move-FileToQuarantine([string]$Path, [string]$QRoot) {
  try {
    $qRoot = if ($QRoot) { $QRoot } else { Get-QuarantineRoot }
    $size = 0L
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -is [System.IO.FileInfo]) { $size = $item.Length }
    else { foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $size += $f.Length } }
    $dest = Join-Path $qRoot ([guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
    $Script:QuarantineManifest.items.Add([pscustomobject]@{ original = $Path; quarantined = $dest; sizeBytes = $size })
    return 'ok'
  } catch { return 'locked' }
}
function Send-ToRecycleBin([string]$Path, [bool]$IsDir) {
  try {
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
    if ($IsDir) {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
    if (Test-Path -LiteralPath $Path) { return 'locked' }
    return 'ok'
  } catch { return 'locked' }
}

function Backup-TargetPaths {
  param([string]$Id, [string[]]$Paths)
  # 备份放 skill 根目录 backups/（可移植，不再写桌面）
  $base = Join-Path (Get-SkillRootDir) 'backups'
  if (-not (Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $backupRoot = Join-Path $base ("win-c-clear-skill_backup_{0}_{1}" -f $Id, $stamp)
  New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
  $copied = 0
  foreach ($p in $Paths) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    try {
      $leaf = Split-Path -Leaf $p
      Copy-Item -LiteralPath $p -Destination (Join-Path $backupRoot $leaf) -Recurse -Force -ErrorAction Stop
      $copied++
    } catch {}
  }
  return @{ path = $backupRoot; copied = $copied }
}

function Get-RunningProcessNames([string[]]$Names) {
  $running = @()
  foreach ($n in ($Names | Where-Object { $_ })) {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) { $running += $n }
  }
  return $running
}

function Invoke-TrimWorkingSet([string[]]$ProcNames) {
  $report = @()
  try {
    Add-Type -Name NativePsapi -Namespace Win32 -MemberDefinition '[DllImport("psapi.dll")] public static extern int EmptyWorkingSet(IntPtr hProcess);' -ErrorAction Stop
  } catch { return $report }
  foreach ($n in ($ProcNames | Where-Object { $_ } | Select-Object -Unique)) {
    foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
      try {
        $beforeMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        [void][Win32.NativePsapi]::EmptyWorkingSet($p.Handle)
        $p.Refresh()
        $afterMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        $report += ("{0} (pid {1}): {2} MB -> {3} MB" -f $n, $p.Id, $beforeMB, $afterMB)
      } catch {}
    }
  }
  return $report
}

function Get-StorageSenseState {
  $ss = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -ErrorAction SilentlyContinue
  if ($ss -and $ss.PSObject.Properties['01']) { return ([int]$ss.'01' -eq 1) }
  return $false
}

# ============================================================
# JSON_SUMMARY builder + output
# ============================================================
function Get-SkillRootDir {
  # 可移植：从本脚本位置推导 skill 安装根目录，绝不写死绝对路径
  $scriptDir = Split-Path -Parent $PSCommandPath
  if ((Split-Path -Leaf $scriptDir) -ieq 'scripts') { return (Split-Path -Parent $scriptDir) }
  return $scriptDir
}
function Get-SkillLogDir {
  $logDir = Join-Path (Get-SkillRootDir) 'logs'
  if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
  }
  return $logDir
}
function Get-DefaultLogPath {
  return (Join-Path (Get-SkillLogDir) ("win-c-clear-skill_log_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
}

function Test-ShKey {
  # 判断 [ordered]/Hashtable/PSCustomObject 是否含某键并取值（键值可为非空）
  param($Obj, [string]$Key)
  if ($null -eq $Obj) { return $false }
  if ($Obj -is [System.Collections.IDictionary]) {
    if (-not $Obj.Contains($Key)) { return $false }
    return $null -ne $Obj[$Key]
  }
  $p = $Obj.PSObject.Properties[$Key]
  return ($null -ne $p -and $null -ne $p.Value)
}

# ============================================================
# 结构化清理报告（精细化 / 标准化 / 现代化 / 模块化 / 结构化）
# 报告由若干独立模块函数组合而成，每个模块自包含、可单独演进。
# ============================================================
$Script:ReportSchemaVersion = '2.0'

function Get-StatusIcon([string]$Status) {
  switch -Wildcard ($Status) {
    'cleaned'   { return '[OK]  ' }
    'scanned'   { return '[SCAN]' }
    'skipped'   { return '[SKIP]' }
    'need-admin'{ return '[ADM] ' }
    'locked'    { return '[LOCK]' }
    'dryrun'    { return '[DRY] ' }
    'error'     { return '[ERR] ' }
    '*guardrail*'{ return '[BLK] ' }
    default     { return '[--]  ' }
  }
}

function Get-TierIcon([string]$Tier) {
  switch ($Tier) {
    'safe'      { return '[S]' }
    'caution'   { return '[C]' }
    'dangerous' { return '[D]' }
    default     { return '[?]' }
  }
}

function Get-GroupCounts([object[]]$Items, [string]$Field) {
  # 按字段值分组计数，返回按数量降序的 PSCustomObject（键值对可被 .PSObject.Properties 正确枚举）。
  # 空值归入 'unknown' 以保留完整性。
  $map = [ordered]@{}
  foreach ($it in @($Items)) {
    $v = [string]$it.$Field
    if ([string]::IsNullOrWhiteSpace($v)) { $v = 'unknown' }
    if ($map.Contains($v)) { $map[$v] = [int]$map[$v] + 1 } else { $map[$v] = 1 }
  }
  $sorted = [ordered]@{}
  foreach ($kv in ($map.GetEnumerator() | Sort-Object Value -Descending)) { $sorted[$kv.Key] = $kv.Value }
  if ($sorted.Count -eq 0) { return [pscustomobject]@{} }
  return [pscustomobject]$sorted
}

function Get-GroupSumGB([object[]]$Items, [string]$Field, [string]$ValueField) {
  # 按字段值分组求和（GB），返回按和值降序的 PSCustomObject。
  $map = [ordered]@{}
  foreach ($it in @($Items)) {
    $v = [string]$it.$Field
    if ([string]::IsNullOrWhiteSpace($v)) { $v = 'unknown' }
    $sum = [double]$it.$ValueField
    if ($map.Contains($v)) { $map[$v] += $sum } else { $map[$v] = $sum }
  }
  $sorted = [ordered]@{}
  foreach ($kv in ($map.GetEnumerator() | Sort-Object Value -Descending)) {
    $sorted[$kv.Key] = [math]::Round($kv.Value, 2)
  }
  if ($sorted.Count -eq 0) { return [pscustomobject]@{} }
  return [pscustomobject]$sorted
}

function Get-SkillReportsDir {
  $dir = Join-Path (Get-SkillRootDir) 'reports'
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
  }
  return $dir
}

function Get-DefaultReportPath {
  return (Join-Path (Get-SkillReportsDir) ("win-c-clear-report_{0}.md" -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
}

function Add-ReportHeader {
  param($L, $SummaryObj)
  $L.Add('')
  $L.Add('+================================================================+')
  $L.Add('|              win-c-clear-skill  清理执行报告                    |')
  $L.Add('+================================================================+')
  $L.Add(('  报告版本     : schema v{0}' -f $Script:ReportSchemaVersion))
  $L.Add(('  生成时间     : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
  $L.Add(('  报告标识     : {0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 12))))
  $L.Add(('  执行模式     : {0}' -f $SummaryObj.mode))
  $L.Add('')
}

function Add-ReportSection-Overview {
  param($L, $SummaryObj)
  $L.Add('[01] 执行概要 ----------------------------------------------------')
  $L.Add(('  模式         : {0}' -f $SummaryObj.mode))
  $L.Add(('  策略         : {0}' -f $Policy))
  $L.Add(('  规则集       : {0}' -f $RuleSets))
  $L.Add(('  扫描模式     : {0}' -f $ScanMode))
  $L.Add(('  路径过滤     : {0}' -f $PathFilter))
  if (Test-ShKey $SummaryObj 'scanRating') {
    $r = $SummaryObj.scanRating
    $L.Add(('  系统评级     : {0}  ({1}/100)  {2}' -f $r.grade, $r.score, $r.status))
  }
  $L.Add(('  DryRun       : {0}' -f [bool]$DryRun))
  $L.Add('')
}

function Add-ReportSection-Environment {
  param($L, $SummaryObj)
  $L.Add('[02] 运行环境 ----------------------------------------------------')
  $L.Add(('  操作系统     : {0} (build {1})' -f $SummaryObj.os.caption, $SummaryObj.os.build))
  $adminIcon = if (Test-IsAdmin) { '[OK] 是' } else { '[--] 否' }
  $L.Add(('  管理员权限   : {0}' -f $adminIcon))
  $L.Add(('  并行线程数   : {0}' -f $threads))
  $L.Add(('  门控开关     : ConfirmIds="{0}"  AllowStop={1}  BackupDangerous={2}' -f $ConfirmIds, [bool]$AllowStop, [bool]$BackupDangerous))
  $L.Add('')
}

function Add-ReportSection-Disk {
  param($L, $SummaryObj)
  $L.Add('[03] 磁盘空间 ----------------------------------------------------')
  $before = [double]$SummaryObj.drive.freeGB_before
  $after  = [double]$SummaryObj.drive.freeGB_after
  $delta  = [math]::Round($after - $before, 2)
  $sign   = if ($delta -ge 0) { '+' } else { '' }
  $L.Add(('  盘符 {0}:      {1,8:N2} GB  -->  {2,8:N2} GB   ({3}{4:N2} GB)' -f $SummaryObj.drive.letter, $before, $after, $sign, $delta))
  $L.Add('')
}

function Add-ReportSection-Targets {
  param($L, $SummaryObj)
  $L.Add('[04] 目标统计 ----------------------------------------------------')
  if (Test-ShKey $SummaryObj 'counts') {
    $c = $SummaryObj.counts
    if (Test-ShKey $c 'existingTotal') {
      $L.Add(('  现存目标     : {0}' -f $c.existingTotal))
      $L.Add(('  缺失目标     : {0}' -f $c.missing))
      $L.Add(('  禁用目标     : {0}' -f $c.disabled))
      if (Test-ShKey $c 'existingByTier') {
        $bt = $c.existingByTier
        $L.Add(('  [S] safe     : {0}' -f $bt.safe))
        $L.Add(('  [C] caution  : {0}' -f $bt.caution))
        $L.Add(('  [D] dangerous: {0}' -f $bt.dangerous))
      }
      $L.Add(('  现存总大小   : {0:N2} GB' -f [double]$c.existingGB))
    } elseif (Test-ShKey $c 'byOrigin') {
      foreach ($k in @($c.byOrigin.PSObject.Properties)) {
        $L.Add(('  来源 {0,-14}: {1}' -f $k.Name, $k.Value))
      }
    }
  } else {
    $L.Add('  (本次模式无目标统计)')
  }
  $L.Add('')
}

function Add-ReportSection-Results {
  param($L, $SummaryObj)
  $L.Add('[05] 执行结果 ----------------------------------------------------')
  $t = $SummaryObj.totals
  $L.Add(('  已释放空间   : {0:N2} GB' -f [double]$t.freedGB))
  $L.Add(('  已清理目标   : {0}' -f $t.cleaned))
  $L.Add(('  跳过目标     : {0}' -f $t.skipped))
  $L.Add(('  需管理员     : {0}' -f $t.needAdmin))
  $L.Add(('  错误         : {0}' -f $t.errors))
  $L.Add('')
}

function Add-ReportSection-Fences {
  param($L, $SummaryObj)
  $L.Add('[06] 门禁与围栏 --------------------------------------------------')
  $L.Add(('  白名单过滤   : 跳过 {0} 项（仅扫描可安全清理目录）' -f $whitelistSkipped))
  $L.Add(('  黑名单过滤   : 跳过 {0} 项（系统核心区域严禁扫描）' -f $blacklistSkipped))
  $guardHit = @($SummaryObj.items | Where-Object { $_.status -like '*guardrail*' -or $_.status -eq 'blocked-by-guardrail' }).Count
  $L.Add(('  守护护栏拦截 : {0} 项' -f $guardHit))
  $L.Add('')
}

function Add-ReportSection-Details {
  param($L, $SummaryObj)
  $L.Add('[07] 关键目标明细 (Top 10) ---------------------------------------')
  $detail = @($SummaryObj.items | Where-Object { $_.sizeGB_before -gt 0 -or $_.sizeGB_after -gt 0 -or $_.freedGB -gt 0 } | Sort-Object { [math]::Max([double]$_.sizeGB_before, [double]$_.freedGB) } -Descending | Select-Object -First 10)
  if ($detail.Count -eq 0) {
    $L.Add('  (无)')
  } else {
    $L.Add('  状态  层级  目标 ID                    前(GB)   后(GB)   释放(GB)')
    $L.Add('  ----  ----  -------------------------  -------  -------  --------')
    foreach ($it in $detail) {
      $L.Add(('  {0} {1} {2,-25} {3,8:N2} {4,8:N2} {5,9:N2}' -f (Get-StatusIcon $it.status), (Get-TierIcon $it.tier), $it.id, [double]$it.sizeGB_before, [double]$it.sizeGB_after, [double]$it.freedGB))
    }
  }
  $L.Add('')
}

function Add-ReportSection-Artifacts {
  param($L, $SummaryObj)
  $L.Add('[08] 产物与路径 --------------------------------------------------')
  if (Test-ShKey $SummaryObj 'logPath') { $L.Add(('  日志文件     : {0}' -f $SummaryObj.logPath)) }
  if (Test-ShKey $SummaryObj 'mergedConfigPath') { $L.Add(('  合并配置     : {0}' -f $SummaryObj.mergedConfigPath)) }
  if (Test-ShKey $SummaryObj 'configPath') { $L.Add(('  主配置       : {0}' -f $SummaryObj.configPath)) }
  if (Test-ShKey $SummaryObj 'quarantine') {
    $q = $SummaryObj.quarantine
    $L.Add(('  隔离区       : {0} ({1} 项)' -f $q.root, $q.items))
  }
  $L.Add('')
}

function Add-ReportSection-Recommendations {
  # 数据驱动的下一步建议（精细化 / 可执行）
  param($L, $SummaryObj)
  $L.Add('[09] 建议与下一步 ------------------------------------------------')
  $recs = New-Object System.Collections.Generic.List[string]
  $t = $SummaryObj.totals
  $mode = $SummaryObj.mode

  if ($mode -eq 'Scan') {
    if (Test-ShKey $SummaryObj 'counts' -and (Test-ShKey $SummaryObj.counts 'existingGB')) {
      $gb = [double]$SummaryObj.counts.existingGB
      if ($gb -gt 1) {
        $recs.Add(('  - 发现约 {0:N2} GB 可清理项，建议执行 Clean 释放空间' -f $gb))
      }
    }
    $safeCount = 0
    if (Test-ShKey $SummaryObj 'counts' -and (Test-ShKey $SummaryObj.counts 'existingByTier')) { $safeCount = [int]$SummaryObj.counts.existingByTier.safe }
    if ($safeCount -gt 0) { $recs.Add(('  - 可先清理 {0} 个 safe 档目标（风险最低）' -f $safeCount)) }
    $cautionCount = 0
    if (Test-ShKey $SummaryObj 'counts' -and (Test-ShKey $SummaryObj.counts 'existingByTier')) { $cautionCount = [int]$SummaryObj.counts.existingByTier.caution }
    if ($cautionCount -gt 0) { $recs.Add(('  - {0} 个 caution 档目标需点名确认（-ConfirmIds）后再清理' -f $cautionCount)) }
  }

  if ($mode -eq 'Clean') {
    if ([double]$t.freedGB -gt 0) { $recs.Add(('  - 本次已释放 {0:N2} GB' -f [double]$t.freedGB)) }
    if ([int]$t.needAdmin -gt 0) { $recs.Add(('  - {0} 项需管理员权限，建议以管理员身份重跑并加 -Elevate' -f [int]$t.needAdmin)) }
    if ([int]$t.skipped -gt 0) { $recs.Add(('  - {0} 项被跳过（热文件/危险扩展/围栏），属正常保护行为' -f [int]$t.skipped)) }
    if ([int]$t.errors -gt 0) { $recs.Add(('  - {0} 项出错，请查看日志明细定位' -f [int]$t.errors)) }
  }

  if (Test-ShKey $SummaryObj 'scanRating') {
    $grade = [string]$SummaryObj.scanRating.grade
    if ($grade -in @('D','E','F')) {
      $recs.Add('  - 系统堆积评级偏低，建议定期运行本 skill 维持磁盘健康')
    } elseif ($grade -in @('A','B')) {
      $recs.Add('  - 系统较干净，保持当前清理频率即可')
    }
  }

  if ($recs.Count -eq 0) { $recs.Add('  - 无特别建议') }
  foreach ($r in $recs) { $L.Add($r) }
  $L.Add('')
}

function Add-ReportVerdict {
  param($L, $SummaryObj)
  $L.Add('[10] 结论 --------------------------------------------------------')
  $t = $SummaryObj.totals
  $mode = $SummaryObj.mode
  $verdict = ''
  if ($mode -eq 'Scan') {
    $gb = 0.0
    if (Test-ShKey $SummaryObj 'counts' -and (Test-ShKey $SummaryObj.counts 'existingGB')) { $gb = [double]$SummaryObj.counts.existingGB }
    $verdict = ('扫描完成：发现 {0:N2} GB 可清理项，等待用户核准后执行 Clean。' -f $gb)
  } elseif ($mode -eq 'Clean') {
    $verdict = ('清理完成：释放 {0:N2} GB，清理 {1} 项，跳过 {2} 项，错误 {3} 项。' -f [double]$t.freedGB, [int]$t.cleaned, [int]$t.skipped, [int]$t.errors)
  } else {
    $verdict = ('{0} 模式执行完成。' -f $mode)
  }
  $L.Add(('  {0}' -f $verdict))
  $L.Add('')
  $L.Add('+================================================================+')
}

function Write-StructuredReport {
  # 组合各模块生成完整报告（写入日志文件 + 控制台）
  param($SummaryObj)
  $L = New-Object System.Collections.Generic.List[string]
  Add-ReportHeader               $L $SummaryObj
  Add-ReportSection-Overview     $L $SummaryObj
  Add-ReportSection-Environment  $L $SummaryObj
  Add-ReportSection-Disk         $L $SummaryObj
  Add-ReportSection-Targets      $L $SummaryObj
  Add-ReportSection-Results      $L $SummaryObj
  Add-ReportSection-Fences       $L $SummaryObj
  Add-ReportSection-Details      $L $SummaryObj
  Add-ReportSection-Artifacts    $L $SummaryObj
  Add-ReportSection-Recommendations $L $SummaryObj
  Add-ReportVerdict              $L $SummaryObj
  return $L
}

function Write-MarkdownReport {
  # 生成模板化/结构化/模块化/系统化/精细化的中文 Markdown 清理报告。
  # 输出为可发送的独立 .md 文件（区别于控制台 & JSON 契约），供用户留存/转发。
  param($SummaryObj)
  $M = New-Object System.Collections.Generic.List[string]
  $mode = [string]$SummaryObj.mode
  $t = $SummaryObj.totals

  # ---- 标题与元信息 ----
  $M.Add('# win-c-clear-skill 清理执行报告')
  $M.Add('')
  $M.Add('| 项目 | 内容 |')
  $M.Add('|------|------|')
  $M.Add(('| 报告版本 | schema v{0} |' -f $Script:ReportSchemaVersion))
  $M.Add(('| 生成时间 | {0} |' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
  $M.Add(('| 报告标识 | {0} |' -f ([guid]::NewGuid().ToString('N').Substring(0, 12))))
  $M.Add(('| 执行模式 | {0} |' -f $mode))
  $M.Add('')
  $M.Add('---')
  $M.Add('')

  # ---- 1. 执行概要 ----
  $M.Add('## 1. 执行概要')
  $M.Add('')
  $M.Add('| 项目 | 值 |')
  $M.Add('|------|-----|')
  $M.Add(('| 模式 | {0} |' -f $mode))
  $M.Add(('| 策略 | {0} |' -f $Policy))
  $M.Add(('| 规则集 | {0} |' -f $(if ($RuleSets) { $RuleSets } else { 'minimal' })))
  $M.Add(('| 扫描模式 | {0} |' -f $ScanMode))
  $M.Add(('| 路径过滤 | {0} |' -f $PathFilter))
  $M.Add(('| DryRun | {0} |' -f [bool]$DryRun))
  if (Test-ShKey $SummaryObj 'scanRating') {
    $r = $SummaryObj.scanRating
    $M.Add(('| 系统评级 | {0}（{1}/100）{2} |' -f $r.grade, $r.score, $r.status))
  }
  $M.Add('')

  # ---- 2. 运行环境 ----
  $M.Add('## 2. 运行环境')
  $M.Add('')
  $M.Add('| 项目 | 值 |')
  $M.Add('|------|-----|')
  if (Test-ShKey $SummaryObj 'os') {
    $M.Add(('| 操作系统 | {0}（build {1}） |' -f $SummaryObj.os.caption, $SummaryObj.os.build))
  }
  $M.Add(('| 管理员权限 | {0} |' -f $(if (Test-IsAdmin) { '是' } else { '否' })))
  $M.Add(('| 并行线程数 | {0} |' -f $threads))
  $M.Add(('| ConfirmIds | {0} |' -f $(if ($ConfirmIds) { $ConfirmIds } else { '（无）' })))
  $M.Add(('| AllowStop | {0} |' -f [bool]$AllowStop))
  $M.Add(('| BackupDangerous | {0} |' -f [bool]$BackupDangerous))
  $M.Add('')

  # ---- 3. 磁盘空间 ----
  $M.Add('## 3. 磁盘空间变化')
  $M.Add('')
  if (Test-ShKey $SummaryObj 'drive') {
    $before = [double]$SummaryObj.drive.freeGB_before
    $after  = [double]$SummaryObj.drive.freeGB_after
    $delta  = [math]::Round($after - $before, 2)
    $sign   = if ($delta -ge 0) { '+' } else { '' }
    $M.Add('| 盘符 | 清理前 | 清理后 | 变化 |')
    $M.Add('|------|-------|-------|------|')
    $M.Add(('| {0} | {1:N2} GB | {2:N2} GB | {3}{4:N2} GB |' -f $SummaryObj.drive.letter, $before, $after, $sign, $delta))
  }
  $M.Add('')

  # ---- 4. 目标统计 ----
  $M.Add('## 4. 目标统计')
  $M.Add('')
  if (Test-ShKey $SummaryObj 'counts') {
    $c = $SummaryObj.counts
    if (Test-ShKey $c 'existingTotal' -and (Test-ShKey $c 'missing') -and (Test-ShKey $c 'disabled')) {
      # Scan 模式统计结构
      $M.Add('| 维度 | 数量 |')
      $M.Add('|------|------|')
      $M.Add(('| 现存目标 | {0} |' -f $c.existingTotal))
      $M.Add(('| 缺失目标 | {0} |' -f [int]$c.missing))
      $M.Add(('| 禁用目标 | {0} |' -f [int]$c.disabled))
      $M.Add(('| 现存总大小 | {0:N2} GB |' -f [double]$c.existingGB))
      $M.Add('')
      if (Test-ShKey $c 'existingByTier') {
        $bt = $c.existingByTier
        $M.Add('**按风险分级**')
        $M.Add('')
        $M.Add('| 分级 | 数量 |')
        $M.Add('|------|------|')
        $M.Add(('| safe（安全） | {0} |' -f $bt.safe))
        $M.Add(('| caution（谨慎） | {0} |' -f $bt.caution))
        $M.Add(('| dangerous（危险） | {0} |' -f $bt.dangerous))
        $M.Add('')
      }
      if (Test-ShKey $c 'existingByCategory' -and $c.existingByCategory -and @($c.existingByCategory.PSObject.Properties).Count -gt 0) {
        $M.Add('**按规则分类**')
        $M.Add('')
        $M.Add('| 分类 | 数量 |')
        $M.Add('|------|------|')
        foreach ($k in @($c.existingByCategory.PSObject.Properties)) { $M.Add(('| {0} | {1} |' -f $k.Name, $k.Value)) }
        $M.Add('')
      }
    } elseif (Test-ShKey $c 'selectedTotal') {
      # Clean 模式统计结构
      $M.Add('| 维度 | 数量 |')
      $M.Add('|------|------|')
      $M.Add(('| 选定目标 | {0} |' -f [int]$c.selectedTotal))
      $M.Add(('| 路径存在 | {0} |' -f [int]$c.existingTotal))
      $M.Add('')
      if (Test-ShKey $c 'byTier' -and $c.byTier -and @($c.byTier.PSObject.Properties).Count -gt 0) {
        $M.Add('**按风险分级（选定项）**')
        $M.Add('')
        $M.Add('| 分级 | 数量 |')
        $M.Add('|------|------|')
        foreach ($k in @($c.byTier.PSObject.Properties)) { $M.Add(('| {0} | {1} |' -f $k.Name, $k.Value)) }
        $M.Add('')
      }
      if (Test-ShKey $c 'freedByTier' -and $c.freedByTier -and @($c.freedByTier.PSObject.Properties).Count -gt 0) {
        $M.Add('**按风险分级释放**')
        $M.Add('')
        $M.Add('| 分级 | 释放 (GB) |')
        $M.Add('|------|-----------|')
        foreach ($k in @($c.freedByTier.PSObject.Properties)) { $M.Add(('| {0} | {1:N2} |' -f $k.Name, [double]$k.Value)) }
        $M.Add('')
      }
      if (Test-ShKey $c 'byCategory' -and $c.byCategory -and @($c.byCategory.PSObject.Properties).Count -gt 0) {
        $M.Add('**按规则分类（选定项）**')
        $M.Add('')
        $M.Add('| 分类 | 数量 |')
        $M.Add('|------|------|')
        foreach ($k in @($c.byCategory.PSObject.Properties)) { $M.Add(('| {0} | {1} |' -f $k.Name, $k.Value)) }
        $M.Add('')
      }
      if (Test-ShKey $c 'freedByCategory' -and $c.freedByCategory -and @($c.freedByCategory.PSObject.Properties).Count -gt 0) {
        $M.Add('**按规则分类释放**')
        $M.Add('')
        $M.Add('| 分类 | 释放 (GB) |')
        $M.Add('|------|-----------|')
        foreach ($k in @($c.freedByCategory.PSObject.Properties)) { $M.Add(('| {0} | {1:N2} |' -f $k.Name, [double]$k.Value)) }
        $M.Add('')
      }
    }
  } else {
    $M.Add('（本次模式无目标统计）')
    $M.Add('')
  }

  # ---- 5. 执行结果 ----
  $M.Add('## 5. 执行结果')
  $M.Add('')
  $M.Add('| 指标 | 值 |')
  $M.Add('|------|-----|')
  $M.Add(('| 已释放空间 | {0:N2} GB |' -f [double]$t.freedGB))
  $M.Add(('| 已清理目标 | {0} |' -f [int]$t.cleaned))
  $M.Add(('| 跳过目标 | {0} |' -f [int]$t.skipped))
  $M.Add(('| 需管理员 | {0} |' -f [int]$t.needAdmin))
  $M.Add(('| 错误 | {0} |' -f [int]$t.errors))
  $M.Add('')

  # ---- 6. 门禁与围栏 ----
  $M.Add('## 6. 门禁与围栏')
  $M.Add('')
  $guardHit = @($SummaryObj.items | Where-Object { $_.status -like '*guardrail*' -or $_.status -eq 'blocked-by-guardrail' }).Count
  $M.Add('| 围栏 | 拦截/过滤 | 说明 |')
  $M.Add('|------|----------|------|')
  $M.Add(('| 白名单过滤 | {0} 项 | 仅扫描预设可安全清理目录 |' -f $whitelistSkipped))
  $M.Add(('| 黑名单过滤 | {0} 项 | 系统核心区域严禁扫描 |' -f $blacklistSkipped))
  $M.Add(('| 守护护栏拦截 | {0} 项 | 引擎级硬编码保护 |' -f $guardHit))
  $M.Add('')

  # ---- 后续章节编号：Clean 有释放明细时从 7 开始，否则从 7 直接为关键目标明细 ----
  $secNum = 7
  # ---- 分级/分类释放明细（仅 Clean 且有释放项时输出） ----
  if ($mode -eq 'Clean') {
    $cleanedItems = @($SummaryObj.items | Where-Object { [double]$_.freedGB -gt 0 })
    if ($cleanedItems.Count -gt 0) {
      $M.Add(('## {0}. 释放明细（按分级 / 分类）' -f $secNum))
      $secNum++
      $M.Add('')
      $byTier = Get-GroupSumGB $cleanedItems 'tier' 'freedGB'
      $M.Add('**按风险分级释放**')
      $M.Add('')
      $M.Add('| 分级 | 释放 (GB) |')
      $M.Add('|------|-----------|')
      foreach ($k in @($byTier.PSObject.Properties)) { $M.Add(('| {0} | {1:N2} |' -f $k.Name, [double]$k.Value)) }
      $M.Add('')
      $byCat = Get-GroupSumGB $cleanedItems 'category' 'freedGB'
      if ($byCat -and @($byCat.PSObject.Properties).Count -gt 0) {
        $M.Add('**按规则分类释放**')
        $M.Add('')
        $M.Add('| 分类 | 释放 (GB) |')
        $M.Add('|------|-----------|')
        foreach ($k in @($byCat.PSObject.Properties)) { $M.Add(('| {0} | {1:N2} |' -f $k.Name, [double]$k.Value)) }
        $M.Add('')
      }
    }
  }

  # ---- 关键目标明细 ----
  $M.Add(('## {0}. 关键目标明细' -f $secNum))
  $secNum++
  $M.Add('')
  $detail = @($SummaryObj.items | Where-Object { [double]$_.sizeGB_before -gt 0 -or [double]$_.freedGB -gt 0 } | Sort-Object { [math]::Max([double]$_.sizeGB_before, [double]$_.freedGB) } -Descending | Select-Object -First 10)
  if ($detail.Count -eq 0) {
    $M.Add('（无）')
  } else {
    $M.Add('| 状态 | 分级 | 分类 | 目标 ID | 前 (GB) | 后 (GB) | 释放 (GB) |')
    $M.Add('|------|------|------|---------|---------|---------|-----------|')
    foreach ($it in $detail) {
      $cat = if ($it.category) { [string]$it.category } else { '-' }
      $M.Add(('| {0} | {1} | {2} | {3} | {4:N2} | {5:N2} | {6:N2} |' -f $it.status, $it.tier, $cat, $it.id, [double]$it.sizeGB_before, [double]$it.sizeGB_after, [double]$it.freedGB))
    }
  }
  $M.Add('')

  # ---- 性能指标 ----
  $M.Add(('## {0}. 性能指标' -f $secNum))
  $secNum++
  $M.Add('')
  $M.Add('| 指标 | 值 |')
  $M.Add('|------|-----|')
  $scanMs = if (Test-ShKey $SummaryObj 'scanMs') { [double]$SummaryObj.scanMs } else { 0.0 }
  $M.Add(('| 扫描耗时 | {0:N0} ms |' -f $scanMs))
  $M.Add(('| 并行线程数 | {0} |' -f $threads))
  if (Test-ShKey $SummaryObj 'cacheHits') { $M.Add(('| 缓存命中 | {0} |' -f [int]$SummaryObj.cacheHits)) }
  if ($mode -eq 'Clean' -and $scanMs -gt 0 -and [double]$t.freedGB -gt 0) {
    $rate = [double]$t.freedGB * 1024.0 / ($scanMs / 1000.0)  # MB/s
    $M.Add(('| 清理吞吐 | {0:N1} MB/s（按扫描耗时估算） |' -f $rate))
  }
  $M.Add('')

  # ---- 产物与路径 ----
  $M.Add(('## {0}. 产物与路径' -f $secNum))
  $M.Add('')
  $M.Add('| 类型 | 路径 |')
  $M.Add('|------|------|')
  if (Test-ShKey $SummaryObj 'logPath') { $M.Add(('| 日志文件 | {0} |' -f $SummaryObj.logPath)) }
  if (Test-ShKey $SummaryObj 'reportPath') { $M.Add(('| 中文报告 | {0} |' -f $SummaryObj.reportPath)) }
  if (Test-ShKey $SummaryObj 'mergedConfigPath') { $M.Add(('| 合并配置 | {0} |' -f $SummaryObj.mergedConfigPath)) }
  if (Test-ShKey $SummaryObj 'configPath') { $M.Add(('| 主配置 | {0} |' -f $SummaryObj.configPath)) }
  if (Test-ShKey $SummaryObj 'quarantine') {
    $q = $SummaryObj.quarantine
    $M.Add(('| 隔离区 | {0}（{1} 项） |' -f $q.root, $q.items))
    # Markdown 表格内管道需转义；路径反斜杠保持原样即可
    $restoreCmd = ([string]$q.restore) -replace '\|', '\|'
    $M.Add(('| 恢复命令 | `{0}` |' -f $restoreCmd))
  }
  $M.Add('')

  return ($M -join [Environment]::NewLine)
}

function Write-SummaryAndLog {
  param($SummaryObj, [string]$LogFilePath)
  # trim long messages for token economy
  foreach ($it in @($SummaryObj.items)) {
    if ($it -and $it.message -and ([string]$it.message).Length -gt 160) {
      $it.message = ([string]$it.message).Substring(0, 157) + '...'
    }
  }
  # 生成模板化/结构化/模块化/系统化/精细化的中文 Markdown 清理报告（独立 .md 文件，可发送/转发）
  $reportPathFinal = if ($ReportFile) { $ReportFile } else { Get-DefaultReportPath }
  try {
    $mdReport = Write-MarkdownReport $SummaryObj
    $rDir = Split-Path -Parent $reportPathFinal
    if ($rDir -and -not (Test-Path -LiteralPath $rDir)) { New-Item -ItemType Directory -Path $rDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($reportPathFinal, $mdReport, (New-Object System.Text.UTF8Encoding($true)))
    if ($SummaryObj -is [System.Collections.IDictionary]) { $SummaryObj['reportPath'] = $reportPathFinal }
    elseif ($null -ne $SummaryObj) { $SummaryObj | Add-Member -NotePropertyName reportPath -NotePropertyValue $reportPathFinal -Force -ErrorAction SilentlyContinue }
    Write-Host ("中文清理报告 : {0}" -f $reportPathFinal) -ForegroundColor Cyan
  } catch {
    Write-Host ("[WARN] 中文报告生成失败: {0}" -f $_.Exception.Message)
  }
  $jsonOut = if ($PrettyJson) { $SummaryObj | ConvertTo-Json -Depth 8 }
             else { $SummaryObj | ConvertTo-Json -Depth 8 -Compress }
  Write-Host ''
  Write-Host '---------- JSON_SUMMARY_BEGIN ----------'
  Write-Host $jsonOut
  Write-Host '---------- JSON_SUMMARY_END ----------'
  # 结构化模块化报告：控制台 + 日志文件（写到 skill 根目录 logs/，可移植）
  $reportLines = Write-StructuredReport $SummaryObj
  try {
    $dir = Split-Path -Parent $LogFilePath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $reportLines | Set-Content -LiteralPath $LogFilePath -Encoding UTF8
  } catch {}
  # 控制台报告（与 JSON_SUMMARY 分离，便于人类阅读）
  foreach ($ln in $reportLines) { Write-Host $ln }
  if ($ResultFile) {
    try { [System.IO.File]::WriteAllText($ResultFile, $jsonOut, (New-Object System.Text.UTF8Encoding($false))) } catch {}
  }
}

function New-BaseSummary([string]$ModeName, [string]$DriveLetter, [double]$FreeBefore) {
  $os = Get-OSInfo
  return [ordered]@{
    schemaVersion = 1
    mode = $ModeName
    os = @{ caption = $os.caption; build = $os.build; isServer = $os.isServer }
    drive = @{ letter = $DriveLetter; freeGB_before = $FreeBefore; freeGB_after = $FreeBefore }
    items = @()
    totals = @{ freedGB = 0.0; cleaned = 0; skipped = 0; needAdmin = 0; errors = 0 }
    logPath = ''
  }
}

# ============================================================
# MAIN
# ============================================================
$configPath = Resolve-ConfigPath $Config
$cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$driveLetter = if ($cfg.drive) { [string]$cfg.drive } else { 'C' }
$scriptDir = Split-Path -Parent $PSCommandPath
$configDir = Split-Path -Parent $configPath
$mergedPath = Join-Path $configDir 'targets.merged.json'
$overridesPath = Join-Path $configDir 'user-overrides.json'
$ruleDirs = Get-CCPDirsFromConfig $cfg $CCPDirs $configDir

# default tiers per mode + policy (strategy layer)
#   conservative: safe only, builtin/merged origin only (ignores community rule enablement)
#   standard    : current defaults (Clean=safe; Scan=safe,caution)
#   deep        : adds caution candidates to Clean (gates still apply: ConfirmIds/AllowStop)
if (-not $Tiers) {
  switch ($Policy) {
    'conservative' { $Tiers = 'safe' }
    'deep' { $Tiers = 'safe,caution' }
    default { $Tiers = if ($Mode -eq 'Clean') { 'safe' } else { 'safe,caution' } }
  }
}
$tierSet = @{}
foreach ($t in ($Tiers -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })) { $tierSet[$t] = $true }
$idFilter = $null
if ($Ids) {
  $idFilter = @{}
  foreach ($i in ($Ids -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { $idFilter[$i] = $true }
}
$confirmSet = @{}
if ($ConfirmIds) {
  foreach ($i in ($ConfirmIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { $confirmSet[$i] = $true }
}

$threads = if ($MaxThreads -gt 0) { $MaxThreads } else { [Environment]::ProcessorCount }

Write-Host ''
Write-Host '=============================================='
Write-Host ("  win-c-clear-skill   Mode={0}" -f $Mode)
Write-Host '=============================================='
Write-Host ("Config : {0}" -f $configPath)
Write-Host ("OS     : {0} (build {1})" -f (Get-OSInfo).caption, (Get-OSInfo).build)
Write-Host ("Admin  : {0}" -f (Test-IsAdmin))
Write-Host ("Threads: {0}" -f $threads)
if ($DryRun) { Write-Host 'DryRun : TRUE (no deletion will happen)' -ForegroundColor Cyan }

# ------------------------------------------------------------
# Mode: MergeConfig
# ------------------------------------------------------------
if ($Mode -eq 'MergeConfig') {
  if ($ruleDirs.Count -eq 0) {
    Write-Host '[ERROR] No c_cleaner_plus directories configured (mergeSources in targets.json or -CCPDirs).'
    exit 3
  }
  Write-Host ("Merging c_cleaner_plus rules from: {0}" -f ($ruleDirs -join ' ; '))
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $mergedData = Invoke-ConfigMerge -Dirs $ruleDirs -BuiltinConfigPath $configPath -OutMergedPath $mergedPath -OverridesPath $overridesPath
  $sw.Stop()
  $freeNow = Get-DriveFreeGB $driveLetter
  $summary = New-BaseSummary 'MergeConfig' $driveLetter $freeNow
  $summary.drive.freeGB_after = $freeNow
  $summary.mergedConfigPath = $mergedPath
  $summary.overridesPath = $overridesPath
  $summary.merge = $mergedData.stats
  $summary.merge.durationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
  $summary.merge.sources = $mergedData.sources
  $summary.unparsed = @($mergedData.unparsed | Select-Object -First 50)
  # token-friendly: NO full item list (15k+ entries would explode context);
  # agents read targets.merged.json on demand or present categories from counts
  $byOrigin = @{}
  foreach ($g in @($mergedData.targets | Group-Object origin)) { $byOrigin[$g.Name] = $g.Count }
  $enabledByTier = @{ safe = 0; caution = 0; dangerous = 0 }
  foreach ($t in @($mergedData.targets | Where-Object { $_.enabled })) {
    if ($enabledByTier.ContainsKey($t.tier)) { $enabledByTier[$t.tier]++ }
  }
  $summary.counts = [ordered]@{
    byOrigin = $byOrigin
    enabledByTier = $enabledByTier
    guardrailDemoted = $mergedData.stats.guardrailDemoted
  }
  $summary.note = 'full rule list with ids/tiers/paths is in mergedConfigPath (targets.merged.json); present categories to the user and enable per-id via user-overrides.json'
  $logPathFinal = if ($LogPath) { $LogPath } else { Get-DefaultLogPath }
  $summary.logPath = $logPathFinal
  Write-Host ("Merged {0} unique ccp entries (+{1} collisions with builtin) in {2:N1}s" -f `
    $mergedData.stats.uniqueCcpEntries, $mergedData.stats.pathCollisionsWithBuiltin, $sw.Elapsed.TotalSeconds)
  Write-Host ("Output: {0}" -f $mergedPath)
  if (@($mergedData.unparsed).Count -gt 0) {
    Write-Host ("[WARN] {0} unparsed entries (see JSON unparsed list)" -f @($mergedData.unparsed).Count) -ForegroundColor Yellow
  }
  Write-SummaryAndLog $summary $logPathFinal
  exit 0
}

# ------------------------------------------------------------
# Auto-merge when ccp dirs exist and merged file is stale
# ------------------------------------------------------------
$mergedData = $null
$overridesData = $null
if ($ruleDirs.Count -gt 0) {
  $needMerge = $true
  if (Test-Path -LiteralPath $mergedPath) {
    $needMerge = $false
    $mergedMtime = (Get-Item -LiteralPath $mergedPath).LastWriteTime
    foreach ($d in $ruleDirs) {
      if (Test-Path -LiteralPath $d) {
        $newest = Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newest -and $newest.LastWriteTime -gt $mergedMtime) { $needMerge = $true; break }
      }
    }
  }
  if ($needMerge) {
    Write-Host '[INFO] c_cleaner_plus rules changed or not merged yet; running merge pipeline...'
    $mergedData = Invoke-ConfigMerge -Dirs $ruleDirs -BuiltinConfigPath $configPath -OutMergedPath $mergedPath -OverridesPath $overridesPath
  } else {
    try { $mergedData = Get-Content -LiteralPath $mergedPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $mergedData = $null }
  }
  if (Test-Path -LiteralPath $overridesPath) {
    try { $overridesData = Get-Content -LiteralPath $overridesPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $overridesData = $null }
  }
}

$allTargets = Get-EffectiveTargets -BuiltinCfg $cfg -MergedData $mergedData -OverridesData $overridesData
Write-Host ("Targets loaded: {0} (builtin+ccp merged config)" -f $allTargets.Count)

# ------------------------------------------------------------
# Path filtering: whitelist/blacklist (R5-1/R5-3)
# 红线：黑名单（系统核心区域）默认始终生效，仅 -PathFilter off / -NoBlacklist 可关闭；
#       白名单默认生效（whitelist 模式），只扫描预设可安全清理目录。
# 性能：白名单预计算小写+前缀（避免每 target 重复 ToLower）；
#       黑名单 regex 仅对白名单命中的少数目标执行（先粗筛后精查）。
# ------------------------------------------------------------
$whitelistPaths = @()
$blacklistPatterns = @()
$whitelistSkipped = 0
$blacklistSkipped = 0
$whitelistExamples = New-Object System.Collections.Generic.List[string]
$blacklistExamples = New-Object System.Collections.Generic.List[string]

if (-not $NoWhitelist -and $PathFilter -in @('whitelist','both')) {
  $whitelistPaths = Get-WhitelistPaths $configDir
  if ($whitelistPaths.Count -gt 0) {
    Write-Host ("Whitelist loaded: {0} paths" -f $whitelistPaths.Count)
  }
}
# 黑名单默认 ON（红线：系统核心区域严禁扫描），PathFilter off 或 -NoBlacklist 才关闭
$blacklistPatterns = @(Get-EngineGuardPatterns)
if (-not $NoBlacklist -and $PathFilter -ne 'off') {
  $userBlacklist = Get-BlacklistPatterns $configDir
  foreach ($p in $userBlacklist) {
    if ($blacklistPatterns -notcontains $p) { $blacklistPatterns += $p }
  }
}
if ($blacklistPatterns.Count -gt 0) {
  Write-Host ("Blacklist loaded: {0} patterns (engine guards always active; system core areas: scan forbidden)" -f $blacklistPatterns.Count)
}
$scanModeConfig = Get-ScanModeConfig $ScanMode
if ($scanModeConfig.useWhitelist -and $whitelistPaths.Count -eq 0 -and $PathFilter -in @('whitelist','both')) {
  # RED LINE: fail-closed — empty whitelist must NOT fall back to scanning all targets.
  # Keep useWhitelist=true so Test-WhitelistFast denies everything (empty set = deny all).
  Write-Host "[ERROR] Whitelist mode enabled but no whitelist paths loaded. Fail-closed: no targets will pass the whitelist filter. Check config/scan-lists.json." -ForegroundColor Red
}

# 预计算白名单小写形式与前缀（精确匹配用 HashSet，前缀匹配用数组）
$wlLower = @($whitelistPaths | ForEach-Object { ([string]$_).ToLowerInvariant() })
$wlSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($w in $wlLower) { [void]$wlSet.Add($w) }
$wlPrefixes = @($wlLower | ForEach-Object { $_ + '\' })

function Test-WhitelistFast([string]$LowerPath) {
  # RED LINE: empty whitelist = deny all (fail-closed)
  if ($wlSet.Count -eq 0) { return $false }
  if ($wlSet.Contains($LowerPath)) { return $true }
  foreach ($pre in $wlPrefixes) {
    if ($LowerPath.StartsWith($pre)) { return $true }
  }
  # 通配白名单（如 %LOCALAPPDATA%\Packages\*\TempState）
  foreach ($w in $wlLower) {
    if ($w.IndexOf('*') -ge 0) {
      $pattern = '^' + [regex]::Escape($w).Replace('\*', '.*') + '$'
      if ($LowerPath -match $pattern) { return $true }
    }
  }
  return $false
}

# Filter targets based on whitelist/blacklist
$filteredTargets = New-Object System.Collections.Generic.List[object]
$swFilter = [System.Diagnostics.Stopwatch]::StartNew()
# 性能：引擎 Guard 模式只取一次（避免每路径重复函数调用+数组分配）
$engineGuards = @(Get-EngineGuardPatterns)
foreach ($t in $allTargets) {
  $keep = $true
  $paths = Get-TargetPathsExpanded $t   # 单次展开，两道过滤复用

  # 第一道：白名单粗筛（快速字符串前缀）
  if ($scanModeConfig.useWhitelist -and $wlSet.Count -gt 0) {
    $match = $false
    foreach ($p in $paths) {
      if (Test-WhitelistFast ([string]$p).ToLowerInvariant()) { $match = $true; break }
    }
    if (-not $match) {
      $keep = $false
      $whitelistSkipped++
      if ($whitelistExamples.Count -lt 5) { $whitelistExamples.Add($t.id) }
    }
  }

  # 第二道：黑名单精查（regex）。RED LINE: 引擎级 Guard 无条件执行；
  # 用户黑名单按 skipBlacklist 配置执行。
  if ($keep -and $blacklistPatterns.Count -gt 0) {
    foreach ($p in $paths) {
      $pLower = ([string]$p).ToLowerInvariant()
      $blocked = $false
      foreach ($gp in $engineGuards) {
        if ($pLower -match $gp) { $blocked = $true; break }
      }
      if (-not $blocked -and $scanModeConfig.skipBlacklist) {
        $blocked = Test-PathAgainstBlacklist ([string]$p) $blacklistPatterns
      }
      if ($blocked) {
        $keep = $false
        $blacklistSkipped++
        if ($blacklistExamples.Count -lt 5) { $blacklistExamples.Add($t.id) }
        break
      }
    }
  }

  if ($keep) { $filteredTargets.Add($t) }
}
$swFilter.Stop()

if ($whitelistSkipped -gt 0 -or $blacklistSkipped -gt 0) {
  Write-Host ("Path filter: kept {0}/{1} targets, skipped {2} (whitelist), {3} (blacklist) in {4:N1}s" -f `
    $filteredTargets.Count, $allTargets.Count, $whitelistSkipped, $blacklistSkipped, $swFilter.Elapsed.TotalSeconds)
  if ($whitelistExamples.Count -gt 0) {
    Write-Host ("  whitelist-skipped examples: {0}" -f ($whitelistExamples -join ', '))
  }
  if ($blacklistExamples.Count -gt 0) {
    Write-Host ("  blacklist-skipped examples: {0}" -f ($blacklistExamples -join ', ')) -ForegroundColor Yellow
  }
}

$allTargets = $filteredTargets

# ------------------------------------------------------------
# Rule-set selection (guided; rules are NOT all loaded by default)
#   minimal (default) = builtin whitelist only
#   general|cn|dev|design|ai|game|media|system|community = curated/ccp categories
#   all = everything; none = alias of minimal
# ------------------------------------------------------------
$rsRaw = $RuleSets.Trim().ToLowerInvariant()
if ($rsRaw -eq 'none') { $rsRaw = 'minimal' }
if ($rsRaw -ne '' -and $rsRaw -ne 'all') {
  $rsSet = @{}
  foreach ($r in ($rsRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { $rsSet[$r] = $true }
  $keepMin = $rsSet.ContainsKey('minimal')
  $beforeRs = $allTargets.Count
  $filtered = New-Object System.Collections.Generic.List[object]
  foreach ($t in $allTargets) {
    $cat = [string]$t.category
    if (-not $cat) { $cat = if ($t.origin -in @('builtin', 'merged')) { 'builtin' } else { 'general' } }
    if ($keepMin -and $cat -eq 'builtin') { $filtered.Add($t); continue }
    if ($rsSet.ContainsKey($cat)) { $filtered.Add($t); continue }
  }
  $allTargets = $filtered
  Write-Host ("RuleSets '{0}': {1} -> {2} targets (categories kept: {3})" -f $RuleSets, $beforeRs, $allTargets.Count, (($rsSet.Keys | Sort-Object) -join ','))
}

# ------------------------------------------------------------
# Mode: Analyze (diagnostic; read-only)
# ------------------------------------------------------------
if ($Mode -eq 'Analyze') {
  $freeBefore = Get-DriveFreeGB $driveLetter
  $summary = New-BaseSummary 'Analyze' $driveLetter $freeBefore
  $summary.hashPath = 'cpu-parallel'
  # GPU probe (transparent fallback)
  $gpuAvailable = $false
  $gpuName = ''
  if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $gpuName = ((& nvidia-smi --query-gpu=name --format=csv,noheader 2>$null) | Select-Object -First 1)
    if ($gpuName) {
      $gpuAvailable = $true
      $pyOk = $false
      if (Get-Command python -ErrorAction SilentlyContinue) {
        & python -c "import cupy" 2>$null
        if ($LASTEXITCODE -eq 0) { $pyOk = $true }
      }
      if ($pyOk) { $summary.hashPath = 'gpu-cupy' } else { $summary.hashPath = 'cpu-parallel (GPU present, no cupy; fell back)' }
    }
  }
  $summary.gpuAvailable = $gpuAvailable
  $summary.gpuName = $gpuName
  if ($gpuAvailable -and $summary.hashPath -notlike 'gpu-*') {
    $summary.hashPath = 'cpu-parallel-boosted (GPU present: hash threads 2x cores for IO overlap)'
  }

  Write-Host '[1/4] Measuring top-level directories (rule-scoped paths only)...'
  # Resolve scan roots from rule targets only — never use $env:USERPROFILE / $env:ProgramData / $env:ProgramFiles
  # as generic recursive roots. The depth/file/directory budgets are applied inside ParallelScanner.
  $ruleResolvableRoots = New-Object System.Collections.Generic.HashSet[string]
  foreach ($t in @($allTargets)) {
    if (-not $t.enabled) { continue }
    foreach ($p in @($t.paths)) {
      $ep = Expand-EnvPath ([string]$p)
      if ($ep -and (Test-Path -LiteralPath $ep -ErrorAction SilentlyContinue)) {
        [void]$ruleResolvableRoots.Add($ep)
      }
    }
  }
  $roots = @($ruleResolvableRoots) | Sort-Object
  if ($roots.Count -eq 0) {
    # RED LINE: never fall back to broad roots (USERPROFILE / ProgramData / Program Files).
    # Use only narrow, regenerable cache/temp subdirectories as last-resort roots.
    $fallbackCandidates = @(
      (Expand-EnvPath '%TEMP%'),
      (Expand-EnvPath '%LOCALAPPDATA%\Temp'),
      (Expand-EnvPath '%LOCALAPPDATA%\Microsoft\Windows\INetCache'),
      (Expand-EnvPath '%LOCALAPPDATA%\CrashDumps')
    )
    $roots = @($fallbackCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
    Write-Host '      [WARN] No rule-resolved paths exist; falling back to narrow temp/cache roots only (never broad user/system roots).' -ForegroundColor Yellow
  }
  Write-Host ("      Resolved {0} scan roots from rule targets." -f $roots.Count)
  $summary.scanPath = 'dotnet-parallel'
  $topDirs = @()
  $largeFiles = New-Object System.Collections.Generic.List[object]
  $dupCandidates = New-Object System.Collections.Generic.List[object]
  $mftOut = Join-Path $env:TEMP ("wincc_mft_{0}.tsv" -f ([guid]::NewGuid().ToString('N')))
  $mftUsed = $false
  
  # Get scan mode configuration for this scan
  $scanModeCfg = Get-ScanModeConfig $ScanMode
  $maxDepth = $scanModeCfg.maxDepth
  $followJunctions = $scanModeCfg.followJunctions
  $skipBlacklist = $scanModeCfg.skipBlacklist
  
  # NTFS MFT direct read fast path (admin + NTFS + not disabled); falls back silently
  if (-not $NoMft -and (Test-IsAdmin)) {
    try {
      $mftCs = Join-Path (Split-Path -Parent $PSCommandPath) 'MftScanner.cs'
      if (Test-Path -LiteralPath $mftCs) {
        Add-Type -TypeDefinition (Get-Content -LiteralPath $mftCs -Raw -Encoding UTF8) -Language CSharp -ErrorAction Stop
        $swMft = [System.Diagnostics.Stopwatch]::StartNew()
        $mftInfo = [MftScanner]::Scan($driveLetter, $mftOut, [string[]]$roots, [int64]1GB, [int64]100MB, 2000, [string[]]$blacklistPatterns)
        $swMft.Stop()
        $summary.scanPath = 'ntfs-mft'
        $summary.mftMs = [int]$swMft.Elapsed.TotalMilliseconds
        $summary.mftSummary = $mftInfo
        $mftUsed = $true
        Write-Host ("      MFT direct read: {0} ({1:N1}s)" -f $mftInfo, $swMft.Elapsed.TotalSeconds)
      }
    } catch {
      Write-Host ("      MFT scan unavailable ({0}); using .NET traversal" -f $_.Exception.Message)
      $mftUsed = $false
    }
  }
  if ($mftUsed) {
    foreach ($line in @(Get-Content -LiteralPath $mftOut -Encoding UTF8)) {
      $p = $line -split "`t"
      if ($p.Count -lt 3) { continue }
      $tag = $p[0]; $path = $p[1]; $bytes = [int64]$p[2]
      if ($tag -eq 'D' -and $bytes -gt 0) { $topDirs += [pscustomobject]@{ path = $path; sizeGB = Get-BytesToGB $bytes } }
      elseif ($tag -eq 'F') { $largeFiles.Add([pscustomobject]@{ path = $path; sizeGB = Get-BytesToGB $bytes }) }
      elseif ($tag -eq 'C') { $dupCandidates.Add(@{ path = $path; bytes = $bytes }) }
    }
    Remove-Item -LiteralPath $mftOut -Force -ErrorAction SilentlyContinue
    $topDirs = @($topDirs | Sort-Object sizeGB -Descending | Select-Object -First 20)
    $largeFiles = @($largeFiles | Sort-Object sizeGB -Descending | Select-Object -First 20)
  } else {
    $dirJobs = New-Object System.Collections.Generic.List[object]
    $idx = 0
    foreach ($r in $roots) {
      # Apply scan mode depth limit
      $depth = 0
      $stack = New-Object System.Collections.Generic.Stack[object]
      $stack.Push(@{ Path = $r; Depth = 0 })
      while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $currentPath = $item.Path
        $currentDepth = $item.Depth
        
        if ($maxDepth -ge 0 -and $currentDepth -ge $maxDepth) { continue }
        
        foreach ($child in @(Get-ChildItem -LiteralPath $currentPath -Directory -Force -ErrorAction SilentlyContinue)) {
          if (-not $followJunctions -and (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { continue }
          
          # RED LINE: engine guards always checked; user blacklist per skipBlacklist
          if (Test-GuardrailBlocked $child.FullName) { continue }
          if ($skipBlacklist -and $blacklistPatterns.Count -gt 0) {
            if (Test-PathAgainstBlacklist $child.FullName $blacklistPatterns) { continue }
          }
          
          $dirJobs.Add([pscustomobject]@{ Key = $child.FullName; Path = $child.FullName; Glob = '' })
          $idx++
          $stack.Push(@{ Path = $child.FullName; Depth = $currentDepth + 1 })
        }
      }
    }
    $dirResults = Invoke-MeasureParallel -MeasureJobs $dirJobs -ThreadCount $threads -ScanMode $ScanMode
    foreach ($k in $dirResults.Keys) {
      $v = $dirResults[$k]
      if ($v -and $v.bytes -gt 0) { $topDirs += [pscustomobject]@{ path = $k; sizeGB = Get-BytesToGB $v.bytes } }
    }
    $topDirs = @($topDirs | Sort-Object sizeGB -Descending | Select-Object -First 20)
  }

  if (-not $mftUsed) {
    Write-Host '[2/4] Finding large files (>= 1 GB) and duplicate candidates (>= 100 MB), single pass...'
    # file-count budget mirrors ParallelScanner presets (0 = unlimited)
    $lfMaxFiles = switch ($ScanMode) { 'fast' { 500000 } 'deep' { 0 } default { 2000000 } }
    $lfFileCount = 0
    $lfBudgetHit = $false
    # rule-scoped roots only — never traverse USERPROFILE/ProgramData as generic roots
    foreach ($root in $roots) {
      if ($lfBudgetHit) { break }
      if (-not (Test-Path -LiteralPath $root)) { continue }
      $stack = New-Object System.Collections.Generic.Stack[object]
      $stack.Push(@{ Path = $root; Depth = 0 })
      while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $dir = $item.Path
        $currentDepth = $item.Depth
        
        if ($maxDepth -ge 0 -and $currentDepth -ge $maxDepth) { continue }
        
        try {
          $di = New-Object System.IO.DirectoryInfo($dir)
          foreach ($fi in $di.EnumerateFiles()) {
            $lfFileCount++
            if ($lfMaxFiles -gt 0 -and $lfFileCount -ge $lfMaxFiles) { $lfBudgetHit = $true; break }
            # single-pass collection: large files (>=1GB) AND duplicate candidates (>=100MB)
            if ($fi.Length -ge 1GB) { $largeFiles.Add([pscustomobject]@{ path = $fi.FullName; sizeGB = Get-BytesToGB $fi.Length }) }
            if ($fi.Length -ge 100MB) { $dupCandidates.Add(@{ path = $fi.FullName; bytes = [int64]$fi.Length }) }
          }
          if ($lfBudgetHit) { break }
          foreach ($sd in $di.EnumerateDirectories()) {
            if (-not $followJunctions -and (($sd.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { continue }
            
            # RED LINE: engine guards always checked; user blacklist per skipBlacklist
            if (Test-GuardrailBlocked $sd.FullName) { continue }
            if ($skipBlacklist -and $blacklistPatterns.Count -gt 0) {
              if (Test-PathAgainstBlacklist $sd.FullName $blacklistPatterns) { continue }
            }
            
            $stack.Push(@{ Path = $sd.FullName; Depth = $currentDepth + 1 })
          }
        } catch {}
      }
    }
    if ($lfBudgetHit) { Write-Host ("      [WARN] Large-file scan hit {0} file budget ({1}); results may be partial. Use -ScanMode deep for full coverage." -f $ScanMode, $lfMaxFiles) -ForegroundColor Yellow }
    $largeFiles = @($largeFiles | Sort-Object sizeGB -Descending | Select-Object -First 20)
  } else {
    Write-Host '[2/4] Large files + duplicate candidates already collected from MFT pass.'
  }

  Write-Host '[3/4] Duplicate detection (size -> 64KB partial hash -> full MD5, cascade)...'
  $bySize = @{}
  foreach ($c in $dupCandidates) {
    if (-not $bySize.ContainsKey($c.bytes)) { $bySize[$c.bytes] = New-Object System.Collections.Generic.List[object] }
    $bySize[$c.bytes].Add($c)
  }
  $hashJobs = New-Object System.Collections.Generic.List[object]
  $hashScript = @'
param([string]$FilePath, [int64]$Length)
try {
  $fs = [System.IO.File]::OpenRead($FilePath)
  try {
    $bufSize = [int]([math]::Min(65536, $Length))
    $buf = New-Object byte[] $bufSize
    [void]$fs.Read($buf, 0, $bufSize)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $h1 = ($md5.ComputeHash($buf) | ForEach-Object { $_.ToString('x2') }) -join ''
    if ($Length -le 65536) { return @{ p = $h1; f = $h1 } }
    $fs.Position = [math]::Max(0, $Length - 65536)
    $n = $fs.Read($buf, 0, $bufSize)
    $tail = New-Object byte[] $n
    [Array]::Copy($buf, $tail, $n)
    $h2 = ($md5.ComputeHash($tail) | ForEach-Object { $_.ToString('x2') }) -join ''
    return @{ p = $h1 + $h2; f = '' }
  } finally { $fs.Dispose() }
} catch { return $null }
'@
  $sizeGroups = @($bySize.Values | Where-Object { $_.Count -ge 2 })
  $needFull = @()
  $fullFiles = New-Object System.Collections.Generic.List[string]
  $partialMap = @{}
  $pool2 = [runspacefactory]::CreateRunspacePool(1, $threads, [initialsessionstate]::CreateDefault(), $Host)
  $pool2.Open()
  $rsJobs = New-Object System.Collections.Generic.List[object]
  foreach ($g in $sizeGroups) {
    foreach ($c in $g) {
      $ps = [powershell]::Create()
      $ps.RunspacePool = $pool2
      [void]$ps.AddScript($hashScript).AddArgument($c.path).AddArgument($c.bytes)
      $rsJobs.Add([pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke(); Path = $c.path; Bytes = $c.bytes })
    }
  }
  foreach ($j in $rsJobs) {
    try {
      $r = $j.PS.EndInvoke($j.Handle) | Select-Object -Last 1
      if ($r) {
        if ($r.f) { $partialMap[$j.Path] = @{ p = $r.p; f = $r.f; bytes = $j.Bytes } }
        else { $partialMap[$j.Path] = @{ p = $r.p; f = ''; bytes = $j.Bytes }; $fullFiles.Add($j.Path) }
      }
    } catch {}
    $j.PS.Dispose()
  }
  $pool2.Close()
  $pool2.Dispose()
  # full hash only for identical partials
  $byPartial = @{}
  foreach ($k in $partialMap.Keys) {
    $pk = $partialMap[$k].p + '|' + $partialMap[$k].bytes
    if (-not $byPartial.ContainsKey($pk)) { $byPartial[$pk] = New-Object System.Collections.Generic.List[string] }
    $byPartial[$pk].Add($k)
  }
  $finalGroups = @()
  # GPU-aware thread boost: hashing is CPU+IO mixed; more threads overlap IO better.
  # When a discrete GPU is present we allow 2x logical cores (system is typically less loaded).
  $hashThreads = $threads
  if ($gpuAvailable) { $hashThreads = [math]::Min($threads * 2, 64) }
  # Full-hash phase in PARALLEL (streaming 1MB buffer) instead of serial per-group loops
  $fullHashScript = @'
param([string]$FilePath)
try {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $fs = [System.IO.File]::OpenRead($FilePath)
  try {
    $buf = New-Object byte[] (1048576)
    while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) { [void]$md5.TransformBlock($buf, 0, $n, $null, 0) }
    [void]$md5.TransformFinalBlock($buf, 0, 0)
    return ($md5.Hash | ForEach-Object { $_.ToString('x2') }) -join ''
  } finally { $fs.Dispose() }
} catch { return $null }
'@
  $needFullPaths = New-Object System.Collections.Generic.List[string]
  foreach ($gk in $byPartial.Keys) {
    $g = $byPartial[$gk]
    if ($g.Count -lt 2) { continue }
    if ($partialMap[$g[0]].bytes -le 65536) { continue }
    foreach ($f in $g) { $needFullPaths.Add($f) }
  }
  $fullHashResults = @{}
  if ($needFullPaths.Count -gt 0) {
    Write-Host ("      full-hash phase: {0} files, {1} parallel streams" -f $needFullPaths.Count, $hashThreads)
    $pool3 = [runspacefactory]::CreateRunspacePool(1, $hashThreads, [initialsessionstate]::CreateDefault(), $Host)
    $pool3.Open()
    $fhJobs = New-Object System.Collections.Generic.List[object]
    foreach ($fp in $needFullPaths) {
      $ps = [powershell]::Create()
      $ps.RunspacePool = $pool3
      [void]$ps.AddScript($fullHashScript).AddArgument($fp)
      $fhJobs.Add([pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke(); Path = $fp })
    }
    foreach ($j in $fhJobs) {
      try { $fullHashResults[$j.Path] = ($j.PS.EndInvoke($j.Handle) | Select-Object -Last 1) } catch {}
      $j.PS.Dispose()
    }
    $pool3.Close()
    $pool3.Dispose()
  }
  foreach ($gk in $byPartial.Keys) {
    $g = $byPartial[$gk]
    if ($g.Count -lt 2) { continue }
    $bytes = $partialMap[$g[0]].bytes
    if ($bytes -le 65536) {
      $finalGroups += @{ bytes = $bytes; files = @($g) }
      continue
    }
    $byFull = @{}
    foreach ($f in $g) {
      $h = $fullHashResults[$f]
      if (-not $h) { continue }
      if (-not $byFull.ContainsKey($h)) { $byFull[$h] = New-Object System.Collections.Generic.List[string] }
      $byFull[$h].Add($f)
    }
    foreach ($h in $byFull.Keys) {
      if ($byFull[$h].Count -ge 2) { $finalGroups += @{ bytes = $bytes; files = @($byFull[$h]) } }
    }
  }
  $dupGroups = @()
  foreach ($g in $finalGroups) {
    $dupGroups += [pscustomobject]@{
      fileCount = $g.files.Count
      sizeGBEach = Get-BytesToGB $g.bytes
      wastedGB = Get-BytesToGB ($g.bytes * ($g.files.Count - 1))
      files = @($g.files | Select-Object -First 8)
    }
  }
  $dupGroups = @($dupGroups | Sort-Object wastedGB -Descending | Select-Object -First 10)

  Write-Host '[4/4] Magic-byte verification (misnamed files), system state and suggestions...'
  # Czkawka-style: files whose extension lies about content (e.g. .log that is really an EXE)
  $misnamed = New-Object System.Collections.Generic.List[object]
  $checkSet = @($dupCandidates | Select-Object -First 300) + @($largeFiles | Select-Object -First 50)
  foreach ($c in $checkSet) {
    $p = if ($c -is [System.Collections.Hashtable]) { $c.path } else { $c.path }
    if (-not $p) { continue }
    $ext = [System.IO.Path]::GetExtension($p).ToLowerInvariant()
    if ($ext -notin @('.log', '.tmp', '.old', '.bak', '.dmp', '.txt')) { continue }
    $mt = Get-MagicType $p
    if ($mt) { $misnamed.Add([pscustomobject]@{ path = $p; ext = $ext; realType = $mt }) }
  }
  $summary.misnamedFiles = @($misnamed | Select-Object -First 20)
  $ssOn = Get-StorageSenseState
  $suggestions = New-Object System.Collections.Generic.List[string]
  $suggestions.Add('Run Storage Sense or enable it (Settings > System > Storage) - currently ' + $(if ($ssOn) { 'ON' } else { 'OFF' }) + '.')
  $suggestions.Add('DISM component cleanup (run manually as admin if desired): dism /online /cleanup-image /startcomponentcleanup')
  $suggestions.Add('cleanmgr /sageset + /sagerun for classic Windows disk cleanup.')
  if (-not $ssOn) { $suggestions.Add('Storage Sense is OFF; enabling it reduces cache rebound automatically.') }
  $suggestions.Add('For large install trees (TeX Live, big IDEs), prefer migrate/junction over deletion.')
  $suggestions.Add('Uninstall unused apps via Settings > Apps (agent will never uninstall without explicit request).')

  $summary.topDirs = $topDirs
  $summary.largeFiles = $largeFiles
  $summary.duplicateGroups = $dupGroups
  $summary.storageSenseEnabled = $ssOn
  $summary.suggestions = $suggestions
  $freeAfter = Get-DriveFreeGB $driveLetter
  $summary.drive.freeGB_after = $freeAfter

  # Scan Rating (R5-2)
  $totalFreedGB = ($topDirs | Measure-Object sizeGB -Sum).Sum
  $rating = Get-ScanRating -TotalFreedGB $totalFreedGB -SafeItemsCleaned 0 -CautionItemsCleaned 0 -DangerousItemsCleaned 0 -ItemsSkipped 0 -ItemsErrors 0 -BlacklistHits $blacklistSkipped
  $summary.scanRating = $rating
  Write-Host ("Scan Rating: {0} (Score: {1}/100) - {2}" -f $rating.grade, $rating.score, $rating.status)

  Write-Host ''
  Write-Host '---------- TOP DIRECTORIES ----------'
  foreach ($d in $topDirs) { Write-Host ("  {0,8:N2} GB  {1}" -f $d.sizeGB, $d.path) }
  Write-Host '---------- LARGE FILES (>=1GB) ----------'
  foreach ($f in $largeFiles) { Write-Host ("  {0,8:N2} GB  {1}" -f $f.sizeGB, $f.path) }
  Write-Host '---------- DUPLICATE GROUPS (>=100MB files) ----------'
  foreach ($g in $dupGroups) { Write-Host ("  wasted {0,7:N2} GB  ({1} files x {2:N2} GB)" -f $g.wastedGB, $g.fileCount, $g.sizeGBEach) }
  Write-Host ("Hash path used: {0}" -f $summary.hashPath)

  $logPathFinal = if ($LogPath) { $LogPath } else { Get-DefaultLogPath }
  $summary.logPath = $logPathFinal
  Write-SummaryAndLog $summary $logPathFinal
  exit 0
}

# ------------------------------------------------------------
# Target selection (Scan + Clean) + whitelist enforcement
# ------------------------------------------------------------
$selected = New-Object System.Collections.Generic.List[object]
$knownIds = @{}
foreach ($t in $allTargets) { $knownIds[[string]$t.id] = $true }
foreach ($t in $allTargets) {
  if ($tierSet.Count -gt 0 -and -not $tierSet.ContainsKey(([string]$t.tier).ToLower())) { continue }
  if ($idFilter -and -not $idFilter.ContainsKey([string]$t.id)) { continue }
  if ($Mode -eq 'Clean' -and -not $t.enabled) { continue }
  $selected.Add($t)
}
Write-Host ("Selected: {0} targets (tiers={1}, policy={2})" -f $selected.Count, $Tiers, $Policy)
if ($Policy -eq 'conservative') {
  # strategy layer: ignore community/curated merged enablement, builtin whitelist only
  $before = $selected.Count
  $selected = New-Object System.Collections.Generic.List[object]
  foreach ($t in $allTargets) {
    if ($t.origin -eq 'c_cleaner_plus') { continue }
    if ($tierSet.Count -gt 0 -and -not $tierSet.ContainsKey(([string]$t.tier).ToLower())) { continue }
    if ($idFilter -and -not $idFilter.ContainsKey([string]$t.id)) { continue }
    if ($Mode -eq 'Clean' -and -not $t.enabled) { continue }
    $selected.Add($t)
  }
  Write-Host ("Policy conservative: {0} -> {1} targets (community rules excluded)" -f $before, $selected.Count)
}
if ($Mode -eq 'Scan' -and $selected.Count -eq 0) { Write-Host '[WARN] No targets match the current filter.' }

# whitelist guard: -Ids referencing unknown ids are rejected loudly (never silently ignored)
$unknownIdItems = @()
if ($idFilter) {
  foreach ($want in $idFilter.Keys) {
    if (-not $knownIds.ContainsKey($want)) {
      $unknownIdItems += [pscustomobject][ordered]@{
        id = $want; name = "(unknown id '$want')"; tier = 'unknown'; origin = 'none'
        enabled = $false; exists = $false; requiresAdmin = $false
        sizeGB_before = 0; sizeGB_after = 0; freedGB = 0
        status = 'error'; message = 'blocked: id is not in the whitelist (builtin or merged rules); refusing to clean unknown paths'
        paths = @(); stopProcesses = @(); stopServices = @(); preCommands = @(); type = 'none'
      }
    }
  }
  if ($unknownIdItems.Count -gt 0) {
    Write-Host ("[GUARD] {0} unknown id(s) rejected: {1}" -f $unknownIdItems.Count, (($unknownIdItems | ForEach-Object { $_.id }) -join ',')) -ForegroundColor Red
  }
}

# ------------------------------------------------------------
# Plan gate (approval fence): Clean (non-DryRun) requires a recent Scan whose
# results were presented to the user for approval. Enforced at ENGINE level.
# ------------------------------------------------------------
if ($Mode -eq 'Clean' -and -not $DryRun) {
  $planPath = if ($PlanFile) { $PlanFile } else { Join-Path $configDir 'last-scan.json' }
  $planOk = $false
  $planMsg = ''
  try {
    if (Test-Path -LiteralPath $planPath) {
      $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $ageMin = ((Get-Date) - [datetime]$plan.time).TotalMinutes
      if ($ageMin -le 30) { $planOk = $true }
      else { $planMsg = ("plan stale: scan was {0:N0} minutes ago (>30); rescan and re-confirm with the user" -f $ageMin) }
    } else { $planMsg = "no scan plan found at '$planPath'" }
  } catch { $planMsg = 'plan file unreadable: ' + $_.Exception.Message }
  if (-not $planOk) {
    Write-Host '[GATE] CLEAN BLOCKED: a fresh Scan (with user-approved selection) must precede Clean.' -ForegroundColor Red
    Write-Host ("       reason: {0}" -f $planMsg)
    Write-Host '       run: -Mode Scan ... present the list, get approval, then Clean within 30 minutes.'
    Write-Host '       (DryRun is exempt; automation may pass -PlanFile <path> for pre-approved plans.)'
    $gateSummary = New-BaseSummary 'Clean' $driveLetter (Get-DriveFreeGB $driveLetter)
    $gateSummary.items = @([ordered]@{
      id = '(plan-gate)'; name = 'approval fence'; tier = 'safe'; origin = 'builtin'
      enabled = $false; exists = $false; requiresAdmin = $false
      sizeGB_before = 0; sizeGB_after = 0; freedGB = 0
      status = 'error'; message = 'blocked: no user-approved scan plan within 30 minutes (scan-before-delete is engine-enforced)'
    })
    $gateSummary.totals.errors = 1
    Write-SummaryAndLog $gateSummary (Get-DefaultLogPath)
    exit 4
  }
}

# ------------------------------------------------------------
# Elevation (Clean mode only, before any work)
# ------------------------------------------------------------
if ($Mode -eq 'Clean' -and -not $DryRun) {
  $needAdminSelected = @($selected | Where-Object { $_.requiresAdmin -eq $true }).Count -gt 0
  if ($Elevate -and $needAdminSelected -and -not (Test-IsAdmin)) {
    Write-Host '[INFO] Admin required for selected targets. Requesting UAC elevation...' -ForegroundColor Yellow
    $rf = Join-Path $env:TEMP ("wincc_result_{0}.json" -f ([guid]::NewGuid().ToString('N')))
    $argList = @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', ('"{0}"' -f $PSCommandPath),
      '-Mode', $Mode,
      '-Config', ('"{0}"' -f $configPath),
      '-Tiers', ('"{0}"' -f $Tiers),
      '-ResultFile', ('"{0}"' -f $rf)
    )
    if ($Ids) { $argList += @('-Ids', ('"{0}"' -f $Ids)) }
    if ($ConfirmIds) { $argList += @('-ConfirmIds', ('"{0}"' -f $ConfirmIds)) }
    if ($LogPath) { $argList += @('-LogPath', ('"{0}"' -f $LogPath)) }
    if ($MaxThreads -gt 0) { $argList += @('-MaxThreads', $MaxThreads) }
    if ($AllowStop) { $argList += '-AllowStop' }
    if ($BackupDangerous) { $argList += '-BackupDangerous' }
    if ($TrimWorkingSet) { $argList += '-TrimWorkingSet' }
    if ($Policy -ne 'standard') { $argList += @('-Policy', $Policy) }
    if ($NoCache) { $argList += '-NoCache' }
    if ($RecoveryMode -ne 'permanent') { $argList += @('-RecoveryMode', $RecoveryMode) }
    if ($RuleSets -ne 'minimal') { $argList += @('-RuleSets', ('"{0}"' -f $RuleSets)) }
    if ($HotMinutes -ne 30) { $argList += @('-HotMinutes', $HotMinutes) }
    if ($PlanFile) { $argList += @('-PlanFile', ('"{0}"' -f $PlanFile)) }
    if ($CCPDirs) { $argList += @('-CCPDirs', ('"{0}"' -f $CCPDirs)) }
    $elevated = $false
    try {
      $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList ($argList -join ' ') -Wait -PassThru -ErrorAction Stop
      $elevated = $true
      if (Test-Path -LiteralPath $rf) {
        $childJson = Get-Content -LiteralPath $rf -Raw
        Write-Host ''
        Write-Host '---------- JSON_SUMMARY_BEGIN ----------'
        Write-Host $childJson
        Write-Host '---------- JSON_SUMMARY_END ----------'
        Remove-Item -LiteralPath $rf -Force -ErrorAction SilentlyContinue
        exit $proc.ExitCode
      } else {
        Write-Host '[WARN] Elevated run finished but produced no result file. Falling back to non-admin clean.'
      }
    } catch {
      Write-Host '[WARN] UAC declined or elevation failed. Continuing without admin (admin targets will be reported as need-admin).' -ForegroundColor Yellow
    }
  }
}

# ------------------------------------------------------------
# Size cache (smart-cache technique from WindowsClear, Rust/MIT):
# path -> {bytes, dirMtime, cachedAt}; valid while mtime unchanged and TTL fresh.
# Second scan in the same session returns instantly for unchanged trees.
# ------------------------------------------------------------

$Script:CacheTtlSeconds = 900
$Script:SizeCachePath = ''
$Script:SizeCache = $null
function Initialize-SizeCache([string]$CachePath) {
  $Script:SizeCachePath = $CachePath
  if ($NoCache) { $Script:SizeCache = $null; return }
  try {
    if (Test-Path -LiteralPath $CachePath) {
      $Script:SizeCache = Get-Content -LiteralPath $CachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
  } catch { $Script:SizeCache = $null }
}
function Test-SizeCacheHit([string]$Path) {
  # returns cached bytes ([long]) or $null
  if ($null -eq $Script:SizeCache -or $NoCache) { return $null }
  try {
    $entries = $Script:SizeCache.entries
    if (-not $entries) { return $null }
    $prop = $entries.PSObject.Properties[$Path]
    if (-not $prop) { return $null }
    $e = $prop.Value
    $age = [DateTime]::UtcNow.ToFileTime() - [long]$e.t
    if ($age -gt ($Script:CacheTtlSeconds * [TimeSpan]::TicksPerSecond)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    if ([long]$item.LastWriteTimeUtc.ToFileTime() -ne [long]$e.m) { return $null }
    return [long]$e.b
  } catch { return $null }
}
function Save-SizeCache([hashtable]$PathKeyMap, [hashtable]$Results) {
  if ($NoCache -or -not $Script:SizeCachePath) { return }
  try {
    $entries = @{}
    if ($Script:SizeCache -and $Script:SizeCache.entries) {
      foreach ($p in $Script:SizeCache.entries.PSObject.Properties) { $entries[$p.Name] = $p.Value }
    }
    $nowFt = [DateTime]::UtcNow.ToFileTime()
    foreach ($path in $PathKeyMap.Keys) {
      $k = $PathKeyMap[$path]
      $r = $Results[$k]
      if (-not $r -or $r.bytes -lt 0) { continue }
      $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
      if (-not $item) { continue }
      $entries[$path] = @{ b = [long]$r.bytes; m = [long]$item.LastWriteTimeUtc.ToFileTime(); t = $nowFt }
    }
    $out = @{ version = 1; entries = $entries }
    [System.IO.File]::WriteAllText($Script:SizeCachePath, ($out | ConvertTo-Json -Depth 4 -Compress), (New-Object System.Text.UTF8Encoding($true)))
  } catch {}
}

# ------------------------------------------------------------
# Measure phase (two-level parallel + wildcard resolution + small-task batching)
# ------------------------------------------------------------
$freeBefore = Get-DriveFreeGB $driveLetter
Initialize-SizeCache (Join-Path $configDir 'scan-cache.json')
$bigItems = New-Object System.Collections.Generic.List[object]    # 1:1 jobs (potentially heavy dirs)
$smallItems = New-Object System.Collections.Generic.List[object]  # batched 16/job (files/globs/resolved)
$cacheHits = @{}     # key -> @{bytes;denied} served from size cache
$pathKeyMap = @{}    # concrete path -> result key (for cache persistence)
$targetPathMap = @{}
$pathExists = @{}
$rootFileBytes = @{}   # aggKey -> bytes of files directly in the root dir
$aggGroups = @{}       # aggKey -> list of sub-task keys (subdirs / file itself)
$wildcardChars = [char[]]@('*','?')
foreach ($t in $selected) {
  $paths = Get-TargetPathsExpanded $t
  $targetPathMap[$t.id] = $paths
  foreach ($p in $paths) {
    if (-not $pathExists.ContainsKey($p)) {
      if ($p.IndexOfAny($wildcardChars) -ge 0) {
        # wildcard path (winapp2-style): cheap prefix-dir check before expensive resolution
        $wc = $p.IndexOfAny($wildcardChars)
        $prefix = $p.Substring(0, $wc)
        $li = $prefix.LastIndexOf('\')
        $prefixDir = if ($li -gt 0) { $prefix.Substring(0, $li) } else { $prefix }
        $pathExists[$p] = [bool]($prefixDir -and (Test-Path -LiteralPath $prefixDir))
      } else {
        $pathExists[$p] = ([System.IO.Directory]::Exists($p) -or [System.IO.File]::Exists($p))
      }
    }
    if (-not $pathExists[$p]) { continue }
    $aggKey = $t.id + '|' + $p
    if (-not $aggGroups.ContainsKey($aggKey)) { $aggGroups[$aggKey] = New-Object System.Collections.Generic.List[string] }
    # wildcard path: resolve pattern to concrete items (small tasks)
    if ($p.IndexOfAny($wildcardChars) -ge 0) {
      $resolved = @(Get-Item -Path $p -Force -ErrorAction SilentlyContinue)
      if ($resolved.Count -eq 0) { $pathExists[$p] = $false; continue }
      foreach ($r in $resolved) {
        $k = $aggKey + '##' + $r.FullName
        $pathKeyMap[$r.FullName] = $k
        $cb = Test-SizeCacheHit $r.FullName
        if ($null -ne $cb) { $cacheHits[$k] = @{ bytes = $cb; denied = $false } }
        else { $smallItems.Add(@{ k = $k; p = $r.FullName; g = '' }) }
        $aggGroups[$aggKey].Add($k)
      }
      continue
    }
    # plain file or glob dir: single small task (glob applies to root-level files only)
    if ([System.IO.File]::Exists($p) -or [string]$t.glob) {
      $pathKeyMap[$p] = $aggKey
      $cb = Test-SizeCacheHit $p
      if ($null -ne $cb) { $cacheHits[$aggKey] = @{ bytes = $cb; denied = $false } }
      else { $smallItems.Add(@{ k = $aggKey; p = $p; g = [string]$t.glob }) }
      $aggGroups[$aggKey].Add($aggKey)
      continue
    }
    # directory: split into root-files (fast, inline) + one BIG task per first-level subdir
    try {
      $di = New-Object System.IO.DirectoryInfo($p)
      $rfb = [int64]0
      $deniedRoot = $false
      try { foreach ($fi in $di.EnumerateFiles()) { $rfb += $fi.Length } } catch { $deniedRoot = $true }
      $rootFileBytes[$aggKey] = $rfb
      if ($deniedRoot) { $rootFileBytes[$aggKey] = -1 }  # marker: root unreadable
      $subs = @()
      try { $subs = @($di.EnumerateDirectories()) } catch {}
      if ($subs.Count -eq 0) {
        if ($deniedRoot) {
          # root denied and we cannot list subdirs: fall back to whole-dir task
          $pathKeyMap[$p] = $aggKey
          $cb = Test-SizeCacheHit $p
          if ($null -ne $cb) { $cacheHits[$aggKey] = @{ bytes = $cb; denied = $false } }
          else { $bigItems.Add(@{ k = $aggKey; p = $p; g = '' }) }
          $aggGroups[$aggKey].Add($aggKey)
        }
      } else {
        foreach ($sd in $subs) {
          $k = $aggKey + '##' + $sd.FullName
          $pathKeyMap[$sd.FullName] = $k
          $cb = Test-SizeCacheHit $sd.FullName
          if ($null -ne $cb) { $cacheHits[$k] = @{ bytes = $cb; denied = $false } }
          else { $bigItems.Add(@{ k = $k; p = $sd.FullName; g = '' }) }
          $aggGroups[$aggKey].Add($k)
        }
      }
    } catch {
      $pathKeyMap[$p] = $aggKey
      $cb = Test-SizeCacheHit $p
      if ($null -ne $cb) { $cacheHits[$aggKey] = @{ bytes = $cb; denied = $false } }
      else { $bigItems.Add(@{ k = $aggKey; p = $p; g = '' }) }
      $aggGroups[$aggKey].Add($aggKey)
    }
  }
}
# assemble jobs: big tasks 1:1, small tasks batched 16 per job
$measureJobs = New-Object System.Collections.Generic.List[object]
foreach ($b in $bigItems) { $measureJobs.Add(@{ Items = @($b) }) }
for ($i = 0; $i -lt $smallItems.Count; $i += 16) {
  $chunk = @()
  for ($j = $i; $j -lt [math]::Min($i + 16, $smallItems.Count); $j++) { $chunk += $smallItems[$j] }
  $measureJobs.Add(@{ Items = $chunk })
}
$measureStart = Get-Date
$measureResults = Invoke-MeasureParallel -MeasureJobs $measureJobs -ThreadCount $threads -ScanMode $ScanMode
foreach ($ck in $cacheHits.Keys) {
  if (-not $measureResults.ContainsKey($ck)) { $measureResults[$ck] = $cacheHits[$ck] }
}
$measureMs = [int]((Get-Date) - $measureStart).TotalMilliseconds
Write-Host ("Measured: {0} jobs ({1} big + {2} small in {3} batches) in {4} ms, {5} threads, {6} size-cache hits" -f $measureJobs.Count, $bigItems.Count, $smallItems.Count, [math]::Ceiling($smallItems.Count / 16.0), $measureMs, $threads, $cacheHits.Count)

# build items
$items = New-Object System.Collections.Generic.List[object]
foreach ($t in $selected) {
  $paths = $targetPathMap[$t.id]
  $beforeBytes = [int64]0
  $exists = $false
  $deniedAny = $false
  foreach ($p in $paths) {
    $aggKey = $t.id + '|' + $p
    if ($pathExists[$p]) { $exists = $true }
    if ($rootFileBytes.ContainsKey($aggKey) -and $rootFileBytes[$aggKey] -ge 0) {
      $beforeBytes += [int64]$rootFileBytes[$aggKey]
    } elseif ($rootFileBytes.ContainsKey($aggKey) -and $rootFileBytes[$aggKey] -lt 0) {
      $deniedAny = $true
    }
    if ($aggGroups.ContainsKey($aggKey)) {
      foreach ($k in $aggGroups[$aggKey]) {
        $r = $measureResults[$k]
        if ($r) {
          if ($r.bytes -ge 0) { $beforeBytes += [int64]$r.bytes } else { $deniedAny = $true }
        } else { $deniedAny = $true }
      }
    }
  }
  $items.Add([pscustomobject][ordered]@{
    id = [string]$t.id
    name = [string]$t.name
    tier = ([string]$t.tier).ToLower()
    category = if ([string]$t.category) { [string]$t.category } else { if ($t.origin -in @('builtin','merged')) { 'builtin' } else { 'general' } }
    origin = [string]$t.origin
    enabled = [bool]$t.enabled
    exists = $exists
    requiresAdmin = [bool]$t.requiresAdmin
    sizeGB_before = Get-BytesToGB $beforeBytes
    sizeGB_after = Get-BytesToGB $beforeBytes
    freedGB = 0.0
    status = 'scanned'
    message = $(if ($deniedAny) { 'partial: some subdirs unreadable (size is an estimate)' } else { '' })
    paths = @($paths)
    stopProcesses = @($t.stopProcesses)
    stopServices = @($t.stopServices)
    preCommands = @($t.preCommands)
    type = [string]$t.type
  })
}
# rejected unknown ids surface as error items in every summary
foreach ($u in $unknownIdItems) { $items.Add($u) }

# ------------------------------------------------------------
# Mode: Scan (report only; NO deletion)
# ------------------------------------------------------------
if ($Mode -eq 'Scan') {
  $present = @($items | Where-Object { $_.exists -and $_.sizeGB_before -gt 0 } | Sort-Object sizeGB_before -Descending)
  Write-Host ''
  Write-Host '---------- SCAN REPORT (no deletion in Scan mode) ----------'
  $shown = 0
  foreach ($it in $present) {
    if ($shown -ge 60) { break }
    Write-Host ("  {0,8:N2} GB  [{1,-9}] {2,-24} {3}" -f $it.sizeGB_before, $it.tier, $it.id, $it.name)
    $shown++
  }
  $missingCount = @($items | Where-Object { -not $_.exists }).Count
  $disabledCount = @($items | Where-Object { -not $_.enabled }).Count
  Write-Host ("Existing with size: {0} | missing: {1} | disabled (listed for awareness): {2}" -f $present.Count, $missingCount, $disabledCount)
  Write-Host ("Scan wall time: {0} ms (parallel, {1} threads)" -f $measureMs, $threads)

  $freeAfter = Get-DriveFreeGB $driveLetter
  $summary = New-BaseSummary 'Scan' $driveLetter $freeBefore
  $summary.drive.freeGB_after = $freeAfter
  $summary.scanMs = $measureMs
  $summary.threads = $threads
  $summary.configPath = $configPath
  $summary.mergedConfigPath = $mergedPath
  $summary.overridesPath = $overridesPath
  # token-friendly output: only Top-N existing items; missing/disabled become aggregate counts
  $existingSorted = @($items | Where-Object { $_.exists } | Sort-Object sizeGB_before -Descending)
  $topItems = @($existingSorted | Select-Object -First $TopN | ForEach-Object {
    [ordered]@{
      id = $_.id; name = $_.name; tier = $_.tier; category = $_.category; origin = $_.origin
      enabled = $_.enabled; exists = $true; requiresAdmin = $_.requiresAdmin
      sizeGB_before = $_.sizeGB_before; sizeGB_after = $_.sizeGB_after; freedGB = $_.freedGB
      status = 'scanned'; message = $_.message
    }
  })
  $summary.items = $topItems
  $summary.counts = [ordered]@{
    shown = $topItems.Count
    existingTotal = $existingSorted.Count
    missing = @($items | Where-Object { -not $_.exists }).Count
    disabled = @($items | Where-Object { -not $_.enabled }).Count
    existingByTier = [ordered]@{
      safe = @($existingSorted | Where-Object { $_.tier -eq 'safe' }).Count
      caution = @($existingSorted | Where-Object { $_.tier -eq 'caution' }).Count
      dangerous = @($existingSorted | Where-Object { $_.tier -eq 'dangerous' }).Count
    }
    existingByCategory = Get-GroupCounts $existingSorted 'category'
    existingGB = [math]::Round((($existingSorted | Measure-Object sizeGB_before -Sum).Sum), 2)
  }
  $summary.note = "items limited to Top-$TopN existing targets; full detail in targets.merged.json / rerun with -TopN"
  $summary.cacheHits = $cacheHits.Count
  $summary.ruleSets = $RuleSets
  
  # Scan Rating (R5-2)：ItemsSkipped 仅计真实访问受限项（counts 无 skipped 字段，Scan 阶段为 0）
  $totalFreedGB = $summary.counts.existingGB
  $realSkipped = 0
  if ($summary.PSObject.Properties['items'] -or $summary.Contains('items')) {
    $realSkipped = @($summary.items | Where-Object { $_.status -eq 'skipped' -or $_.status -eq 'error' }).Count
  }
  $rating = Get-ScanRating -TotalFreedGB $totalFreedGB -SafeItemsCleaned $summary.counts.existingByTier.safe -CautionItemsCleaned $summary.counts.existingByTier.caution -DangerousItemsCleaned $summary.counts.existingByTier.dangerous -ItemsSkipped $realSkipped -ItemsErrors 0 -BlacklistHits $blacklistSkipped
  $summary.scanRating = $rating
  Write-Host ("Scan Rating: {0} (Score: {1}/100) - {2}" -f $rating.grade, $rating.score, $rating.status)
  
  $logPathFinal = if ($LogPath) { $LogPath } else { Get-DefaultLogPath }
  $summary.logPath = $logPathFinal
  Save-SizeCache $pathKeyMap $measureResults
  # write the approval plan: Clean (non-DryRun) is engine-gated on this file being <=30 min old
  try {
    $plan = [ordered]@{
      time = (Get-Date).ToString('o')
      mode = 'Scan'
      ruleSets = $RuleSets
      freeGB = $freeAfter
      existingTotal = $summary.counts.existingTotal
      existingGB = $summary.counts.existingGB
      topIds = @($existingSorted | Select-Object -First 20 | ForEach-Object { $_.id })
    }
    [System.IO.File]::WriteAllText((Join-Path $configDir 'last-scan.json'), ($plan | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($true)))
  } catch {}
  Write-SummaryAndLog $summary $logPathFinal
  exit 0
}

# ------------------------------------------------------------
# Mode: Clean
# ------------------------------------------------------------
$summary = New-BaseSummary 'Clean' $driveLetter $freeBefore
$summary.scanMs = $measureMs
$summary.threads = $threads
$cleanItems = New-Object System.Collections.Generic.List[object]
$stoppedServices = @{}
$procNamesToTrim = New-Object System.Collections.Generic.List[string]

# engine-level gate: caution/dangerous must be confirmed by id
foreach ($it in $items) {
  # whitelist-rejected unknown ids keep their error status (contract: unknown id -> status "error",
  # counted in totals.errors); never let downstream gates downgrade them to "skipped"
  if ($it.origin -eq 'none') {
    $it.status = 'error'
    $cleanItems.Add($it)
    continue
  }
  $tier = $it.tier
  $gateOk = $true
  $gateMsg = ''
  if ($tier -ne 'safe') {
    if ($confirmSet.Count -eq 0) {
      $gateOk = $false
      $gateMsg = 'blocked: ' + $tier + ' tier requires -ConfirmIds listing this id (two-phase confirmation protocol)'
    } elseif (-not $confirmSet.ContainsKey($it.id)) {
      $gateOk = $false
      $gateMsg = 'blocked: id not present in -ConfirmIds; user confirmation missing'
    }
  }
  if (-not $gateOk) {
    $it.status = 'skipped'
    $it.message = $gateMsg
    $cleanItems.Add($it)
    continue
  }

  # admin gate
  if ($it.requiresAdmin -and -not (Test-IsAdmin)) {
    $it.status = 'need-admin'
    $it.message = 'rerun elevated: powershell -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Mode Clean -Tiers ' + $Tiers + ' -Ids ' + $it.id + ' -ConfirmIds ' + $it.id + ' -Elevate'
    $cleanItems.Add($it)
    continue
  }

  if (-not $it.exists) {
    $it.status = 'skipped'
    $it.message = 'path missing (idempotent no-op)'
    $cleanItems.Add($it)
    continue
  }
  if ($it.sizeGB_before -le 0 -and $it.type -ne 'special') {
    $it.status = 'skipped'
    $it.message = 'already empty'
    $cleanItems.Add($it)
    continue
  }

  # process/service stop gate
  $runningProcs = @(Get-RunningProcessNames $it.stopProcesses)
  if ($runningProcs.Count -gt 0) {
    if (-not $AllowStop) {
      $it.status = 'locked'
      $it.message = 'processes running (' + ($runningProcs -join ',') + '); close them or rerun with -AllowStop after user confirmation'
      $cleanItems.Add($it)
      continue
    }
  }
  $runningSvcs = @()
  foreach ($svc in $it.stopServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running') { $runningSvcs += $svc }
  }

  if ($DryRun) {
    $it.status = 'dryrun'
    $it.message = ('would free ~{0:N2} GB (dry run, nothing deleted)' -f $it.sizeGB_before)
    $cleanItems.Add($it)
    continue
  }

  # stop processes/services (user already confirmed via -AllowStop)
  foreach ($pn in $runningProcs) {
    Get-Process -Name $pn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
  }
  foreach ($svc in $runningSvcs) {
    $stoppedServices[$svc] = $true
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
  }

  # backup dangerous before delete
  if ($BackupDangerous -and $it.tier -eq 'dangerous') {
    $bk = Backup-TargetPaths -Id $it.id -Paths $it.paths
    $it.message = ('backup: {0} ({1} paths copied)' -f $bk.path, $bk.copied)
  }

  # pre commands (app-native cleaners)
  foreach ($cmd in @($it.preCommands)) {
    if ([string]::IsNullOrWhiteSpace([string]$cmd)) { continue }
    Write-Host ("  -> pre: {0}" -f $cmd)
    $tool = ($cmd -split ' ')[0]
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      $it.message = ('pre command skipped (tool not found): {0}' -f $tool)
      continue
    }
    cmd /c $cmd 2>$null | Out-Null
  }

  # special targets (native-command handlers; never direct file deletion)
  if ($it.type -eq 'special' -and $it.id -eq 'pagefile-swapfile') {
    # ADVISORY-ONLY: never delete live page/swap files; explain and measure only
    $it.status = 'advisory'
    $it.message = 'advisory-only: pagefile.sys/swapfile.sys are NEVER deleted (would corrupt the running system). To reclaim: move pagefile to another drive via System Properties > Advanced > Virtual Memory (sysdm.cpl), or reduce size. Current combined size reported in sizeGB_before.'
    $it.freedGB = 0
    $it.sizeGB_after = $it.sizeGB_before
    $cleanItems.Add($it)
    continue
  }
  $hotTotal = 0
  $riskTotal = 0
  if ($it.type -eq 'special' -and $it.id -eq 'recycle-bin') {
    Clear-RecycleBin -DriveLetter $driveLetter -Force -ErrorAction SilentlyContinue
  } elseif ($it.type -eq 'special' -and $it.id -eq 'windows-old') {
    # native takeown/icacls sequence then delete (two-phase confirmed dangerous target)
    foreach ($p in $it.paths) {
      if (-not (Test-Path -LiteralPath $p)) { continue }
      Write-Host ("  -> takeown: {0}" -f $p)
      cmd /c "takeown /F `"$p`" /A /R /D Y" 2>$null | Out-Null
      cmd /c "icacls `"$p`" /grant Administrators:F /T /C /Q" 2>$null | Out-Null
      $res = Clear-OnePath -Path $p -GlobPattern '' -Mode $RecoveryMode -TargetId $it.id -TargetOrigin $it.origin -Tier $it.tier -HotMin $HotMinutes
      $hotTotal += $script:LastHotSkipped; $riskTotal += $script:LastRiskSkipped
      if ($res -eq 'locked') { $it.message = 'some files locked; reboot and retry, or use Disk Cleanup (cleanmgr)' }
    }
  } else {
    foreach ($p in $it.paths) {
      # wildcard path (winapp2-style): resolve pattern to concrete items first
      $concrete = @()
      if ($p.IndexOfAny($wildcardChars) -ge 0) {
        $concrete = @(Get-Item -Path $p -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
      } else { $concrete = @($p) }
      foreach ($cp in $concrete) {
        if (-not (Test-Path -LiteralPath $cp)) { continue }
        if ($it.type -eq 'special' -and $it.id -eq 'hiberfil') { continue }      # powercfg already removed it
        if ($it.type -eq 'special' -and $it.id -like 'win-event-logs*') { continue }  # wevtutil already cleared them
        # engine-level guardrail: refuse to delete protected system paths
        $np = ConvertTo-NormPath $cp
        if (Test-GuardrailBlocked $np) {
          $it.status = 'blocked-by-guardrail'
          $it.message = 'blocked: protected system path (WinSxS/Installer/NTUSER.DAT/pagefile etc.); this skill never deletes OS core files'
          Write-Host ("  [GUARD] blocked protected path: {0}" -f $cp) -ForegroundColor Red
          continue
        }
        $res = Clear-OnePath -Path $cp -GlobPattern $it.glob -Mode $RecoveryMode -TargetId $it.id -TargetOrigin $it.origin -Tier $it.tier -HotMin $HotMinutes
        $hotTotal += $script:LastHotSkipped; $riskTotal += $script:LastRiskSkipped
        if ($res -eq 'locked') {
          # Restart Manager (native rstrtmgr): report who holds the lock
          $lockers = Get-PathLockers $cp
          $it.message = 'some files locked (in use)' + $(if ($lockers) { ' by: ' + $lockers } else { '' }) + '; close them or reboot and retry'
        }
        if ($res -eq 'blocked') {
          $it.status = 'blocked-by-guardrail'
          $it.message = 'blocked: protected system path (defense-in-depth assert); this skill never deletes OS core files'
        }
      }
    }
  }
  if ($hotTotal -gt 0) {
    $it.message = ("fence: {0} item(s) skipped as hot (modified < {1} min = likely in active use); rerun later" -f $hotTotal, $HotMinutes) + $(if ($it.message) { '; ' + $it.message } else { '' })
  }
  if ($riskTotal -gt 0) {
    $it.message = ("fence: {0} item(s) skipped by risky-extension fence (exe/dll/sys/...) on non-builtin target" -f $riskTotal) + $(if ($it.message) { '; ' + $it.message } else { '' })
  }

  # restart services
  foreach ($svc in $runningSvcs) {
    Start-Service -Name $svc -ErrorAction SilentlyContinue
  }
  foreach ($pn in $it.stopProcesses) { $procNamesToTrim.Add($pn) }

  # measure after (wildcard-aware)
  $afterJobs = New-Object System.Collections.Generic.List[object]
  foreach ($p in $it.paths) {
    if ($p.IndexOfAny($wildcardChars) -ge 0) {
      foreach ($cp in @(Get-Item -Path $p -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })) {
        $afterJobs.Add(@{ Items = @(@{ k = $cp; p = $cp; g = [string]$it.glob }) })
      }
    } else {
      $afterJobs.Add(@{ Items = @(@{ k = $p; p = $p; g = [string]$it.glob }) })
    }
  }
  $afterRes = Invoke-MeasureParallel -MeasureJobs $afterJobs -ThreadCount 4 -ScanMode $ScanMode
  $afterBytes = [int64]0
  foreach ($p in $it.paths) {
    $r = $afterRes[$p]
    if ($r -and $r.bytes -gt 0) { $afterBytes += [int64]$r.bytes }
  }
  $it.sizeGB_after = Get-BytesToGB $afterBytes
  $freed = [math]::Round($it.sizeGB_before - $it.sizeGB_after, 2)
  if ($freed -lt 0) { $freed = 0 }
  $it.freedGB = $freed
  if ($it.sizeGB_after -le 0.01) { $it.status = 'cleaned' }
  elseif ($freed -gt 0) { $it.status = 'cleaned'; $it.message = ('partial: {0:N2} GB remains' -f $it.sizeGB_after) + $(if ($it.message) { '; ' + $it.message } else { '' }) }
  else { $it.status = 'locked'; if (-not $it.message) { $it.message = 'files in use; nothing freed' } }
  $cleanItems.Add($it)
}

# working set trim (optional, only user-confirmed process names)
$trimReport = @()
if ($TrimWorkingSet -and $procNamesToTrim.Count -gt 0) {
  $trimReport = Invoke-TrimWorkingSet -ProcNames ($procNamesToTrim | Select-Object -Unique)
}

$freeAfter = Get-DriveFreeGB $driveLetter
$summary.drive.freeGB_after = $freeAfter
$summary.items = @($cleanItems | ForEach-Object {
  [ordered]@{
    id = $_.id; name = $_.name; tier = $_.tier; category = $_.category; origin = $_.origin
    enabled = $_.enabled; exists = $_.exists; requiresAdmin = $_.requiresAdmin
    sizeGB_before = $_.sizeGB_before; sizeGB_after = $_.sizeGB_after; freedGB = $_.freedGB
    status = $_.status; message = $_.message
  }
})
$totalFreed = [math]::Round((($cleanItems | Measure-Object freedGB -Sum).Sum), 2)
if ($null -eq $totalFreed) { $totalFreed = 0 }
$summary.totals = [ordered]@{
  freedGB = $totalFreed
  cleaned = @($cleanItems | Where-Object { $_.status -eq 'cleaned' }).Count
  skipped = @($cleanItems | Where-Object { $_.status -eq 'skipped' -or $_.status -eq 'dryrun' }).Count
  needAdmin = @($cleanItems | Where-Object { $_.status -eq 'need-admin' }).Count
  errors = @($cleanItems | Where-Object { $_.status -eq 'error' }).Count
}
# Clean 模式统计块：供报告第4章与 JSON 契约使用（分级/分类维度）
$summary.counts = [ordered]@{
  selectedTotal = $cleanItems.Count
  existingTotal = @($cleanItems | Where-Object { $_.exists }).Count
  byTier = Get-GroupCounts $cleanItems 'tier'
  freedByTier = Get-GroupSumGB $cleanItems 'tier' 'freedGB'
  byCategory = Get-GroupCounts $cleanItems 'category'
  freedByCategory = Get-GroupSumGB $cleanItems 'category' 'freedGB'
}
if ($trimReport.Count -gt 0) { $summary.workingSetTrim = $trimReport }

Write-Host ''
Write-Host '---------- CLEAN DETAILS ----------'
foreach ($r in ($cleanItems | Sort-Object freedGB -Descending)) {
  if ($r.sizeGB_before -le 0 -and $r.freedGB -le 0 -and $r.status -eq 'skipped') { continue }
  Write-Host ("  [{0,-10}] {1,-26} {2,7:N2} -> {3,7:N2} GB  freed {4,7:N2}  ({5})" -f `
    $r.status, $r.id, $r.sizeGB_before, $r.sizeGB_after, $r.freedGB, $r.tier)
}
Write-Host ''
Write-Host ("Total freed (folder sum) : {0:N2} GB" -f $totalFreed) -ForegroundColor Green
Write-Host ("{0}: free before -> after  : {1:N2} -> {2:N2} GB" -f $driveLetter, $freeBefore, $freeAfter) -ForegroundColor Green

$logPathFinal = if ($LogPath) { $LogPath } else { Get-DefaultLogPath }
$summary.logPath = $logPathFinal
# persist quarantine manifest when recovery mode = quarantine
if ($RecoveryMode -eq 'quarantine' -and $Script:QuarantineManifest -and $Script:QuarantineManifest.items.Count -gt 0) {
  try {
    $qRoot = Split-Path -Parent ($Script:QuarantineManifest.items[0].quarantined)
    $mf = Join-Path $qRoot 'manifest.json'
    [System.IO.File]::WriteAllText($mf, ($Script:QuarantineManifest | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($true)))
    $summary.quarantine = @{
      root = $qRoot; manifest = $mf; items = $Script:QuarantineManifest.items.Count
      restore = 'powershell -File tools\restore-quarantine.ps1 -Manifest "' + $mf + '"'
    }
    Write-Host ("Quarantined {0} item(s) -> {1}" -f $Script:QuarantineManifest.items.Count, $qRoot) -ForegroundColor Cyan
    Write-Host ("Restore: powershell -File tools\restore-quarantine.ps1 -Manifest `"{0}`"" -f $mf) -ForegroundColor Cyan
  } catch {}
}
Save-SizeCache $pathKeyMap $measureResults
Write-SummaryAndLog $summary $logPathFinal

# exit codes: 0 ok; 2 some items need admin; 3 fatal
if (@($cleanItems | Where-Object { $_.status -eq 'need-admin' }).Count -gt 0) { exit 2 }
exit 0
