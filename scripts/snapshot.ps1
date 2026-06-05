<#
.SYNOPSIS
拍一份 WezTerm 会话快照：窗口/tab/pane 布局 + 每个 pane 跑的 agent(claude/codex) + 匹配到的 session id。
用于 WezTerm 崩溃后复原（配合 restore.ps1）。

布局只能在 wezterm 健康时抓；wezterm 没响应时本脚本仍会写出 claude/codex 的 session 索引
（这些在磁盘上，崩溃后也读得到），并把 weztermAvailable 标记为 false。

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/snapshot.ps1

.EXAMPLE
# 只扫最近 1 天的 session
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/snapshot.ps1 -RecentDays 1
#>
[CmdletBinding()]
param(
    # 快照输出目录，默认 <工程>/snapshots
    [string]$OutDir,
    # 只把最近 N 天内活跃过的 session 纳入索引（控制扫描量）
    [ValidateRange(1, 365)]
    [int]$RecentDays = 3,
    # 等待 wezterm cli list 的最长秒数；超时视为 wezterm 未响应
    [ValidateRange(2, 60)]
    [int]$WezTimeoutSeconds = 8
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) "snapshots"
}

$claudeRoot = Join-Path $HOME ".claude\projects"
$codexRoot = Join-Path $HOME ".codex\sessions"
$cutoff = (Get-Date).AddDays(-$RecentDays)

# ---------- 工具函数 ----------

function ConvertTo-LocalPath {
    # 把 wezterm 的 cwd（可能是 file://HOST/C:/path 这种 OSC7 URL）转成 C:\path
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }

    $v = $Value
    if ($v -like "file://*") {
        $rest = $v.Substring("file://".Length)
        # 去掉 authority（host）：取第一个 '/' 之后的部分
        $slash = $rest.IndexOf('/')
        if ($slash -ge 0) { $rest = $rest.Substring($slash + 1) }
        try { $rest = [System.Uri]::UnescapeDataString($rest) } catch { }
        $v = $rest
    }

    $v = $v -replace '/', '\'
    return $v
}

function Get-NormalizedPathKey {
    # 用于 cwd 比较的规范化 key：小写、反斜杠、去尾部斜杠
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $p = (ConvertTo-LocalPath $Path)
    $p = $p -replace '/', '\'
    $p = $p.TrimEnd('\')
    return $p.ToLowerInvariant()
}

function Get-CwdFromJsonl {
    # 从 jsonl 头部若干行里抠出第一个 "cwd" 值（值里的 \\ 会被还原成 \）
    param([string]$FilePath)

    try {
        $head = Get-Content -LiteralPath $FilePath -TotalCount 40 -Encoding UTF8 -ErrorAction Stop
    } catch {
        return ""
    }

    foreach ($line in $head) {
        $m = [regex]::Match($line, '"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"')
        if ($m.Success) {
            $raw = $m.Groups[1].Value
            return ($raw -replace '\\\\', '\' -replace '\\/', '/')
        }
    }
    return ""
}

function Get-GuidFromName {
    param([string]$Name)
    $m = [regex]::Match($Name, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if ($m.Success) { return $m.Value }
    return [System.IO.Path]::GetFileNameWithoutExtension($Name)
}

function Get-ClaudeSessions {
    if (-not (Test-Path -LiteralPath $claudeRoot)) { return @() }

    $files = Get-ChildItem -LiteralPath $claudeRoot -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $cutoff }

    $out = foreach ($f in $files) {
        [pscustomobject]@{
            agent        = "claude"
            sessionId    = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            cwd          = (Get-CwdFromJsonl $f.FullName)
            lastActive   = $f.LastWriteTime.ToString("o")
            lastActiveMs = [int64]($f.LastWriteTime - [datetime]'1970-01-01').TotalMilliseconds
            sizeBytes    = $f.Length
            file         = $f.FullName
            resumeCmd    = "claude --resume $([System.IO.Path]::GetFileNameWithoutExtension($f.Name))"
        }
    }
    return @($out | Sort-Object -Property lastActiveMs -Descending)
}

function Get-CodexSessions {
    if (-not (Test-Path -LiteralPath $codexRoot)) { return @() }

    $files = Get-ChildItem -LiteralPath $codexRoot -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $cutoff }

    $out = foreach ($f in $files) {
        $id = Get-GuidFromName $f.Name
        [pscustomobject]@{
            agent        = "codex"
            sessionId    = $id
            cwd          = (Get-CwdFromJsonl $f.FullName)
            lastActive   = $f.LastWriteTime.ToString("o")
            lastActiveMs = [int64]($f.LastWriteTime - [datetime]'1970-01-01').TotalMilliseconds
            sizeBytes    = $f.Length
            file         = $f.FullName
            resumeCmd    = "codex resume $id"
        }
    }
    return @($out | Sort-Object -Property lastActiveMs -Descending)
}

function Invoke-WezTermList {
    # 在后台进程里跑 wezterm cli list，带超时；wezterm 冻死时快速失败而不是挂住
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wezterm"
    $psi.Arguments = "cli list --format json"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEndAsync()
    if (-not $p.WaitForExit($WezTimeoutSeconds * 1000)) {
        try { $p.Kill() } catch { }
        return $null
    }
    if ($p.ExitCode -ne 0) { return $null }

    $text = $stdout.Result
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return @($text | ConvertFrom-Json) } catch { return $null }
}

