<#
.SYNOPSIS
    clippingfixer - 把 Cyberpunk 2077 服装包里的身材模板钉死为指定身材（默认 ANGEL），
    解决“穿鞋 / 穿脚模后胸臀顶穿”的穿模问题。

.DESCRIPTION
    原理：很多服装包的实体里写的是动态网格路径模板，例如
        *mod\item\item_{gender}_{body}.mesh      (Tony 系)
        *mod\item\item_{body}.mesh              (Lirael / Subleader 系)
    {body} 在运行时由 PuppetStateSystem 解析。实测装了 HystAngel 等身材 mod 后，
    它经常解析成 BaseBody，于是衣服取到原版身材的网格 -> 胸/臀被顶穿。
    本工具把这些模板直接替换成本包内已存在的 ANGEL 网格（item_w_angel.mesh / item_angel.mesh），
    不再依赖运行时解析。

    处理流程：解包 -> 改 ent -> 回写 CR2W -> 重打包 -> 校验条目数 -> 备份原包 -> 安装。
    会同时覆盖三处可能存在的同一文件：mods\...\archives、archive\pc\mod、Vortex 暂存区。

.PARAMETER Mode
    scan   只扫描并输出报告（默认，不动任何文件）
    apply  实际修改并安装（必须同时给 -Apply）
    revert 按 manifest 回滚
    verify 校验当前文件与 manifest 是否一致

.PARAMETER Filter
    只处理文件名匹配该通配符的 archive，例如 -Filter 'tony_*'。
    scan 全量很慢（WolvenKit 解包是按整包扫描的），建议先用 -Filter 缩小范围。

.EXAMPLE
    .\clippingfixer.ps1 -Mode scan -Filter 'tony_*'
    .\clippingfixer.ps1 -Mode apply -Apply -Filter 'tony_*'
    .\clippingfixer.ps1 -Mode apply -Apply -Only tony_goth_girl_outfit_3.archive
    .\clippingfixer.ps1 -Mode verify
    .\clippingfixer.ps1 -Mode revert
#>
[CmdletBinding()]
param(
    [ValidateSet('scan','apply','revert','verify')]
    [string]$Mode = 'scan',
    [string]$Config = '',
    [string]$Only = '',
    [string]$Filter = '*',
    [switch]$Apply,
    [switch]$NoCache,
    [string]$BackupDir = '',
    [string]$ReportDir = '',
    [string]$WorkDir   = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Config)    { $Config    = Join-Path $scriptRoot 'config.json' }
if (-not $BackupDir) { $BackupDir = Join-Path $scriptRoot 'backup' }
if (-not $ReportDir) { $ReportDir = Join-Path $scriptRoot 'reports' }
if (-not $WorkDir)   { $WorkDir   = Join-Path $scriptRoot '.work' }

$script:started = Get-Date
$script:logPath = Join-Path $ReportDir ('clippingfixer-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

function Log($msg) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg)
    Write-Host $line
    Add-Content -LiteralPath $script:logPath -Value $line -Encoding UTF8
}

# ---------------------------------------------------------------- config
if (-not (Test-Path -LiteralPath $Config)) { throw "找不到配置文件：$Config（可从 config.example.json 复制一份）" }
$cfg = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json

$game   = $cfg.gamePath
$stage  = $cfg.stagePath
$cli    = $cfg.wolvenkit
$dotnet = $cfg.dotnetRoot
$bodyTag = if ($cfg.bodyTag) { $cfg.bodyTag } else { 'angel' }
$candidates = @($cfg.meshCandidates)
if (-not $candidates -or $candidates.Count -eq 0) { $candidates = @(('_w_' + $bodyTag), ('_' + $bodyTag)) }

if (-not (Test-Path -LiteralPath $cli)) { throw "WolvenKit CLI 不存在：$cli" }
if ($dotnet -and (Test-Path -LiteralPath $dotnet)) { $env:DOTNET_ROOT = $dotnet }

New-Item -ItemType Directory -Force -Path $BackupDir, $ReportDir, $WorkDir | Out-Null
$manifestPath = Join-Path $BackupDir 'manifest.json'
$cachePath    = Join-Path $BackupDir 'scan-cache.json'

function Invoke-Wk {
    param([string[]]$ArgList)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @()
    try { $out = & $cli @ArgList 2>&1 } catch { $out = @($_.Exception.Message) } finally { $ErrorActionPreference = $prev }
    return @($out | ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'Long path support is disabled' })
}

