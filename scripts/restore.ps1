<#
.SYNOPSIS
按快照全自动复原 WezTerm 会话：重建窗口/tab/分屏，每个 pane 切到原 cwd 并自动 resume
对应的 claude / codex session。

前提：当前 wezterm 必须是健康（能响应 cli）的新实例——崩溃后先重开 wezterm，再跑本脚本。
快照必须是 wezterm 健康时抓的（weztermAvailable=true），否则没有布局可重建。

.EXAMPLE
# 全自动复原最新快照
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/restore.ps1

.EXAMPLE
# 只预览要做什么，不实际执行
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/restore.ps1 -WhatIf

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/restore.ps1 -Snapshot snapshots/wezterm-20260602-120000.json
#>
[CmdletBinding()]
param(
    # 要复原的快照文件，默认 <工程>/snapshots/latest.json
    [string]$Snapshot,
    # 只打印计划不执行
    [switch]$WhatIf,
    # 复原后 resume 命令之间的间隔秒数，给 agent 启动留时间
    [ValidateRange(0, 30)]
    [int]$StepDelaySeconds = 1
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$snapDir = Join-Path (Split-Path -Parent $PSScriptRoot) "snapshots"
if (-not $Snapshot) {
    # 默认挑“最近一份带布局(weztermAvailable=true)的快照”，而不是 latest.json——
    # 崩溃后定时任务仍在跑，最新几份很可能是 wezterm 已冻死、没布局的快照。
    $candidates = Get-ChildItem -LiteralPath $snapDir -Filter "wezterm-*.json" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    foreach ($c in $candidates) {
        try { $d = Get-Content -Raw -Encoding UTF8 -LiteralPath $c.FullName | ConvertFrom-Json } catch { continue }
        if ($d.weztermAvailable) { $Snapshot = $c.FullName; break }
    }
    if (-not $Snapshot) {
        # 没有任何带布局的快照：退回 latest.json（下面会给出明确提示）
        $Snapshot = Join-Path $snapDir "latest.json"
    }
}

if (-not (Test-Path -LiteralPath $Snapshot)) {
    throw "找不到快照文件：$Snapshot"
}

Write-Host "使用快照：$Snapshot"
$data = Get-Content -Raw -Encoding UTF8 -LiteralPath $Snapshot | ConvertFrom-Json

if (-not $data.weztermAvailable) {
    Write-Host "这份快照抓取时 wezterm 没响应，没有 tab 布局可重建（capturedAt=$($data.capturedAt)）。" -ForegroundColor Yellow
    Write-Host "请改用一份 wezterm 健康时抓的快照；磁盘上的 session 索引仍可在 sessionIndex 字段里查到。"
    return
}

$windows = @($data.windows)
if ($windows.Count -eq 0) {
    Write-Host "快照里没有窗口，无需复原。"
    return
}

# ---------- wezterm 调用封装 ----------

function Invoke-Wez {
    param([string[]]$WezArgs, [int]$TimeoutMs = 15000)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wezterm"
    $psi.Arguments = ($WezArgs -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutMs)) {
        try { $p.Kill() } catch { }
        throw "wezterm $($psi.Arguments) 超时未返回（wezterm 是否健康？）"
    }
    if ($p.ExitCode -ne 0) {
        throw "wezterm $($psi.Arguments) 失败：$($errTask.Result)"
    }
    return $outTask.Result.Trim()
}

