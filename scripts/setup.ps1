#Requires -Version 5.1
# 一键安装：把工程的 wezterm.lua 部署到 ~/.wezterm.lua（带备份），并可选装“每5分钟自动快照”计划任务。
# 通常通过双击工程根目录的 install.bat 运行（它会以 Bypass 策略调用本脚本）。
# 单向部署：工程 -> live 家目录；绝不碰 WezTerm 安装目录（WezTerm 只读 ~/.wezterm.lua）。
# 默认会连【每5分钟自动快照】计划任务一起装；只想要配置、不要计划任务就加 -NoTask。
param([switch]$NoTask)
$ErrorActionPreference = "Stop"

$repo      = Split-Path -Parent $PSScriptRoot
$src       = Join-Path $repo "wezterm.lua"
$dest      = Join-Path $HOME ".wezterm.lua"
$backupDir = Join-Path $repo "backups"

Write-Host ""
Write-Host "=== WezTerm 配置一键部署 ===" -ForegroundColor Cyan
Write-Host "工程目录: $repo"
Write-Host "目标文件: $dest"
Write-Host ""

if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "错误: 找不到配置源文件 $src" -ForegroundColor Red
    return
}

# 检查 WezTerm 是否已安装（不强制，没装也照样写配置，只是不会生效）
$wez = Get-Command wezterm -ErrorAction SilentlyContinue
if ($wez) {
    $ver = (& wezterm --version 2>$null)
    Write-Host "已检测到 WezTerm: $ver" -ForegroundColor Green
} else {
    Write-Host "提醒: 命令行里找不到 wezterm。" -ForegroundColor Yellow
    Write-Host "      请先到 https://wezterm.org 装【官方版】（装完确保 wezterm 在 PATH 里）。"
    Write-Host "      本工程不编译 WezTerm，只负责这份配置；没装 WezTerm 的话配置不会生效。"
}

# 备份已有的 live 配置
if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}
if (Test-Path -LiteralPath $dest) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $bak   = Join-Path $backupDir "wezterm.lua.$stamp.bak"
    Copy-Item -LiteralPath $dest -Destination $bak -Force
    Write-Host "已备份原配置 -> $bak" -ForegroundColor Green
} else {
    Write-Host "（首次部署：家目录还没有 .wezterm.lua）"
}

# 部署（Copy-Item 按字节复制，保留 wezterm.lua 原编码）
Copy-Item -LiteralPath $src -Destination $dest -Force
Write-Host "已部署: $src -> $dest" -ForegroundColor Green
Write-Host "WezTerm 默认自动重载配置，通常无需重启；若没生效，手动重启 WezTerm。"
Write-Host ""

# 装“每5分钟自动快照”计划任务（崩溃后可用 restore 一键复原会话）——默认随部署一起装。
if ($NoTask) {
    Write-Host "已按 -NoTask 跳过自动快照任务（以后可单独运行 scripts\install-snapshot-task.ps1）。" -ForegroundColor Yellow
} else {
    $taskScript = Join-Path $PSScriptRoot "install-snapshot-task.ps1"
    if (Test-Path -LiteralPath $taskScript) {
        Write-Host "正在安装【每5分钟自动快照】计划任务..." -ForegroundColor Cyan
        & $taskScript
    } else {
        Write-Host "找不到 $taskScript，跳过计划任务安装。" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== 完成 ===" -ForegroundColor Cyan
Write-Host "你的配置现在在: $dest"