function Get-ArchiveEntries {
    param([string]$Arc)
    return @(Invoke-Wk @('archive', $Arc, '-l') | Where-Object { "$_" -match '\\' } | ForEach-Object { "$_".Trim() })
}

function Get-TemplateCandidates {
    param([string]$RawValue)
    $plain = $RawValue.TrimStart('*')
    $res = New-Object System.Collections.Generic.List[string]
    foreach ($c in $script:candidates) {
        if ($plain -match '\{gender\}_\{body\}') { $res.Add(($plain -replace '\{gender\}_\{body\}', $c)) }
        if ($plain -match '\{body\}')          { $res.Add(($plain -replace '\{body\}', $c)) }
    }
    return ,$res
}

function Find-ArchiveFiles {
    $list = New-Object System.Collections.Generic.List[object]
    $modsRoot = Join-Path $game 'mods'
    if (Test-Path -LiteralPath $modsRoot) {
        Get-ChildItem -LiteralPath $modsRoot -Recurse -Filter '*.archive' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match '\\archives?$' } |
            ForEach-Object { $list.Add([pscustomobject]@{ File = $_; Kind = 'mods' }) }
    }
    $legacy = Join-Path $game 'archive\pc\mod'
    if (Test-Path -LiteralPath $legacy) {
        Get-ChildItem -LiteralPath $legacy -Filter '*.archive' -File -ErrorAction SilentlyContinue |
            ForEach-Object { $list.Add([pscustomobject]@{ File = $_; Kind = 'legacy' }) }
    }
    return ,$list
}

