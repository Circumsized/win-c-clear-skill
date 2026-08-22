// ParallelScanner.cs — bounded async parallel directory scanner for win-c-clear-skill.
// C# 5 compatible (PowerShell 5.1 Add-Type uses the legacy compiler: no tuples,
// no switch expressions, no out-var, no digit separators, no string interpolation).
// Techniques:
//   Task.WhenAll + SemaphoreSlim(maxDop)          throttled concurrency
//   maxDepth / maxFiles / maxDirs                 budget guards
//   CancellationTokenSource(timeout)              overall deadline per run
//   ReparsePoint check                            skip junctions / symlinks / volumes
//   Per-root budget overrides                     "depth:files:dirs" strings
using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

public enum ScanMode { Fast, Standard, Deep }

public sealed class ParallelScanResult
{
    public long[]  Sizes;
    public int[]   Denied;
    public long[]  FilesScanned;
    public long[]  DirsScanned;
    public int[]   BudgetHit;
    public int[]   Cancelled;
}

public static class ParallelScanner
{
    // Scan-mode presets (mirrors scan-lists.json scanModes; 0 = unlimited).
    private static void GetPreset(ScanMode mode, out int depth, out int files, out int dirs, out int timeoutMs)
    {
        switch (mode)
        {
            case ScanMode.Fast:
                depth = 3; files = 500000; dirs = 50000; timeoutMs = 60000; break;
            case ScanMode.Deep:
                depth = 12; files = 0; dirs = 0; timeoutMs = 900000; break;
            default: // Standard
                depth = 6; files = 2000000; dirs = 200000; timeoutMs = 300000; break;
        }
    }

    public static ParallelScanResult Scan(string[] paths, string[] globs, int maxDop)
    {
        return Scan(paths, globs, maxDop, null, ScanMode.Standard);
    }

    public static ParallelScanResult Scan(string[] paths, string[] globs, int maxDop,
                                          ScanMode mode)
    {
        return Scan(paths, globs, maxDop, null, mode);
    }

    public static ParallelScanResult Scan(string[] paths, string[] globs, int maxDop,
                                          string[] budgets, ScanMode mode)
    {
        if (paths == null || paths.Length == 0)
        {
            var empty = new ParallelScanResult();
            empty.Sizes = new long[0]; empty.Denied = new int[0];
            empty.FilesScanned = new long[0]; empty.DirsScanned = new long[0];
            empty.BudgetHit = new int[0]; empty.Cancelled = new int[0];
            return empty;
        }
        if (maxDop < 1) maxDop = 1;

        int n = paths.Length;
        long[] sizes        = new long[n];
        int[]  denied       = new int[n];
        long[] filesScanned = new long[n];
        long[] dirsScanned  = new long[n];
        int[]  budgetHit    = new int[n];
        int[]  cancelled    = new int[n];

        int presetDepth, presetFiles, presetDirs, presetTimeout;
        GetPreset(mode, out presetDepth, out presetFiles, out presetDirs, out presetTimeout);

        using (var overallCts = new CancellationTokenSource(presetTimeout))
        using (var sem = new SemaphoreSlim(maxDop, maxDop))
        {
            var tasks = new Task[n];
            for (int i = 0; i < n; i++)
            {
                int idx = i;
                string p = paths[idx];
                string g = (globs != null && globs.Length > idx) ? globs[idx] : null;

                int bd = presetDepth, bf = presetFiles, bdr = presetDirs;
                if (budgets != null && budgets.Length > idx && !string.IsNullOrEmpty(budgets[idx]))
                {
                    var parts = budgets[idx].Split(':');
                    int d, f, dr;
                    if (parts.Length >= 1 && int.TryParse(parts[0], out d)  && d  > 0) bd  = d;
                    if (parts.Length >= 2 && int.TryParse(parts[1], out f)  && f  > 0) bf  = f;
                    if (parts.Length >= 3 && int.TryParse(parts[2], out dr) && dr > 0) bdr = dr;
                }

                tasks[idx] = Task.Run(() =>
                {
                    try
                    {
                        sem.Wait(overallCts.Token);
                        try
                        {
                            var res = ScanOne(p, g, bd, bf, bdr, overallCts);
                            sizes[idx]        = res.Bytes;
                            filesScanned[idx] = res.Files;
                            dirsScanned[idx]  = res.Dirs;
                            budgetHit[idx]    = res.BudgetHit ? 1 : 0;
                            cancelled[idx]    = res.Cancelled ? 1 : 0;
                        }
                        finally { sem.Release(); }
                    }
                    catch (OperationCanceledException) { cancelled[idx] = 1; }
                    catch (UnauthorizedAccessException) { denied[idx] = 1; }
                    catch { denied[idx] = 1; }
                });
            }
            try { Task.WaitAll(tasks); }
            catch (AggregateException) { }
        }

        var result = new ParallelScanResult();
        result.Sizes = sizes; result.Denied = denied;
        result.FilesScanned = filesScanned; result.DirsScanned = dirsScanned;
        result.BudgetHit = budgetHit; result.Cancelled = cancelled;
        return result;
    }

    private sealed class ScanOneResult
    {
        public long Bytes; public long Files; public long Dirs;
        public bool BudgetHit; public bool Cancelled;
    }

