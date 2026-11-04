<#
    LodDedup.ps1 - removes files from the game's LOD archives that another archive of the
    same kind replaces (MMMerge Waffel Edition, 05.11.26)

    How the game picks a file: for every kind of archive the original one is read first
    (bitmaps.lod, icons.lod, sprites.lod, games.lod, EnglishT.lod, EnglishD.lod), then the
    custom ones (*.bitmaps.lod, *.icons.lod ...) in alphabetical order; when several archives
    hold a file of the same name, the one read last wins. Every other copy is never used.
    This script finds those unused copies and, with -Apply, removes them.

    Usage: put it in the game folder (or its Tools folder), open PowerShell there and run
        powershell -ExecutionPolicy Bypass -File .\LodDedup.ps1           # report only
        powershell -ExecutionPolicy Bypass -File .\LodDedup.ps1 -Apply    # remove them

    The report is written to LodDedupReport.txt in the game folder.
    With -Apply every archive that changes is first moved to Data\LodDedupBackup_<date>,
    and the new archive is checked before it takes its place. To undo, copy the archives
    back from that folder. Close the game and the editor before running it.

    Left alone: the UI layout archives (*.icons.UI.lod), editor.* archives (they may be
    loaded only by the editor), new.lod, and files listed twice inside one archive.
#>
param(
    [switch]$Apply,
    [string]$GameDir = ''
)
# the game folder: where the script is, or the folder above it (Tools\)
if (-not $GameDir) {
    if (Test-Path (Join-Path $PSScriptRoot 'Data')) { $GameDir = $PSScriptRoot } else { $GameDir = Split-Path -Parent $PSScriptRoot }
}

$ErrorActionPreference = 'Stop'
$Latin1 = [Text.Encoding]::GetEncoding(28591)
$DataDir = Join-Path $GameDir 'Data'
if (-not (Test-Path $DataDir)) { throw "No Data folder in $GameDir" }

# kind of archive: the original one and the pattern of the custom ones
$Kinds = @(
    @{ Kind = 'bitmaps';     Base = 'bitmaps.lod';  Pattern = '*.bitmaps.lod' },
    @{ Kind = 'icons';       Base = 'icons.lod';    Pattern = '*.icons.lod' },
    @{ Kind = 'sprites';     Base = 'sprites.lod';  Pattern = '*.sprites.lod' },
    @{ Kind = 'games';       Base = 'games.lod';    Pattern = '*.games.lod' },
    @{ Kind = 'text (T)';    Base = 'EnglishT.lod'; Pattern = '*.T.lod' },
    @{ Kind = 'data (D)';    Base = 'EnglishD.lod'; Pattern = '*.D.lod' },
    @{ Kind = 'HD bitmaps';  Base = 'bitmaps.lwd';  Pattern = '*.bitmaps.lwd' }
)

function Read-U32([byte[]]$b, [int]$o) { [BitConverter]::ToUInt32($b, $o) }

# reads the header and the directory of an archive
function Read-Lod([string]$path) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'Read')
    try {
        $len = $fs.Length
        if ($len -lt 0x120) { return $null }
        $hdr = New-Object byte[] 0x120
        [void]$fs.Read($hdr, 0, 0x120)
        if ($Latin1.GetString($hdr, 0, 3) -ne 'LOD') { return $null }
        $ver = $Latin1.GetString($hdr, 4, 6)
        $dirStart = Read-U32 $hdr 0x110
        $count = Read-U32 $hdr 0x11C
        if ($dirStart -ne 0x120 -or $count -eq 0) { return $null }
        if ($ver -eq 'MMVIII') { $es = 0x4C; $nl = 0x40 } else { $es = 0x20; $nl = 0x10 }
        $dir = New-Object byte[] ($count * $es)
        [void]$fs.Read($dir, 0, $dir.Length)
        $entries = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $count; $i++) {
            $p = $i * $es
            $name = $Latin1.GetString($dir, $p, $nl).Split([char]0)[0]
            $off = Read-U32 $dir ($p + $nl)
            $size = Read-U32 $dir ($p + $nl + 4)
            if ($dirStart + $off + $size -gt $len) { return $null }   # not a layout we know
            $entries.Add([pscustomobject]@{ Index = $i; Name = $name; Off = $off; Size = $size })
        }
        return [pscustomobject]@{ Path = $path; File = (Split-Path -Leaf $path); Header = $hdr
            Dir = $dir; EntrySize = $es; NameLen = $nl; Entries = $entries; Length = $len }
    } finally { $fs.Close() }
}