function Set-WezTermSocketEnv {
    # 不在 wezterm pane 里运行时（如计划任务），环境没有 WEZTERM_UNIX_SOCKET，
    # wezterm cli 找不到 GUI 的控制 socket 就会连不上。这里自动找到运行中
    # wezterm-gui 对应的 gui-sock-<pid> 文件并设置它，让 cli 能连上。
    if ($env:WEZTERM_UNIX_SOCKET -and (Test-Path -LiteralPath $env:WEZTERM_UNIX_SOCKET)) { return }
    $dir = Join-Path $HOME ".local\share\wezterm"
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $guiPids = @(Get-Process wezterm-gui -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $cands = @(Get-ChildItem -LiteralPath $dir -Filter "gui-sock-*" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $pick = $null
    foreach ($c in $cands) {
        $sockPid = $c.Name -replace 'gui-sock-', ''
        if ($sockPid -match '^\d+$' -and $guiPids -contains [int]$sockPid) { $pick = $c; break }
    }
    if (-not $pick -and $cands.Count -gt 0) { $pick = $cands[0] }
    if ($pick) { $env:WEZTERM_UNIX_SOCKET = $pick.FullName }
}

# ---------- 采集 ----------

$claudeSessions = @(Get-ClaudeSessions)
$codexSessions = @(Get-CodexSessions)
$allSessions = @($claudeSessions) + @($codexSessions)

function Find-SessionsForCwd {
    param([string]$Cwd, [string]$Agent)
    $key = Get-NormalizedPathKey $Cwd
    if ([string]::IsNullOrEmpty($key)) { return @() }
    $matches = $allSessions | Where-Object {
        $_.agent -eq $Agent -and (Get-NormalizedPathKey $_.cwd) -eq $key
    }
    return @($matches | Sort-Object -Property lastActiveMs -Descending)
}

Set-WezTermSocketEnv
$rawPanes = Invoke-WezTermList
$weztermAvailable = $null -ne $rawPanes

$windows = @()
if ($weztermAvailable) {
    $byWindow = $rawPanes | Group-Object -Property window_id | Sort-Object { [int]$_.Name }
    foreach ($w in $byWindow) {
        $tabs = @()
        # 不要按 tab_id 排！tab_id 是创建顺序，不是用户拖动后的可视顺序。
        # wezterm cli list 的行顺序 == 标签栏可视顺序，Group-Object 默认保留首次出现顺序，
        # 所以这里保持原顺序即为可视顺序（之前按 tab_id 排会把拖动顺序丢掉）。
        $byTab = $w.Group | Group-Object -Property tab_id
        foreach ($t in $byTab) {
            $panes = @()
            foreach ($pane in ($t.Group | Sort-Object top_row, left_col, pane_id)) {
                $cwd = ConvertTo-LocalPath ([string]$pane.cwd)
                $title = [string]$pane.title

                $claudeCand = @(Find-SessionsForCwd -Cwd $cwd -Agent "claude")
                $codexCand = @(Find-SessionsForCwd -Cwd $cwd -Agent "codex")

                # agent 推断：标题关键字优先，其次看哪个 store 在该 cwd 下最近活跃
                $agent = "unknown"
                if ($title -match '(?i)codex') { $agent = "codex" }
                elseif ($title -match '(?i)claude') { $agent = "claude" }
                else {
                    $cTop = if ($claudeCand.Count) { $claudeCand[0].lastActiveMs } else { 0 }
                    $xTop = if ($codexCand.Count) { $codexCand[0].lastActiveMs } else { 0 }
                    if ($cTop -eq 0 -and $xTop -eq 0) { $agent = "shell" }
                    elseif ($xTop -gt $cTop) { $agent = "codex" }
                    else { $agent = "claude" }
                }

                $best = $null
                if ($agent -eq "claude" -and $claudeCand.Count) { $best = $claudeCand[0] }
                elseif ($agent -eq "codex" -and $codexCand.Count) { $best = $codexCand[0] }

                $panes += [pscustomobject]@{
                    paneId          = [int]$pane.pane_id
                    cwd             = $cwd
                    title           = $title
                    workspace       = [string]$pane.workspace
                    size            = $pane.size
                    geometry        = [pscustomobject]@{ leftCol = [int]$pane.left_col; topRow = [int]$pane.top_row }
                    agent           = $agent
                    bestSessionId   = if ($best) { $best.sessionId } else { $null }
                    bestResumeCmd   = if ($best) { $best.resumeCmd } else { $null }
                    claudeCandidates = @($claudeCand | Select-Object sessionId, lastActive, resumeCmd)
                    codexCandidates  = @($codexCand | Select-Object sessionId, lastActive, resumeCmd)
                    raw             = $pane
                }
            }
            $tabs += [pscustomobject]@{
                tabId = [int]$t.Name
                panes = @($panes)
            }
        }
        $windows += [pscustomobject]@{
            windowId = [int]$w.Name
            tabs     = @($tabs)
        }
    }
}

$snapshot = [pscustomobject]@{
    capturedAt       = (Get-Date).ToString("o")
    weztermAvailable = $weztermAvailable
    note             = if ($weztermAvailable) { "ok" } else { "wezterm 未响应：本次只记录了磁盘上的 session 索引，未能采集 tab 布局。" }
    windows          = @($windows)
    sessionIndex     = [pscustomobject]@{
        recentDays = $RecentDays
        claude     = @($claudeSessions | Select-Object sessionId, cwd, lastActive, resumeCmd, file)
        codex      = @($codexSessions  | Select-Object sessionId, cwd, lastActive, resumeCmd, file)
    }
}

# ---------- 写出 ----------

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$jsonPath = Join-Path $OutDir "wezterm-$stamp.json"
$latestPath = Join-Path $OutDir "latest.json"

$json = $snapshot | ConvertTo-Json -Depth 12
Set-Content -LiteralPath $jsonPath -Value $json -Encoding UTF8
Set-Content -LiteralPath $latestPath -Value $json -Encoding UTF8

# 保留最近 288 份（5 分钟一份约等于最近 24 小时），其余删除，防止无限堆积。
$keep = 288
$old = Get-ChildItem -LiteralPath $OutDir -Filter "wezterm-*.json" -File |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip $keep
foreach ($o in $old) { Remove-Item -LiteralPath $o.FullName -Force -ErrorAction SilentlyContinue }

$paneCount = ($windows | ForEach-Object { $_.tabs } | ForEach-Object { $_.panes } | Measure-Object).Count
[pscustomobject]@{
    snapshot         = $jsonPath
    latest           = $latestPath
    weztermAvailable = $weztermAvailable
    windows          = $windows.Count
    panes            = $paneCount
    claudeSessions   = $claudeSessions.Count
    codexSessions    = $codexSessions.Count
} | ConvertTo-Json