function Set-WezTermSocketEnv {
    # 不在 wezterm pane 里运行时没有 WEZTERM_UNIX_SOCKET，cli 连不上 GUI。
    # 自动找到运行中 wezterm-gui 的 gui-sock-<pid> 并设置它。
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

function Get-CleanCwd {
    # 去掉结尾的反斜杠/斜杠：--cwd "D:\path\" 末尾的 \" 会被 Windows 命令行解析当成转义引号，
    # 把参数搞坏，pane 退回家目录。盘符根（如 D:\）要保留一个反斜杠。
    param([string]$Cwd)
    if (-not $Cwd) { return $Cwd }
    $c = $Cwd -replace '[\\/]+$', ''
    if ($c -match '^[A-Za-z]:$') { $c = "$c\" }
    return $c
}

function Spawn-Pane {
    # 返回新 pane 的 id（int）。$Parent 取 'new-window' / 'window:<id>'
    param([string]$Parent, [string]$Cwd)

    $args = @("cli", "spawn")
    if ($Parent -eq "new-window") {
        $args += "--new-window"
    } elseif ($Parent -like "window:*") {
        $args += @("--window-id", $Parent.Substring("window:".Length))
    }
    if ($Cwd) { $args += @("--cwd", "`"$(Get-CleanCwd $Cwd)`"") }

    $out = Invoke-Wez -WezArgs $args
    return [int]($out -replace '\D', '')
}

function Split-FromPane {
    param([int]$PaneId, [string]$Cwd)
    # --right：新 pane 出现在右侧，配合 pane 按 leftCol 升序处理 => 左→右排布（用户惯用 coder|reviewer 左右分屏）。
    $args = @("cli", "split-pane", "--right", "--pane-id", "$PaneId")
    if ($Cwd) { $args += @("--cwd", "`"$(Get-CleanCwd $Cwd)`"") }
    $out = Invoke-Wez -WezArgs $args
    return [int]($out -replace '\D', '')
}

function Get-WindowIdOfPane {
    param([int]$PaneId)
    $list = Invoke-Wez -WezArgs @("cli", "list", "--format", "json") | ConvertFrom-Json
    $row = @($list | Where-Object { [int]$_.pane_id -eq $PaneId } | Select-Object -First 1)
    if ($row.Count -eq 0) { return $null }
    return [int]$row[0].window_id
}

function Send-Resume {
    param([int]$PaneId, [string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return }
    Invoke-Wez -WezArgs @("cli", "send-text", "--pane-id", "$PaneId", "--no-paste", "`"$Command`"") | Out-Null
    Invoke-Wez -WezArgs @("cli", "send-text", "--pane-id", "$PaneId", "--no-paste", "`"`r`"") | Out-Null
}

# 为每个 (role|cwd) 维护一个去重的候选会话队列（按近活降序）+ 消费指针。
# 用户惯例：左 pane = coder = claude，右 pane = reviewer = codex。按“位置定角色”取会话，
# 不要信快照里每个 pane 的 agent 字段（它常把两个 pane 都误标成 codex）。
# 同一 (role|cwd) 的多个 pane（多个同目录 tab 的同侧）各取一个不同会话，不重复 resume 最近那一个。
$script:resumeQueues = @{}
$script:resumeIdx    = @{}
function Get-PaneResume {
    param($Pane, [string]$Role)   # Role = 'claude'(左/coder) | 'codex'(右/reviewer)
    $key = "$Role|$($Pane.cwd)"
    if (-not $script:resumeQueues.ContainsKey($key)) {
        $cands = if ($Role -eq 'claude') { $Pane.claudeCandidates } else { $Pane.codexCandidates }
        $seen = @{}
        $list = @()
        foreach ($c in @($cands)) {
            if ($c -and $c.sessionId -and -not $seen.ContainsKey($c.sessionId)) {
                $seen[$c.sessionId] = $true
                $list += $c.resumeCmd
            }
        }
        $script:resumeQueues[$key] = $list
        $script:resumeIdx[$key] = 0
    }
    $i = $script:resumeIdx[$key]
    $q = $script:resumeQueues[$key]
    if ($i -lt $q.Count) {
        $script:resumeIdx[$key] = $i + 1
        return $q[$i]
    }
    return ""   # 候选用尽：只开 shell、不重复 resume 同一会话（用户可在此手动开 reviewer）
}

# ---------- 计划 / 执行 ----------

Set-WezTermSocketEnv
$planLines = @()
$actions = 0

foreach ($win in $windows) {
    $firstTabInWindow = $true
    $newWindowId = $null

    # tab 保持快照里的数组顺序——修好后的 snapshot.ps1 存的就是标签栏可视顺序（cli list 行序）。
    # 绝不要在这里再按 tabId 排序：tabId 是创建顺序，会覆盖用户拖动后的真实顺序。
    foreach ($tab in @($win.tabs)) {
        # pane 按 leftCol 升序 => 左→右；配合 split --right 还原左右分屏。
        $panes = @($tab.panes | Sort-Object { [int]$_.geometry.leftCol })
        if ($panes.Count -eq 0) { continue }

        $p0 = $panes[0]
        $cmd0 = Get-PaneResume $p0 'claude'   # 最左 pane = coder = claude
        if ($firstTabInWindow) {
            $parent = "new-window"
            $planLines += "新窗口  tab(原 win $($win.windowId)/tab $($tab.tabId))  cwd=$($p0.cwd)  -> $cmd0"
        } else {
            $parent = "window:$newWindowId"
            $planLines += "新 tab (win $newWindowId)  cwd=$($p0.cwd)  -> $cmd0"
        }

        if (-not $WhatIf) {
            $paneId = Spawn-Pane -Parent $parent -Cwd $p0.cwd
            if ($firstTabInWindow) {
                $resolved = Get-WindowIdOfPane -PaneId $paneId
                if ($null -ne $resolved) { $newWindowId = $resolved }
            }
            Send-Resume -PaneId $paneId -Command $cmd0
            $prevPaneId = $paneId
            Start-Sleep -Seconds $StepDelaySeconds
        }
        $firstTabInWindow = $false
        $actions++

        # 同一 tab 内其余 pane → 从上一个 pane 向右分屏（左右排布）
        foreach ($pj in ($panes | Select-Object -Skip 1)) {
            $cmdj = Get-PaneResume $pj 'codex'   # 右侧 pane = reviewer = codex
            $planLines += "  分屏(右)  cwd=$($pj.cwd)  -> $cmdj"
            if (-not $WhatIf) {
                $splitId = Split-FromPane -PaneId $prevPaneId -Cwd $pj.cwd
                Send-Resume -PaneId $splitId -Command $cmdj
                $prevPaneId = $splitId
                Start-Sleep -Seconds $StepDelaySeconds
            }
            $actions++
        }
    }
}

if ($WhatIf) {
    Write-Host "=== 复原计划（-WhatIf，未执行）来自 $Snapshot ===" -ForegroundColor Cyan
    $planLines | ForEach-Object { Write-Host $_ }
    Write-Host "共 $actions 个 pane 待重建。去掉 -WhatIf 即真正执行。"
} else {
    Write-Host "复原完成：重建了 $actions 个 pane（快照 capturedAt=$($data.capturedAt)）。" -ForegroundColor Green
}