function Read-Blob($lod, $e) {
    $fs = [IO.File]::Open($lod.Path, 'Open', 'Read', 'Read')
    try {
        $b = New-Object byte[] $e.Size
        [void]$fs.Seek(0x120 + [int64]$e.Off, 'Begin')
        $read = 0
        while ($read -lt $e.Size) { $read += $fs.Read($b, $read, $e.Size - $read) }
        return $b
    } finally { $fs.Close() }
}

# same content? (a copy of the name at the start of a file may differ in letter case)
function Same-Content($lodA, $a, $lodB, $b) {
    if ($a.Size -ne $b.Size) { return $false }
    $x = Read-Blob $lodA $a; $y = Read-Blob $lodB $b
    $nl = [Math]::Min($lodA.NameLen, $x.Length)
    $start = 0
    if ($Latin1.GetString($x, 0, $nl).ToLower() -eq $Latin1.GetString($y, 0, $nl).ToLower()) { $start = $nl }
    for ($i = $start; $i -lt $x.Length; $i++) { if ($x[$i] -ne $y[$i]) { return $false } }
    return $true
}

# writes the archive without the listed entries, then checks it
function Write-Lod($lod, $removeSet, [string]$outPath) {
    $keep = @($lod.Entries | Where-Object { -not $removeSet.Contains($_.Index) })
    $es = $lod.EntrySize; $nl = $lod.NameLen
    $dir = New-Object byte[] ($keep.Count * $es)
    $pos = [uint32]($keep.Count * $es)
    $newOff = @{}
    foreach ($e in ($keep | Sort-Object Off)) { $newOff[$e.Index] = $pos; $pos += $e.Size }
    for ($i = 0; $i -lt $keep.Count; $i++) {
        $e = $keep[$i]
        [Array]::Copy($lod.Dir, $e.Index * $es, $dir, $i * $es, $es)
        [Array]::Copy([BitConverter]::GetBytes([uint32]$newOff[$e.Index]), 0, $dir, $i * $es + $nl, 4)
    }
    $hdr = [byte[]]$lod.Header.Clone()
    [Array]::Copy([BitConverter]::GetBytes([uint32]$pos), 0, $hdr, 0x114, 4)          # size after 0x120
    [Array]::Copy([BitConverter]::GetBytes([uint32]$keep.Count), 0, $hdr, 0x11C, 4)
    $src = [IO.File]::Open($lod.Path, 'Open', 'Read', 'Read')
    $dst = [IO.File]::Open($outPath, 'Create', 'Write', 'None')
    try {
        $dst.Write($hdr, 0, $hdr.Length)
        $dst.Write($dir, 0, $dir.Length)
        $buf = New-Object byte[] (1MB)
        foreach ($e in ($keep | Sort-Object Off)) {
            [void]$src.Seek(0x120 + [int64]$e.Off, 'Begin')
            $left = [int64]$e.Size
            while ($left -gt 0) {
                $n = $src.Read($buf, 0, [int][Math]::Min($buf.Length, $left))
                if ($n -le 0) { throw "Unexpected end of $($lod.File)" }
                $dst.Write($buf, 0, $n); $left -= $n
            }
        }
    } finally { $src.Close(); $dst.Close() }
    # check: same names in the same order, same sizes, same first bytes of every file
    $chk = Read-Lod $outPath
    if (-not $chk -or $chk.Entries.Count -ne $keep.Count) { throw "Check failed for $outPath" }
    for ($i = 0; $i -lt $keep.Count; $i++) {
        $a = $keep[$i]; $b = $chk.Entries[$i]
        if ($a.Name -ne $b.Name -or $a.Size -ne $b.Size) { throw "Check failed for $outPath ($($a.Name))" }
    }
    $sample = $keep | Get-Random -Count ([Math]::Min(20, $keep.Count))
    foreach ($a in $sample) {
        $b = $chk.Entries[[array]::IndexOf($keep, $a)]
        $x = Read-Blob $lod $a; $y = Read-Blob $chk $b
        if ([Convert]::ToBase64String($x) -ne [Convert]::ToBase64String($y)) { throw "Check failed for $outPath ($($a.Name) content)" }
    }
}

$report = New-Object System.Collections.Generic.List[string]
function Say([string]$s) { $report.Add($s); Write-Host $s }

Say "LOD duplicates report, $(Get-Date -Format 'yyyy-MM-dd HH:mm')   Game folder: $GameDir"
Say ($(if ($Apply) { 'Mode: REMOVE (-Apply)' } else { 'Mode: report only (run with -Apply to remove)' }))
Say ''

