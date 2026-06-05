# wezterm-for-agents

一套**为 AI 编程工作流定制的 WezTerm 配置**（外加崩溃复原工具）。它本身不含任何 AI 能力——只是把终端调成顺手配合 claude / codex 这类 agent 干活的样子。

> A WezTerm setup tuned for working with AI coding agents (claude + codex): custom keybindings, one-click install, and session crash-recovery. Windows-only.

## 它做了什么

- **AI 双 agent 布局**：每个项目一个 tab，左右分屏 —— 左 = coder（claude）、右 = reviewer（codex），各自独立会话。
- **一堆顺手的快捷键**：剪贴板 / 标签与窗口 / 智能分屏（按宽高比自动左右或上下）/ 合并相邻标签 / 把 pane 拆成新标签 / 搜索面板全屏 / 字号 / 滚动等。详见 [CLAUDE.md](./CLAUDE.md)。
- **崩溃复原**：WezTerm 长跑会偶发卡死。后台每 5 分钟自动拍一份会话快照（窗口/tab/分屏布局 + 每个 pane 的 cwd + 匹配到的 claude/codex session id）；崩溃后一条命令重建所有 tab、切回原目录并自动 `resume` 回原会话。

## 环境要求

- **Windows**（依赖 PowerShell 5.1、计划任务、`.vbs` 启动器）。
- 官方 **WezTerm**（到 [wezterm.org](https://wezterm.org) 下载安装，确保命令行能跑 `wezterm`）。本仓库**不编译、不包含** WezTerm 本体，只提供配置与工具。
- 会话复原依赖你机器上装了 `claude` / `codex` CLI 并有对应工程的会话记录。

## 一键安装

把整个仓库拷到本机任意位置，然后**双击 `install.bat`**。它会：

1. 检测 WezTerm 是否已安装；
2. 备份现有 `~/.wezterm.lua`（如果有）到 `backups/`；
3. 部署本仓库的 `wezterm.lua` → `~/.wezterm.lua`（WezTerm 只读这个位置）；
4. 安装「每 5 分钟自动快照」计划任务。

> 只想要配置、不要定时任务：`powershell -ExecutionPolicy Bypass -File scripts/setup.ps1 -NoTask`

## 崩溃复原怎么用

```powershell
# 重开一个健康的 WezTerm 后：
powershell -ExecutionPolicy Bypass -File scripts/restore.ps1 -WhatIf   # 先预览复原计划
powershell -ExecutionPolicy Bypass -File scripts/restore.ps1           # 确认后真正执行
```

它默认挑「最近一份带布局的快照」还原，按数组顺序重建 tab、左右分屏、左 claude / 右 codex，并在各 pane 发 `claude --resume <id>` / `codex resume <id>`。

## 目录结构

| 路径 | 作用 |
|---|---|
| `wezterm.lua` | 配置真源，改这里 |
| `install.bat` | 一键安装入口（双击） |
| `scripts/setup.ps1` | 部署配置 + 装快照任务（`-NoTask` 只部署配置） |
| `scripts/deploy.sh` / `import.sh` | 配置 工程↔live 双向同步（需 bash） |
| `scripts/snapshot.ps1` | 拍会话快照 |
| `scripts/restore.ps1` | 按快照复原会话 |
| `scripts/install-snapshot-task.ps1` | 注册/卸载每 5 分钟自动快照计划任务 |
| `snapshots/` · `backups/` | 快照与配置备份（本地生成，已 gitignore） |

更详细的约定、注意事项见 [CLAUDE.md](./CLAUDE.md)。

## 个性化提醒

- **左 claude / 右 codex 的约定写死在 `scripts/restore.ps1`**（`Get-PaneResume` 的两处调用）。习惯不同就改这两行。
- 所有 `.ps1` 必须存成 **UTF-8 with BOM**，否则 PowerShell 5.1 按 GBK 解析中文会语法报错。
