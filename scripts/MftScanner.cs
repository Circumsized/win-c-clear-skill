// MftScanner.cs — NTFS MFT direct-read scanner for win-c-clear-skill (Analyze fast path).
// Principle: every file/dir has a fixed-size record in the MFT containing name, parent
// reference and $DATA sizes. Sequentially reading the MFT = full volume file list without
// directory-tree recursion (3-5x faster). Requires admin + NTFS; engine falls back to the
// .NET/robocopy scanner on any failure.
//
// Native APIs used:
//   CreateFile(\\.\C:)              raw volume handle (GENERIC_READ)
//   DeviceIoControl FSCTL_GET_NTFS_VOLUME_DATA (0x00090064) -> MftStartLcn, BytesPerFileRecordSegment
//   SetFilePointerEx + ReadFile     sequential MFT zone read
// Record parsing: FILE header (fixup/USN applied) -> attributes walk ->
//   0x30 $FILE_NAME (parent FRN + name) / 0x80 $DATA unnamed (real size).
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class MftScanner
{
    private const uint FSCTL_GET_NTFS_VOLUME_DATA = 0x00090064;
    private const uint GENERIC_READ = 0x80000000;
    private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, FILE_SHARE_DELETE = 4;
    private const uint OPEN_EXISTING = 3;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes,
        uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(
        Microsoft.Win32.SafeHandles.SafeFileHandle hDevice, uint ioControlCode,
        IntPtr lpInBuffer, uint nInBufferSize, byte[] lpOutBuffer, uint nOutBufferSize,
        out uint lpBytesReturned, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFilePointerEx(
        Microsoft.Win32.SafeHandles.SafeFileHandle hFile, long liDistanceToMove,
        out long lpNewFilePointer, uint dwMoveMethod);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadFile(
        Microsoft.Win32.SafeHandles.SafeFileHandle hFile, byte[] lpBuffer, uint nNumberOfBytesToRead,
        out uint lpNumberOfBytesRead, IntPtr lpOverlapped);

    private sealed class Entry
    {
        public ulong Parent; public string Name; public long Size; public bool IsDir;
    }

    // diagnostics counters (returned in the summary line for tuning)
    public static long DiagInUse, DiagNamed, DiagWithData, DiagAttrBreak, DiagS24, DiagS2C, DiagS30;

    // Scans the MFT of `volume` (e.g. "C"). Writes TSV lines to outFilePath:
    //   S <tab> totalFiles <tab> totalBytes
    //   D <tab> <first-level-dir-under-a-root> <tab> bytes
    //   F <tab> <path> <tab> bytes        (files >= bigBytes under a root, top 500 by size)
    //   C <tab> <path> <tab> bytes        (files >= dupBytes under a root, top dupCap by size)
    // Boundary filter: only paths strictly under one of `roots` appear in D/F/C output.
    // Files outside all roots (e.g. Windows core dirs) are counted in S but NEVER reported.
    // `blacklistPatterns` (optional) are regexes matched against lowercased absolute path;
    // matching paths are excluded from D/F/C even when under a root (defense in depth).
    public static string Scan(string volume, string outFilePath, string[] roots,
                              long bigBytes, long dupBytes, int dupCap)
    {
        return Scan(volume, outFilePath, roots, bigBytes, dupBytes, dupCap, null);
    }

    public static string Scan(string volume, string outFilePath, string[] roots,
                              long bigBytes, long dupBytes, int dupCap, string[] blacklistPatterns)
    {
        var rootSet = new List<string>(roots.Length);
        foreach (var r in roots) { var t = r.TrimEnd('\\'); if (t.Length > 0) rootSet.Add(t); }
        using (var h = CreateFile("\\\\.\\" + volume + ":",
                 GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                 IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero))
        {
            if (h.IsInvalid) throw new IOException("cannot open volume (admin required?)");
            var vdb = new byte[0x60];
            uint br;
            if (!DeviceIoControl(h, FSCTL_GET_NTFS_VOLUME_DATA, IntPtr.Zero, 0, vdb, (uint)vdb.Length, out br, IntPtr.Zero))
                throw new IOException("FSCTL_GET_NTFS_VOLUME_DATA failed (not NTFS?)");
            ulong mftStartLcn = BitConverter.ToUInt64(vdb, 64);   // offset 64
            uint clusterBytes = BitConverter.ToUInt32(vdb, 44);   // offset 44
            uint frsBytes = BitConverter.ToUInt32(vdb, 48);       // offset 48
            ulong mftValid = BitConverter.ToUInt64(vdb, 56);      // offset 56
            if (frsBytes < 512 || frsBytes > 4096) throw new IOException("unexpected FRS size");
            long mftOffset = (long)(mftStartLcn * clusterBytes);
            long mftLen = (long)mftValid;   // MftValidDataLength is in BYTES (4.3GB => ~4.2M records)

            var entries = new Dictionary<ulong, Entry>(2000000);
            var buf = new byte[4 * 1024 * 1024];
            long totalFiles = 0; long totalBytes = 0;

            // ---- enumerate MFT extents by parsing MFT's own $DATA run list (record 0) ----
            // MftValidDataLength is the LOGICAL size; the MFT can be fragmented on disk, so a
            // plain sequential read from MftStartLcn only covers the first extent.
            var runs = new List<long[]>();   // [lcn, byteLength]
            long vcnCursor = 0;              // logical VCN cursor for record numbering
            {
                var rec0 = new byte[frsBytes];
                long sp0;
                if (!SetFilePointerEx(h, mftOffset, out sp0, 0)) throw new IOException("seek record0 failed");
                uint g0;
                if (!ReadFile(h, rec0, frsBytes, out g0, IntPtr.Zero) || g0 < frsBytes) throw new IOException("read record0 failed");
                if (!ApplyFixups(rec0)) throw new IOException("record0 fixup failed");
                int p = BitConverter.ToUInt16(rec0, 0x14);
                uint used0 = BitConverter.ToUInt32(rec0, 0x18);
                if (used0 > frsBytes) used0 = frsBytes;
                bool found = false;
                while (p + 8 <= used0)
                {
                    uint type = BitConverter.ToUInt32(rec0, p);
                    if (type == 0xFFFFFFFF) break;
                    uint len = BitConverter.ToUInt32(rec0, p + 4);
                    if (len < 8 || p + len > used0) break;
                    if (type == 0x80 && rec0[p + 8] != 0 && rec0[p + 9] == 0)
                    {
                        int ro = BitConverter.ToUInt16(rec0, p + 0x20);
                        long lcn = 0; int q = p + ro;
                        while (q < p + (int)len && q < frsBytes && rec0[q] != 0)
                        {
                            int b = rec0[q]; int ls = b & 0x0F; int os = b >> 4; q++;
                            long runLen = 0; long runOff = 0;
                            for (int i = 0; i < ls && q < frsBytes; i++) { runLen |= (long)rec0[q] << (8 * i); q++; }
                            bool neg = (os > 0 && (rec0[q + os - 1] & 0x80) != 0);
                            for (int i = 0; i < os && q < frsBytes; i++) { runOff |= (long)rec0[q] << (8 * i); q++; }
                            if (neg) runOff -= (1L << (8 * os));
                            lcn += runOff;
                            long runBytes = runLen * (long)clusterBytes;
                            long clamp = Math.Min(runBytes, mftLen - vcnCursor * clusterBytes);
                            if (clamp > 0 && lcn >= 0) runs.Add(new long[] { lcn, clamp });
                            vcnCursor += runLen;
                        }
                        found = true;
                        break;
                    }
                    p += (int)len;
                }
                if (!found || runs.Count == 0)
                {
                    // fallback: single extent assumption (contiguous MFT)
                    runs.Add(new long[] { (long)mftStartLcn, Math.Min(mftLen, 64L * 1024 * 1024) });
                }
            }

            // ---- walk all extents, parsing records with GLOBAL logical record numbers ----
            long recBaseVcn = 0;
            long chunks = 0;
            foreach (var run in runs)
            {
                long runLcn = run[0]; long runLen = run[1];
                long done = 0;
                while (done < runLen)
                {
                    uint want = (uint)Math.Min((long)buf.Length, runLen - done);
                    long spNew;
                    if (!SetFilePointerEx(h, runLcn * (long)clusterBytes + done, out spNew, 0)) break;
                    uint got;
                    if (!ReadFile(h, buf, want, out got, IntPtr.Zero) || got == 0) break;
                    chunks++;
                    long recNo = (recBaseVcn * clusterBytes + done) / frsBytes;
                    for (uint off = 0; off + frsBytes <= got; off += frsBytes, recNo++)
                    {
                        var rec = new byte[frsBytes];
                        Array.Copy(buf, off, rec, 0, frsBytes);
                        ParseRecord(rec, entries, ref totalFiles, ref totalBytes, recNo);
                    }
                    done += got;
                }
                recBaseVcn += runLen / clusterBytes;
            }
            System.Console.Error.WriteLine("mftread: extents=" + runs.Count + " chunks=" + chunks + " entries=" + entries.Count);

            // Pass 2: resolve paths, aggregate under roots, collect big/dup candidates.
            // Boundary filter: big/dup candidates are ONLY collected under a root and
            // never for blacklist-matching paths (system core areas stay invisible).
            System.Text.RegularExpressions.Regex[] black = null;
            if (blacklistPatterns != null && blacklistPatterns.Length > 0)
            {
                var rl = new List<System.Text.RegularExpressions.Regex>(blacklistPatterns.Length);
                foreach (var bp in blacklistPatterns)
                {
                    if (string.IsNullOrEmpty(bp)) continue;
                    try { rl.Add(new System.Text.RegularExpressions.Regex(bp, System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.Compiled)); }
                    catch { }
                }
                if (rl.Count > 0) black = rl.ToArray();
            }
            long diagOutsideRoots = 0; long diagBlacklisted = 0;
            var dirAgg = new Dictionary<string, long>();
            var big = new List<KeyValuePair<string, long>>();
            var dup = new List<KeyValuePair<string, long>>();
            string volPrefix = volume + ":\\";
            foreach (var kv in entries)
            {
                var e = kv.Value;
                if (e.IsDir || e.Name == null) continue;
                string rel = BuildPath(entries, kv.Key);
                if (rel == null) continue;
                string path = volPrefix + rel;
                bool inRoot = false;
                foreach (var root in rootSet)
                {
                    if (path.Length > root.Length + 1 &&
                        path.StartsWith(root, StringComparison.OrdinalIgnoreCase) &&
                        path[root.Length] == '\\')
                    {
                        int next = path.IndexOf('\\', root.Length + 1);
                        string seg = next < 0 ? path : path.Substring(0, next);
                        long cur; dirAgg[seg] = dirAgg.TryGetValue(seg, out cur) ? cur + e.Size : e.Size;
                        inRoot = true;
                        break;
                    }
                }
                // boundary gate: outside every rule root -> not reportable
                if (!inRoot)
                {
                    if (e.Size >= bigBytes || e.Size >= dupBytes) diagOutsideRoots++;
                    continue;
                }
                // blacklist gate: defense in depth even inside roots
                if (black != null)
                {
                    string lower = path.ToLowerInvariant();
                    bool hitBl = false;
                    foreach (var rx in black) { if (rx.IsMatch(lower)) { hitBl = true; break; } }
                    if (hitBl) { diagBlacklisted++; continue; }
                }
                if (e.Size >= bigBytes) big.Add(new KeyValuePair<string, long>(path, e.Size));
                if (e.Size >= dupBytes) dup.Add(new KeyValuePair<string, long>(path, e.Size));
            }

            using (var w = new StreamWriter(outFilePath, false, new UTF8Encoding(false)))
            {
                w.Write("S\t"); w.Write(totalFiles); w.Write('\t'); w.WriteLine(totalBytes);
                foreach (var kv in dirAgg) { w.Write("D\t"); w.Write(kv.Key); w.Write('\t'); w.WriteLine(kv.Value); }
                big.Sort((a, b) => b.Value.CompareTo(a.Value));
                foreach (var kv in big.Count > 500 ? big.GetRange(0, 500) : big)
                { w.Write("F\t"); w.Write(kv.Key); w.Write('\t'); w.WriteLine(kv.Value); }
                dup.Sort((a, b) => b.Value.CompareTo(a.Value));
                int n = Math.Min(dupCap <= 0 ? 2000 : dupCap, dup.Count);
                foreach (var kv in dup.GetRange(0, n))
                { w.Write("C\t"); w.Write(kv.Key); w.Write('\t'); w.WriteLine(kv.Value); }
            }
            return string.Format("mft: {0} entries, {1} files, {2:F2} GB; aggDirs={3}; boundary outsideRoots={4} blacklisted={5}; diag inUse={6} named={7} withData={8} s24={9:F0}GB s2C={10:F0}GB s30={11:F0}GB",
                entries.Count, totalFiles, totalBytes / 1073741824.0, dirAgg.Count,
                diagOutsideRoots, diagBlacklisted,
                DiagInUse, DiagNamed, DiagWithData, DiagS24 / 1073741824.0, DiagS2C / 1073741824.0, DiagS30 / 1073741824.0);
        }
    }

    private static bool ApplyFixups(byte[] rec)
    {
        if (rec[0] != (byte)'F' || rec[1] != (byte)'I' || rec[2] != (byte)'L' || rec[3] != (byte)'E') return false;
        ushort usnOff = BitConverter.ToUInt16(rec, 4);
        ushort usnCnt = BitConverter.ToUInt16(rec, 6);
        if (usnCnt == 0 || usnOff + usnCnt * 2 > rec.Length) return false;
        ushort magic = BitConverter.ToUInt16(rec, usnOff);
        for (int i = 1; i < usnCnt; i++)
        {
            int secEnd = i * 512 - 2;
            if (secEnd < 0 || secEnd + 2 > rec.Length) return false;
            if (BitConverter.ToUInt16(rec, secEnd) != magic) return false; // torn record
            rec[secEnd] = rec[usnOff + i * 2];
            rec[secEnd + 1] = rec[usnOff + i * 2 + 1];
        }
        return true;
    }

    private static void ParseRecord(byte[] rec, Dictionary<ulong, Entry> entries,
        ref long totalFiles, ref long totalBytes, long recNo)
    {
        if (!ApplyFixups(rec)) return;
        ushort flags = BitConverter.ToUInt16(rec, 0x16);
        if ((flags & 1) == 0) return;                       // not in use
        if (BitConverter.ToUInt64(rec, 0x20) != 0) return;  // extension record: sizes live in base
        DiagInUse++;
        ushort firstAttr = BitConverter.ToUInt16(rec, 0x14);
        uint used = BitConverter.ToUInt32(rec, 0x18);
        if (used > rec.Length) used = (uint)rec.Length;

        Entry e = new Entry();
        e.IsDir = (flags & 2) != 0;
        long dataSize = -1;
        int p = firstAttr;
        while (p + 8 <= used)
        {
            uint type = BitConverter.ToUInt32(rec, p);
            if (type == 0xFFFFFFFF) break;
            uint len = BitConverter.ToUInt32(rec, p + 4);
            if (len < 8 || p + len > used) break;
            byte nonRes = rec[p + 8];
            byte nameLen = rec[p + 9];
            if (type == 0x30 && nonRes == 0 && nameLen == 0)
            {
                uint contentLen = BitConverter.ToUInt32(rec, p + 0x10);
                ushort contentOff = BitConverter.ToUInt16(rec, p + 0x14);
                if (contentOff + 0x42 <= p + len && contentLen >= 0x44)
                {
                    int fnl = rec[p + contentOff + 0x40];
                    int ns = rec[p + contentOff + 0x41];
                    if (fnl > 0 && fnl <= 255 && (e.Name == null || ns != 2))
                    {
                        int nameOff = p + contentOff + 0x42;
                        if (nameOff + fnl * 2 <= p + len)
                        {
                            e.Parent = BitConverter.ToUInt64(rec, p + contentOff);
                            e.Name = Encoding.Unicode.GetString(rec, nameOff, fnl * 2);
                            DiagNamed++;
                        }
                    }
                }
            }
            else if (type == 0x80 && nameLen == 0)
            {
                if (nonRes == 0) dataSize = BitConverter.ToUInt32(rec, p + 0x10);
                else if (p + 0x38 <= used)
                {
                    long c24 = BitConverter.ToInt64(rec, p + 0x24);
                    long c2C = BitConverter.ToInt64(rec, p + 0x2C);
                    long c30 = BitConverter.ToInt64(rec, p + 0x30);
                    DiagS24 += c24; DiagS2C += c2C; DiagS30 += c30;
                    dataSize = c30;   // RealSize @ 0x30 (MSDN layout: RunOff/CompUnit/Padding, Allocated@0x28, Real@0x30, Initialized@0x38)
                }
                DiagWithData++;
            }
            p += (int)len;
        }
        if (e.Name == null) return;
        e.Size = dataSize < 0 ? 0 : dataSize;
        entries[(ulong)recNo] = e;
        if (!e.IsDir) { totalFiles++; totalBytes += e.Size; }
    }

    private static string BuildPath(Dictionary<ulong, Entry> entries, ulong frn)
    {
        var parts = new List<string>(16);
        var seen = new HashSet<ulong>();
        ulong cur = frn;
        int depth = 0;
        while (cur != 5 && depth++ < 64)
        {
            if (!seen.Add(cur)) return null;
            Entry e;
            if (!entries.TryGetValue(cur, out e) || e.Name == null) return null;
            parts.Add(e.Name);
            cur = e.Parent & 0xFFFFFFFFFFFF; // low 6 bytes = FRN, high 2 = sequence
        }
        if (cur != 5 || parts.Count == 0) return null;
        parts.Reverse();
        return string.Join("\\", parts.ToArray());
    }
}
