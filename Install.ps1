#requires -Version 5.0
<#
 BioShock Infinite - Carry All Guns + 13-slot Weapon Wheel
 Patches the user's own stock game files. No game data and no executable is shipped in this package.
   Install.ps1                 install (auto-detects the game folder)
   Install.ps1 -GameDir "D:\Games\BioShock Infinite"
   Install.ps1 -HoldToAim yes|no   hold-to-aim (aim only while the key is held) on/off; default: ask
   Install.ps1 -Uninstall      restore the original files from the backup
   Running it again with the other -HoldToAim value switches the option.
#>
param(
    [string]$GameDir = "",
    [ValidateSet("ask", "yes", "no")][string]$HoldToAim = "ask",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$src = @'
using System;
using System.IO;
using System.Security.Cryptography;

public static class BiPatch
{
    const uint TAG = 0x9E2A83C1;

    public static string Sha(byte[] b)
    {
        using (SHA256 s = SHA256.Create())
        {
            return BitConverter.ToString(s.ComputeHash(b)).Replace("-", "");
        }
    }

    static int I32(byte[] b, int o) { return BitConverter.ToInt32(b, o); }
    static void P32(byte[] b, int o, int v) { Buffer.BlockCopy(BitConverter.GetBytes(v), 0, b, o, 4); }

    static void ApplyEdits(byte[] data, byte[] patch, ref int pos)
    {
        int n = I32(patch, pos); pos += 4;
        for (int i = 0; i < n; i++)
        {
            int off = I32(patch, pos); int len = I32(patch, pos + 4); pos += 8;
            Buffer.BlockCopy(patch, pos, data, off, len); pos += len;
        }
    }

    static byte[] ApplyOps(byte[] src, byte[] patch, ref int pos)
    {
        int n = I32(patch, pos); pos += 4;
        MemoryStream ms = new MemoryStream();
        for (int i = 0; i < n; i++)
        {
            int type = patch[pos]; pos++;
            if (type == 0)
            {
                int off = I32(patch, pos); int len = I32(patch, pos + 4); pos += 8;
                ms.Write(src, off, len);
            }
            else
            {
                int len = I32(patch, pos); pos += 4;
                ms.Write(patch, pos, len); pos += len;
            }
        }
        return ms.ToArray();
    }

    public static byte[] PatchExe(byte[] stock, byte[] patch)
    {
        byte[] r = (byte[])stock.Clone();
        int pos = 0;
        ApplyEdits(r, patch, ref pos);
        return r;
    }

    public static byte[] PatchInt(byte[] stock, byte[] patch)
    {
        int pos = 0;
        return ApplyOps(stock, patch, ref pos);
    }

    // ---- LZO1X
    static void Lit(byte[] src, ref int ip, byte[] dst, ref int op, int end, int n)
    {
        if (op + n > end || ip + n > src.Length) throw new InvalidDataException("LZO literal overrun");
        Buffer.BlockCopy(src, ip, dst, op, n); ip += n; op += n;
    }

    static void Match(byte[] dst, ref int op, int start, int end, int dist, int len)
    {
        int from = op - dist;
        if (from < start || op + len > end) throw new InvalidDataException("LZO match out of range");
        for (int i = 0; i < len; i++) { dst[op] = dst[from + i]; op++; }
    }

    static void Lzo(byte[] src, int ip, byte[] dst, int op, int outLen)
    {
        int start = op;
        int end = op + outLen;
        int t, dist, length;
        int state = 0;
        if (src[ip] > 17)
        {
            t = src[ip] - 17; ip++;
            Lit(src, ref ip, dst, ref op, end, t);
            state = t >= 4 ? 4 : t;
        }
        while (true)
        {
            t = src[ip]; ip++;
            if (t < 16)
            {
                if (state == 0)
                {
                    if (t == 0)
                    {
                        while (src[ip] == 0) { t += 255; ip++; }
                        t += 15 + src[ip]; ip++;
                    }
                    Lit(src, ref ip, dst, ref op, end, t + 3);
                    state = 4;
                    continue;
                }
                if (state == 4)
                {
                    dist = 1 + 0x0800 + (t >> 2) + (src[ip] << 2); ip++;
                    Match(dst, ref op, start, end, dist, 3);
                }
                else
                {
                    dist = 1 + (t >> 2) + (src[ip] << 2); ip++;
                    Match(dst, ref op, start, end, dist, 2);
                }
            }
            else if (t >= 64)
            {
                dist = 1 + ((t >> 2) & 7) + (src[ip] << 3); ip++;
                Match(dst, ref op, start, end, dist, (t >> 5) - 1 + 2);
            }
            else if (t >= 32)
            {
                length = t & 31;
                if (length == 0)
                {
                    while (src[ip] == 0) { length += 255; ip++; }
                    length += 31 + src[ip]; ip++;
                }
                dist = 1 + (src[ip] >> 2) + (src[ip + 1] << 6); ip += 2;
                Match(dst, ref op, start, end, dist, length + 2);
                t = src[ip - 2];
            }
            else
            {
                length = t & 7;
                dist = (t & 8) << 11;
                if (length == 0)
                {
                    while (src[ip] == 0) { length += 255; ip++; }
                    length += 7 + src[ip]; ip++;
                }
                dist += (src[ip] >> 2) + (src[ip + 1] << 6); ip += 2;
                if (dist == 0) break;
                Match(dst, ref op, start, end, dist + 0x4000, length + 2);
                t = src[ip - 2];
            }
            state = t & 3;
            if (state != 0) Lit(src, ref ip, dst, ref op, end, state);
        }
        if (op != end) throw new InvalidDataException("LZO size mismatch");
    }

    static byte[] LiteralOnly(byte[] data, int off, int n)
    {
        MemoryStream o = new MemoryStream();
        if (n <= 238) o.WriteByte((byte)(17 + n));
        else
        {
            int tt = n - 18;
            o.WriteByte(0);
            while (tt > 255) { tt -= 255; o.WriteByte(0); }
            o.WriteByte((byte)tt);
        }
        o.Write(data, off, n);
        o.WriteByte(0x11); o.WriteByte(0); o.WriteByte(0);
        return o.ToArray();
    }

    static void DecodeChunk(byte[] comp, int co, int uo, int us, byte[] dst)
    {
        if ((uint)I32(comp, co) != TAG) throw new InvalidDataException("bad chunk tag");
        int bsize = I32(comp, co + 4);
        if (I32(comp, co + 12) != us) throw new InvalidDataException("bad chunk size");
        int nb = (us + bsize - 1) / bsize;
        int pos = co + 16 + nb * 8;
        int o = uo;
        for (int j = 0; j < nb; j++)
        {
            int cs = I32(comp, co + 16 + j * 8);
            int usz = I32(comp, co + 16 + j * 8 + 4);
            Lzo(comp, pos, dst, o, usz);
            o += usz; pos += cs;
        }
    }

    public static byte[] PatchMasterP(byte[] comp, byte[] patch, int tab, int nch)
    {
        int[] uoA = new int[nch], usA = new int[nch], coA = new int[nch], csA = new int[nch];
        for (int i = 0; i < nch; i++)
        {
            uoA[i] = I32(comp, tab + i * 16); usA[i] = I32(comp, tab + i * 16 + 4);
            coA[i] = I32(comp, tab + i * 16 + 8); csA[i] = I32(comp, tab + i * 16 + 12);
        }
        int L = nch - 1;
        int uo = uoA[L], us = usA[L], co = coA[L];
        if (co + csA[L] != comp.Length) throw new InvalidDataException("unexpected Master_P layout");
        int S = uo + us;

        byte[] dold = new byte[S];
        for (int i = 0; i < nch; i++) DecodeChunk(comp, coA[i], uoA[i], usA[i], dold);

        byte[] head = new byte[co];
        Buffer.BlockCopy(comp, 0, head, 0, co);
        int pos = 0;
        ApplyEdits(head, patch, ref pos);
        byte[] tail = ApplyOps(dold, patch, ref pos);

        byte[] nu = new byte[us + tail.Length];
        Buffer.BlockCopy(dold, uo, nu, 0, us);
        Buffer.BlockCopy(tail, 0, nu, us, tail.Length);

        int bsize = I32(comp, co + 4);
        int nbOld = (us + bsize - 1) / bsize;
        int dpos = co + 16 + nbOld * 8;
        System.Collections.Generic.List<byte[]> blocks = new System.Collections.Generic.List<byte[]>();
        System.Collections.Generic.List<int> usz = new System.Collections.Generic.List<int>();
        for (int j = 0; j < nbOld; j++)
        {
            int cs = I32(comp, co + 16 + j * 8);
            int u = I32(comp, co + 16 + j * 8 + 4);
            if (u == bsize)
            {
                byte[] b = new byte[cs];
                Buffer.BlockCopy(comp, dpos, b, 0, cs);
                blocks.Add(b); usz.Add(u);
            }
            dpos += cs;
        }
        for (int p = blocks.Count * bsize; p < nu.Length; p += bsize)
        {
            int n = Math.Min(bsize, nu.Length - p);
            blocks.Add(LiteralOnly(nu, p, n)); usz.Add(n);
        }
        int sum = 0;
        for (int i = 0; i < blocks.Count; i++) sum += blocks[i].Length;
        MemoryStream ch = new MemoryStream();
        byte[] hd = new byte[16];
        P32(hd, 0, unchecked((int)TAG)); P32(hd, 4, bsize); P32(hd, 8, sum); P32(hd, 12, nu.Length);
        ch.Write(hd, 0, 16);
        for (int i = 0; i < blocks.Count; i++)
        {
            byte[] e = new byte[8];
            P32(e, 0, blocks[i].Length); P32(e, 4, usz[i]);
            ch.Write(e, 0, 8);
        }
        for (int i = 0; i < blocks.Count; i++) ch.Write(blocks[i], 0, blocks[i].Length);
        byte[] chunk = ch.ToArray();

        byte[] res = new byte[co + chunk.Length];
        Buffer.BlockCopy(head, 0, res, 0, co);
        Buffer.BlockCopy(chunk, 0, res, co, chunk.Length);
        P32(res, tab + L * 16, uo); P32(res, tab + L * 16 + 4, nu.Length);
        P32(res, tab + L * 16 + 8, co); P32(res, tab + L * 16 + 12, chunk.Length);
        return res;
    }
}
'@
Add-Type -TypeDefinition $src -Language CSharp

function Say($s) { Write-Host $s }
function Test-Game($d) { return ($d -and (Test-Path -LiteralPath (Join-Path $d "Binaries\Win32\BioShockInfinite.exe"))) }

function Find-Game {
    $c = @($here, (Split-Path -Parent $here), (Get-Location).Path)
    $steam = $null
    try { $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath } catch { }
    $libs = @()
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $libs += $steam
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            foreach ($mm in [regex]::Matches((Get-Content -Raw -LiteralPath $vdf), '"path"\s+"([^"]+)"')) {
                $libs += ($mm.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    foreach ($l in $libs) { $c += (Join-Path $l "steamapps\common\BioShock Infinite") }
    foreach ($d in $c) { if (Test-Game $d) { return $d } }
    return $null
}

function Read-Bytes($p) { return [IO.File]::ReadAllBytes($p) }
function Write-Atomic($path, [byte[]]$bytes) {
    $tmp = $path + ".bi_tmp"
    [IO.File]::WriteAllBytes($tmp, $bytes)
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    Move-Item -LiteralPath $tmp -Destination $path
}

try {
    $m = Get-Content -Raw -LiteralPath (Join-Path $here "data\manifest.json") | ConvertFrom-Json

    if ($GameDir) { $g = $GameDir.TrimEnd('\') } else { $g = Find-Game }
    if (-not (Test-Game $g)) {
        $g = (Read-Host "Game folder not found. Enter the BioShock Infinite folder (contains Binaries and XGame)").Trim('"').TrimEnd('\')
    }
    if (-not (Test-Game $g)) { throw "BioShockInfinite.exe not found under: $g" }
    Say "Game folder: $g"

    if (Get-Process -Name "BioShockInfinite" -ErrorAction SilentlyContinue) {
        throw "BioShock Infinite is running. Close the game and run this again."
    }

    $bk = Join-Path $g "BI-AllGuns-WeaponWheel-backup"
    $latin = [Text.Encoding]::GetEncoding(28591)
    $tocFiles = @(Get-ChildItem -LiteralPath (Join-Path $g "XGame") -Filter "PCConsoleTOC*.txt" -File)

    if ($Uninstall) {
        if (-not (Test-Path -LiteralPath $bk)) { throw "No backup folder found ($bk). Use Steam: right-click the game > Properties > Installed Files > Verify integrity." }
        foreach ($f in Get-ChildItem -LiteralPath $bk -Recurse -File) {
            $rel = $f.FullName.Substring($bk.Length).TrimStart('\')
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $g $rel) -Force
            Say "Restored $rel"
        }
        $chk = @(@("Binaries\Win32\BioShockInfinite.exe", $m.exe.stock_sha), @($m.masterp.path, $m.masterp.stock_sha), @($m.int.path, $m.int.stock_sha))
        foreach ($c in $chk) {
            $h = [BiPatch]::Sha((Read-Bytes (Join-Path $g $c[0])))
            if ($h -ne $c[1]) { Say "WARNING: $($c[0]) does not match the stock hash after restore." } else { Say "Verified $($c[0])" }
        }
        Remove-Item -LiteralPath $bk -Recurse -Force
        Say "Uninstalled."
        return
    }

    # ---------------------------------------------------------- options
    if ($HoldToAim -eq "ask") {
        Say ""
        Say "Hold-to-aim: aim only while the zoom key (Z / middle mouse) is held, instead of toggling."
        $ans = (Read-Host "Enable hold-to-aim? [Y/n]").Trim().ToLower()
        $HoldToAim = if ($ans -eq "n" -or $ans -eq "no") { "no" } else { "yes" }
    }
    $hold = ($HoldToAim -eq "yes")
    $wantExe = if ($hold) { $m.exe.new_sha } else { $m.exe.nohold_sha }
    Say ("Hold-to-aim: " + $HoldToAim)

    # ---------------------------------------------------------- plan (everything is computed and verified in memory first)
    $plan = @()
    $already = 0

    $items = @(
        @{ Rel = "Binaries\Win32\BioShockInfinite.exe"; Info = $m.exe; Bin = "exe.bin"; Kind = "exe"; Want = $wantExe },
        @{ Rel = $m.masterp.path; Info = $m.masterp; Bin = "masterp.bin"; Kind = "masterp"; Want = $m.masterp.new_sha },
        @{ Rel = $m.int.path; Info = $m.int; Bin = "int.bin"; Kind = "int"; Want = $m.int.new_sha }
    )
    foreach ($it in $items) {
        $p = Join-Path $g $it.Rel
        if (-not (Test-Path -LiteralPath $p)) { throw "Missing game file: $($it.Rel)" }
        $b = Read-Bytes $p
        $h = [BiPatch]::Sha($b)
        if ($h -eq $it.Want) { $already++; Say "Already patched: $($it.Rel)"; continue }
        if ($it.Kind -eq "exe" -and ($h -eq $it.Info.new_sha -or $h -eq $it.Info.nohold_sha)) {
            # already installed with the other hold-to-aim setting: flip the one byte
            $nb = [byte[]]$b.Clone()
            $nb[[int]$it.Info.hold_off] = $(if ($hold) { [byte]$it.Info.hold_byte } else { [byte]$it.Info.nohold_byte })
            if ([BiPatch]::Sha($nb) -ne $it.Want) { throw "Internal check failed while switching hold-to-aim. Nothing was changed." }
            Say "Switching hold-to-aim in $($it.Rel)"
            $plan += @{ Path = $p; Rel = $it.Rel; Bytes = $nb }
            continue
        }
        if ($h -ne $it.Info.stock_sha) {
            throw "$($it.Rel) is not the expected stock version (sha256 $h). It may be modified by another mod or a different game version. Verify game files in Steam first. Nothing was changed."
        }
        Say "Building $($it.Rel) ..."
        $patch = Read-Bytes (Join-Path $here ("data\" + $it.Bin))
        if ($it.Kind -eq "exe") { $nb = [BiPatch]::PatchExe($b, $patch) }
        elseif ($it.Kind -eq "int") { $nb = [BiPatch]::PatchInt($b, $patch) }
        else { $nb = [BiPatch]::PatchMasterP($b, $patch, [int]$m.masterp.tab, [int]$m.masterp.nch) }
        if ($it.Kind -eq "exe" -and -not $hold) { $nb[[int]$it.Info.hold_off] = [byte]$it.Info.nohold_byte }
        if ([BiPatch]::Sha($nb) -ne $it.Want) { throw "Internal check failed for $($it.Rel) (result hash mismatch). Nothing was changed." }
        $plan += @{ Path = $p; Rel = $it.Rel; Bytes = $nb }
    }

    $mo = $m.toc.master_old; $mn = $m.toc.master_new; $io = $m.toc.int_old; $inew = $m.toc.int_new
    foreach ($tf in $tocFiles) {
        $s = $latin.GetString((Read-Bytes $tf.FullName))
        $n = $s
        $touched = $false
        if ($n.Contains($mo)) { $n = $n.Replace($mo, $mn); $touched = $true }
        elseif (-not $n.Contains($mn)) { throw "$($tf.Name) is not in the expected format. Nothing was changed." }
        if ($n.Contains($io)) { $n = $n.Replace($io, $inew); $touched = $true }
        if ($touched) { $plan += @{ Path = $tf.FullName; Rel = ("XGame\" + $tf.Name); Bytes = $latin.GetBytes($n) } }
    }

    if ($plan.Count -eq 0) { Say "Mod is already installed. Nothing to do."; return }

    # ---------------------------------------------------------- backup, then write
    foreach ($pl in $plan) {
        $dest = Join-Path $bk $pl.Rel
        if (-not (Test-Path -LiteralPath $dest)) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            Copy-Item -LiteralPath $pl.Path -Destination $dest
        }
    }
    Say "Backup: $bk"
    foreach ($pl in $plan) {
        Write-Atomic $pl.Path $pl.Bytes
        Say "Patched $($pl.Rel)"
    }

    # ---------------------------------------------------------- verify
    foreach ($it in $items) {
        $h = [BiPatch]::Sha((Read-Bytes (Join-Path $g $it.Rel)))
        if ($h -ne $it.Want) { throw "Post-install check failed for $($it.Rel). Run Uninstall.bat to restore." }
    }
    Say ""
    Say "Installed. Start the game: you now carry all guns; hold E for the weapon wheel."
    Say "To remove the mod run Uninstall.bat (originals are kept in the backup folder)."
}
catch {
    Write-Host ""
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