$plan = @{}          # archive path -> @{ Lod; Remove = HashSet[int] }
$totalBytes = [int64]0; $totalFiles = 0
$all = Get-ChildItem -LiteralPath $DataDir -File

foreach ($k in $Kinds) {
    $base = $all | Where-Object { $_.Name -ieq $k.Base }
    $custom = @($all | Where-Object { $_.Name -like $k.Pattern -and $_.Name -notlike 'editor.*' -and $_.Name -ine $k.Base })
    $names = [string[]]@($custom | ForEach-Object { $_.Name })
    [Array]::Sort($names, [StringComparer]::OrdinalIgnoreCase)
    $order = @()
    if ($base) { $order += $base.FullName }
    $order += $names | ForEach-Object { Join-Path $DataDir $_ }
    if ($order.Count -lt 2) { continue }

    $lods = @()
    foreach ($p in $order) {
        $l = Read-Lod $p
        if ($l) { $lods += $l } else { Say "  ! skipped (not a known archive layout): $(Split-Path -Leaf $p)" }
    }
    Say "== $($k.Kind): read in this order, the last one wins =="
    $i = 0; foreach ($l in $lods) { $i++; Say ("  {0,2}. {1} ({2} files)" -f $i, $l.File, $l.Entries.Count) }

    # name -> the archive that wins, and its entry there
    $winner = @{}; $winEntry = @{}
    for ($li = 0; $li -lt $lods.Count; $li++) {
        foreach ($e in $lods[$li].Entries) { $n = $e.Name.ToLower(); $winner[$n] = $li; $winEntry[$n] = $e }
    }
    for ($li = 0; $li -lt $lods.Count; $li++) {
        $l = $lods[$li]
        $rm = New-Object 'System.Collections.Generic.HashSet[int]'
        $same = 0; $over = 0; $bytes = [int64]0; $lines = @()
        foreach ($e in $l.Entries) {
            $w = $winner[$e.Name.ToLower()]
            if ($w -le $li) { continue }
            $we = $winEntry[$e.Name.ToLower()]
            $isSame = Same-Content $l $e $lods[$w] $we
            if ($isSame) { $same++ } else { $over++ }
            [void]$rm.Add($e.Index); $bytes += $e.Size
            $lines += ("      {0,-24} {1,10:N0}  {2} in {3}" -f $e.Name, $e.Size, $(if ($isSame) { 'identical to the copy' } else { 'replaced by the copy' }), $lods[$w].File)
        }
        if ($rm.Count -gt 0 -and $rm.Count -eq $l.Entries.Count) {
            Say ("  {0}: all {1} files are replaced by later archives; left as it is (it could be deleted)" -f $l.File, $rm.Count)
        } elseif ($rm.Count -gt 0) {
            Say ("  {0}: {1} files to remove ({2} identical, {3} replaced), {4:N1} MB" -f $l.File, $rm.Count, $same, $over, ($bytes / 1MB))
            foreach ($s in $lines) { $report.Add($s) }
            $plan[$l.Path] = @{ Lod = $l; Remove = $rm }
            $totalBytes += $bytes; $totalFiles += $rm.Count
        }
    }
    Say ''
}

Say ("Total: {0} files, {1:N1} MB" -f $totalFiles, ($totalBytes / 1MB))

if ($Apply -and $plan.Count -gt 0) {
    $backup = Join-Path $DataDir ('LodDedupBackup_' + (Get-Date -Format 'yyyyMMdd_HHmm'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Say ''
    Say "Backups of the changed archives: $backup"
    foreach ($p in $plan.Keys) {
        $item = $plan[$p]
        $tmp = $p + '.dedup'
        try {
            # the game or the editor must not have it open
            $t = [IO.File]::Open($p, 'Open', 'ReadWrite', 'None'); $t.Close()
            Write-Lod $item.Lod $item.Remove $tmp
            Move-Item -LiteralPath $p -Destination (Join-Path $backup (Split-Path -Leaf $p))
            Move-Item -LiteralPath $tmp -Destination $p
            Say ("  done: {0}  {1:N1} MB -> {2:N1} MB" -f (Split-Path -Leaf $p), ($item.Lod.Length / 1MB), ((Get-Item -LiteralPath $p).Length / 1MB))
        } catch {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp }
            Say "  NOT changed: $(Split-Path -Leaf $p): $($_.Exception.Message)"
        }
    }
}

$reportPath = Join-Path $GameDir 'LodDedupReport.txt'
[IO.File]::WriteAllLines($reportPath, $report)
Write-Host "Report: $reportPath"