    private static ScanOneResult ScanOne(string path, string glob, int maxDepth,
                                          int maxFiles, int maxDirs, CancellationTokenSource cts)
    {
        var result = new ScanOneResult();
        try
        {
            if (File.Exists(path))
            {
                result.Bytes = new FileInfo(path).Length;
                result.Files = 1;
                return result;
            }
            var di = new DirectoryInfo(path);
            if (!di.Exists) return result;

            // never follow junctions/symlinks at the root either
            if ((di.Attributes & FileAttributes.ReparsePoint) != 0) return result;

            if (!string.IsNullOrEmpty(glob))
            {
                foreach (var f in di.EnumerateFiles(glob, SearchOption.TopDirectoryOnly))
                    result.Bytes += f.Length;
                return result;
            }

            // First pass: enumerate top-level files + collect sub-dir names
            long rootFileBytes = 0;
            long rootFileCount = 0;
            foreach (var f in SafeEnumerateFiles(di))
            {
                if (cts.Token.IsCancellationRequested) { result.Cancelled = true; break; }
                rootFileBytes += f.Length;
                rootFileCount++;
                if (maxFiles > 0 && rootFileCount >= maxFiles) { result.BudgetHit = true; break; }
            }
            if (result.Cancelled || result.BudgetHit)
            { result.Bytes = rootFileBytes; result.Files = rootFileCount; return result; }

            var subDirNames = new List<string>();
            foreach (var d in SafeEnumerateDirs(di))
            {
                if ((d.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                subDirNames.Add(d.Name);
            }

            long totalBytes = rootFileBytes;
            long totalFiles = rootFileCount;
            long dirCount   = subDirNames.Count;

            if (maxDirs > 0 && dirCount >= maxDirs)
            {
                result.BudgetHit = true;
                result.Bytes = totalBytes;
                result.Files = totalFiles;
                result.Dirs = dirCount;
                return result;
            }

            for (int i = 0; i < subDirNames.Count; i++)
            {
                if (cts.Token.IsCancellationRequested) { result.Cancelled = true; break; }
                var sd = new DirectoryInfo(Path.Combine(path, subDirNames[i]));
                int remainingFiles = maxFiles > 0 ? maxFiles - (int)totalFiles : maxFiles;
                int remainingDirs  = maxDirs  > 0 ? maxDirs  - (int)dirCount  : maxDirs;
                var sub = Recurse(sd, 1, maxDepth, remainingFiles, remainingDirs, cts);
                totalBytes += sub.Bytes;
                totalFiles += sub.Files;
                dirCount   += sub.Dirs;
                result.BudgetHit |= sub.BudgetHit;
                result.Cancelled |= sub.Cancelled;
                if (result.Cancelled || result.BudgetHit) break;
            }

            result.Bytes = totalBytes;
            result.Files = totalFiles;
            result.Dirs = dirCount;
        }
        catch { /* swallow, result remains 0 */ }
        return result;
    }

    // C# 5 iterator restriction: no yield inside try-with-catch, so wrap the
    // enumeration result instead (collect-then-yield keeps memory bounded per dir).
    private static IEnumerable<FileInfo> SafeEnumerateFiles(DirectoryInfo di)
    {
        FileInfo[] items = null;
        try { items = ToArray(di.EnumerateFiles()); }
        catch { }
        if (items != null) { foreach (var f in items) yield return f; }
    }

    private static IEnumerable<DirectoryInfo> SafeEnumerateDirs(DirectoryInfo di)
    {
        DirectoryInfo[] items = null;
        try { items = ToArray(di.EnumerateDirectories()); }
        catch { }
        if (items != null) { foreach (var d in items) yield return d; }
    }

    private static FileInfo[] ToArray(IEnumerable<FileInfo> src)
    {
        var list = new List<FileInfo>(1024);
        foreach (var f in src) list.Add(f);
        return list.ToArray();
    }

    private static DirectoryInfo[] ToArray(IEnumerable<DirectoryInfo> src)
    {
        var list = new List<DirectoryInfo>(256);
        foreach (var d in src) list.Add(d);
        return list.ToArray();
    }

    private static ScanOneResult Recurse(DirectoryInfo di, int depth, int maxDepth,
                                          int maxFiles, int maxDirs, CancellationTokenSource cts)
    {
        var result = new ScanOneResult();
        if (depth > maxDepth) { result.BudgetHit = true; return result; }

        long fileCount = 0, dirCount = 1;
        long bytes = 0;

        foreach (var f in SafeEnumerateFiles(di))
        {
            if (cts.Token.IsCancellationRequested) { result.Cancelled = true; break; }
            bytes += f.Length;
            fileCount++;
            if (maxFiles > 0 && fileCount >= maxFiles) { result.BudgetHit = true; break; }
        }
        if (result.Cancelled || result.BudgetHit)
        { result.Bytes = bytes; result.Files = fileCount; result.Dirs = dirCount; return result; }

        var subDirNames = new List<string>();
        foreach (var d in SafeEnumerateDirs(di))
        {
            if ((d.Attributes & FileAttributes.ReparsePoint) != 0) continue;
            subDirNames.Add(d.Name);
        }

        for (int i = 0; i < subDirNames.Count; i++)
        {
            if (cts.Token.IsCancellationRequested) { result.Cancelled = true; break; }
            if (maxDirs > 0 && dirCount >= maxDirs) { result.BudgetHit = true; break; }

            var sd = new DirectoryInfo(Path.Combine(di.FullName, subDirNames[i]));
            int remFiles = maxFiles > 0 ? maxFiles - (int)fileCount : maxFiles;
            int remDirs  = maxDirs  > 0 ? maxDirs  - (int)dirCount  : maxDirs;
            var sub = Recurse(sd, depth + 1, maxDepth, remFiles, remDirs, cts);
            bytes += sub.Bytes;
            fileCount += sub.Files;
            dirCount  += sub.Dirs;
            result.BudgetHit |= sub.BudgetHit;
            result.Cancelled |= sub.Cancelled;
            if (result.Cancelled || result.BudgetHit) break;
        }

        result.Bytes = bytes;
        result.Files = fileCount;
        result.Dirs = dirCount;
        return result;
    }
}