function Get-StagingCopies {
    param([string]$Name)
    if (-not $stage -or -not (Test-Path -LiteralPath $stage)) { return @() }
    return @(Get-ChildItem -LiteralPath $stage -Recurse -Filter $Name -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
}

function Get-ArchiveKey {
    param($FileInfo)
    return ('{0}|{1}|{2}' -f $FileInfo.FullName, $FileInfo.Length, $FileInfo.LastWriteTimeUtc.Ticks)
}

function Read-Cache {
    if ($NoCache) { return @{} }
    if (-not (Test-Path -LiteralPath $cachePath)) { return @{} }
    $obj = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $h = @{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

function Write-Cache($cache) {
    if ($NoCache) { return }
    $cache | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cachePath -Encoding UTF8
}

function Test-IsPatched {
    param([string]$Arc)
    $work = Join-Path $WorkDir ('probe_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        Invoke-Wk @('unbundle', $Arc, '-o', $work, '-w', '*.ent') | Out-Null
        foreach ($e in (Get-ChildItem $work -Recurse -Include '*.ent' -File -ErrorAction SilentlyContinue)) {
            Invoke-Wk @('convert', 'serialize', $e.FullName) | Out-Null
            $j = $e.FullName + '.json'
            if (Test-Path -LiteralPath $j) {
                if ([IO.File]::ReadAllText($j) -match '\{body\}') { return 'needs-fix' }
                Remove-Item $j -Force -ErrorAction SilentlyContinue
            }
        }
        return 'already-fixed'
    } finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-ArchiveState {
    param($FileInfo)
    $work = Join-Path $WorkDir ('scan_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $entries = Get-ArchiveEntries $FileInfo.FullName
        $entrySet = @{}
        foreach ($en in $entries) { $entrySet[$en.ToLower()] = $true }
        Invoke-Wk @('unbundle', $FileInfo.FullName, '-o', $work, '-w', '*.ent') | Out-Null
        $fixable = 0; $needRefit = 0; $refs = 0
        foreach ($e in (Get-ChildItem $work -Recurse -Include '*.ent' -File -ErrorAction SilentlyContinue)) {
            Invoke-Wk @('convert', 'serialize', $e.FullName) | Out-Null
            $j = $e.FullName + '.json'
            if (-not (Test-Path -LiteralPath $j)) { continue }
            $txt = [IO.File]::ReadAllText($j)
            foreach ($m in [regex]::Matches($txt, '"\$value":\s*"([^"]*\{body\}[^"]*)"')) {
                $refs++
                $ok = $false
                foreach ($c in (Get-TemplateCandidates $m.Groups[1].Value)) {
                    $fs = ($c -replace '\\\\', '\').ToLower()
                    if ($entrySet.ContainsKey($fs)) { $ok = $true; break }
                }
                if ($ok) { $fixable++ } else { $needRefit++ }
            }
            Remove-Item $j -Force -ErrorAction SilentlyContinue
        }
        $state = if ($refs -eq 0) { 'clean' } elseif ($fixable -gt 0) { 'fixable' } else { 'needs-review' }
        return [pscustomobject]@{ State = $state; Refs = $refs; Fixable = $fixable; NeedRefit = $needRefit; Entries = $entries.Count }
    } finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------- scan
function Invoke-Scan {
    $cache = Read-Cache
    $rows = New-Object System.Collections.Generic.List[object]
    $archives = Find-ArchiveFiles | Where-Object { $_.File.Name -like $Filter }
    Log ("扫描 " + $archives.Count + " 个 archive（filter=" + $Filter + "）")
    foreach ($a in $archives) {
        $name = $a.File.Name
        if ($Only -and $name -ne $Only) { continue }
        $key = Get-ArchiveKey $a.File
        try {
            if ($cache.ContainsKey($key)) {
                $r = $cache[$key]
                Log ("cached  " + $name + "  " + $r.State)
            } else {
                $r = Get-ArchiveState $a.File
                $cache[$key] = [pscustomobject]@{ State=$r.State; Refs=$r.Refs; Fixable=$r.Fixable; NeedRefit=$r.NeedRefit; Entries=$r.Entries }
            }
            if ($r.State -ne 'clean' -or $Only) {
                $rows.Add([pscustomobject]@{
                    Archive = $name; Kind = $a.Kind; Entries = $r.Entries
                    Refs = $r.Refs; Fixable = $r.Fixable; NeedRefit = $r.NeedRefit
                    State = $r.State; Path = $a.File.FullName
                })
                Log ("{0,-12} {1,-38} refs={2} fixable={3} needRefit={4}" -f $r.State, $name, $r.Refs, $r.Fixable, $r.NeedRefit)
            }
        } catch {
            Log ("扫描失败 " + $name + " : " + $_.Exception.Message)
        }
    }
    Write-Cache $cache
    $csv = Join-Path $ReportDir ('scan-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv')
    $rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    Log ("报告已写入 " + $csv)
}

# ---------------------------------------------------------------- apply
function Invoke-Apply {
    if (-not $Apply) { throw "apply 模式必须显式加 -Apply（避免误改）" }
    if (-not (Test-Path -LiteralPath $manifestPath)) { '[]' | Set-Content -LiteralPath $manifestPath -Encoding UTF8 }
    $manifest = @(Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $cache = Read-Cache

    $targets = Find-ArchiveFiles | Where-Object { $_.Kind -eq 'mods' -and $_.File.Name -like $Filter }
    foreach ($t in $targets) {
        $arcPath = $t.File.FullName
        $name = $t.File.Name
        if ($Only -and $name -ne $Only) { continue }
        $key = Get-ArchiveKey $t.File
        $state = if ($cache.ContainsKey($key)) { $cache[$key].State } else { Test-IsPatched $arcPath }
        if ($state -ne 'fixable' -and $state -ne 'needs-fix') { Log ("跳过（" + $state + "）：" + $name); continue }

        Log ("处理 " + $name)
        $base = [IO.Path]::GetFileNameWithoutExtension($name)
        $work = Join-Path $WorkDir $base
        $out  = Join-Path $WorkDir ('out_' + $base)
        Remove-Item $work, $out -Recurse -Force -ErrorAction SilentlyContinue

        $origEntries = (Get-ArchiveEntries $arcPath).Count
        Invoke-Wk @('unbundle', $arcPath, '-o', $work) | Out-Null
        if (-not (Test-Path -LiteralPath $work)) { Log ("解包失败：" + $name); continue }

        $patched = 0; $refs = 0
        foreach ($e in (Get-ChildItem $work -Recurse -Include '*.ent','*.app' -File -ErrorAction SilentlyContinue)) {
            Invoke-Wk @('convert', 'serialize', $e.FullName) | Out-Null
            $j = $e.FullName + '.json'
            if (-not (Test-Path -LiteralPath $j)) { continue }
            $txt = [IO.File]::ReadAllText($j)
            if ($txt -notmatch '\{body\}') { Remove-Item $j -Force; continue }
            $hit = 0
            foreach ($m in [regex]::Matches($txt, '"\$value":\s*"([^"]*\{body\}[^"]*)"')) {
                $refs++
                foreach ($c in (Get-TemplateCandidates $m.Groups[1].Value)) {
                    $fs = Join-Path $work ($c -replace '\\\\', '\')
                    if (Test-Path -LiteralPath $fs) { $txt = $txt.Replace($m.Groups[1].Value, $c); $hit++; break }
                }
            }
            if ($hit -gt 0) {
                [IO.File]::WriteAllText($j, $txt)
                Invoke-Wk @('convert', 'deserialize', $j) | Out-Null
                $patched += $hit
            }
            Remove-Item $j -Force -ErrorAction SilentlyContinue
        }
        if ($patched -eq 0) {
            Log ("无可替换引用（包内没有 ANGEL 网格，需要先 refit）：" + $name)
            Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }

        Invoke-Wk @('pack', $work, '-o', $out) | Out-Null
        $newArc = Join-Path $out $name
        if (-not (Test-Path -LiteralPath $newArc)) { Log ("打包失败：" + $name); continue }
        $newEntries = (Get-ArchiveEntries $newArc).Count
        if ($newEntries -ne $origEntries) {
            Log ("条目数不一致，放弃：" + $name + "  " + $newEntries + "/" + $origEntries)
            Remove-Item $work, $out -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }

        $origHash = (Get-FileHash $arcPath -Algorithm SHA256).Hash
        $backupFile = Join-Path $BackupDir $name
        if (-not (Test-Path -LiteralPath $backupFile)) { Copy-Item $arcPath $backupFile -Force }
        $newHash = (Get-FileHash $newArc -Algorithm SHA256).Hash

        $installPaths = New-Object System.Collections.Generic.List[string]
        $installPaths.Add($arcPath)
        $legacyCopy = Join-Path (Join-Path $game 'archive\pc\mod') $name
        if (Test-Path -LiteralPath $legacyCopy) { $installPaths.Add($legacyCopy) }
        foreach ($s in (Get-StagingCopies $name)) { $installPaths.Add($s) }

        foreach ($p in $installPaths) {
            try { Copy-Item $newArc $p -Force; Log ("  已安装 " + $p) }
            catch { Log ("  安装失败 " + $p + " : " + $_.Exception.Message) }
        }

        $manifest += [pscustomobject]@{
            archive = $name; backup = $backupFile
            originalSha256 = $origHash; patchedSha256 = $newHash
            paths = @($installPaths); bodyTag = $script:bodyTag
            patchedRefs = $patched; refsSeen = $refs
            date = (Get-Date -Format 'o')
        }
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        if ($cache.ContainsKey($key)) { $cache[$key].State = 'clean'; $cache[$key].Fixable = 0 }
        Remove-Item $work, $out -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Cache $cache
    Log ("manifest: " + $manifestPath)
}

# ---------------------------------------------------------------- revert / verify
function Get-Manifest {
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "没有 manifest：$manifestPath" }
    return @(Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Invoke-Revert {
    foreach ($m in (Get-Manifest)) {
        if ($Only -and $m.archive -ne $Only) { continue }
        if (-not $m.backup -or -not (Test-Path -LiteralPath $m.backup)) { Log ("备份缺失：" + $m.archive); continue }
        foreach ($p in @($m.paths)) {
            if (Test-Path -LiteralPath $p) { Copy-Item $m.backup $p -Force; Log ("  已还原 " + $p) }
        }
    }
    Log '回滚完成'
}

function Invoke-Verify {
    $bad = 0
    foreach ($m in (Get-Manifest)) {
        $first = @($m.paths)[0]
        if (-not (Test-Path -LiteralPath $first)) { Log ("缺失：" + $first); $bad++; continue }
        $h = (Get-FileHash $first -Algorithm SHA256).Hash
        if ($h -ne $m.patchedSha256) { Log ("不一致：" + $m.archive); $bad++ } else { Log ("OK " + $m.archive) }
    }
    Log ("校验完成，异常 " + $bad + " 项")
}

# ---------------------------------------------------------------- main
Log ('clippingfixer · mode=' + $Mode + ' · bodyTag=' + $bodyTag + ' · filter=' + $Filter)
switch ($Mode) {
    'scan'   { Invoke-Scan }
    'apply'  { Invoke-Apply }
    'revert' { Invoke-Revert }
    'verify' { Invoke-Verify }
}
Log ('用时 ' + [math]::Round(((Get-Date) - $script:started).TotalSeconds, 1) + ' 秒')
