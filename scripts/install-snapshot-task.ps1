<#
.SYNOPSIS
注册（或卸载）一个 Windows 计划任务，每隔几分钟自动跑 snapshot.ps1，
这样 WezTerm 崩溃前总有一份新的会话快照可供 restore.ps1 复原。

任务在当前用户登录会话中运行（WezTerm 也只在登录时存在），无需管理员。

.EXAMPLE
# 安装：每 5 分钟一次
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-snapshot-task.ps1

.EXAMPLE
# 改成每 3 分钟
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-snapshot-task.ps1 -IntervalMinutes 3

.EXAMPLE
# 卸载
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-snapshot-task.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$TaskName = "WezTermSnapshot",
    [ValidateRange(1, 60)]
    [int]$IntervalMinutes = 5,
    [switch]$Uninstall
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "已卸载计划任务：$TaskName" -ForegroundColor Green
    } else {
        Write-Host "没有找到计划任务：$TaskName"
    }
    return
}

$snap = Join-Path $PSScriptRoot "snapshot.ps1"
if (-not (Test-Path -LiteralPath $snap)) {
    throw "找不到 snapshot.ps1：$snap"
}

# 经 wscript 跑 vbs 启动器，纯后台无窗口闪烁（powershell -WindowStyle Hidden 仍会闪）
$vbs = Join-Path $PSScriptRoot "run-snapshot-hidden.vbs"
if (-not (Test-Path -LiteralPath $vbs)) {
    throw "找不到 run-snapshot-hidden.vbs：$vbs"
}
$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbs`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "每 $IntervalMinutes 分钟拍一份 WezTerm 会话快照（snapshot.ps1），供崩溃后 restore.ps1 复原。" `
    -Force | Out-Null

Write-Host "已安装计划任务：$TaskName，每 $IntervalMinutes 分钟一次。" -ForegroundColor Green
Write-Host "快照写到：$(Join-Path (Split-Path -Parent $PSScriptRoot) 'snapshots')"
Write-Host "查看：Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo"
Write-Host "卸载：powershell -File scripts/install-snapshot-task.ps1 -Uninstall"
