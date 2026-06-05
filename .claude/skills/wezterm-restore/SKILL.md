---
name: wezterm-restore
description: 恢复/复原 WezTerm 会话与 tab 布局，把之前的 claude/codex session 在重开的 wezterm 里重建并自动 resume。当用户说“恢复 wezterm”“复原 wezterm”“把 tab 和 session 恢复回来”“restore wezterm session”时使用。保存/拍快照请改用 wezterm-save。
---

# WezTerm 会话快照 / 复原

WezTerm 长时间运行会反复卡死（GUI 控制 socket 不再响应）。这个 skill 用来在崩前定期存档、崩后一键复原：重建窗口/tab/分屏，并把每个 pane 自动 `resume` 回原来的 claude / codex 会话。

工程目录：`D:\CursorProject\WezTermInstall`
脚本目录：`D:\CursorProject\WezTermInstall\scripts`
快照目录：`D:\CursorProject\WezTermInstall\snapshots`（`latest.json` + 时间戳份）

所有脚本都用 PowerShell 调，固定前缀：
`powershell -NoProfile -ExecutionPolicy Bypass -File <脚本路径> [参数]`

## 复原（用户要“恢复 wezterm”时的默认流程）

1. **先确认 wezterm 是健康的新实例**。复原要往 wezterm 里 `spawn` tab，前提是它能响应 cli。
   - 探测：`wezterm cli list --format json`。若报 `failed to connect to Socket(...)`，说明旧实例仍冻死——提示用户先彻底重开 wezterm（必要时 `taskkill /F /IM wezterm-gui.exe`），再继续。
2. **先预览**：`powershell -NoProfile -ExecutionPolicy Bypass -File D:\CursorProject\WezTermInstall\scripts\restore.ps1 -WhatIf`
   - `restore.ps1` 默认自动挑“最近一份带布局（weztermAvailable=true）的快照”，不是盲取 latest.json（崩溃后最新几份往往没布局）。
   - 把它打印的复原计划（要开几个窗口/tab、各自 cwd、各自 resume 命令）念给用户确认。
3. **执行**：确认无误后去掉 `-WhatIf` 真跑：
   `powershell -NoProfile -ExecutionPolicy Bypass -File D:\CursorProject\WezTermInstall\scripts\restore.ps1`
   它会重建窗口/tab/分屏，每个 pane 切到原 cwd 并发送 `claude --resume <id>` 或 `codex resume <id>`。
4. 如果预览提示“这份快照没有 tab 布局”，说明还没有过一份健康时的快照可用——告诉用户：tab 布局无法重建，但磁盘上的 session 清单仍在快照的 `sessionIndex` 字段里（claude/codex 各自的 sessionId + cwd + resume 命令），可据此手动 resume。

## 手动拍快照（用户要“存一下当前会话”时）

`powershell -NoProfile -ExecutionPolicy Bypass -File D:\CursorProject\WezTermInstall\scripts\snapshot.ps1`

- 采集 wezterm 布局 + 每 pane 的 cwd/agent + 匹配到的 session id；扫描 `~/.claude/projects` 与 `~/.codex/sessions` 近期会话。
- wezterm 卡死时仍会写出磁盘侧的 session 索引（`weztermAvailable=false`），只是缺布局。
- 已有计划任务 `WezTermSnapshot` 每 5 分钟自动跑一次（经 `run-snapshot-hidden.vbs` 纯后台执行，无窗口闪烁），通常无需手动。

## 计划任务

- 安装/改间隔：`powershell -NoProfile -ExecutionPolicy Bypass -File D:\CursorProject\WezTermInstall\scripts\install-snapshot-task.ps1 [-IntervalMinutes 5]`
- 卸载：同脚本加 `-Uninstall`
- 查看：`Get-ScheduledTask -TaskName WezTermSnapshot | Get-ScheduledTaskInfo`

## 注意

- pane↔session 是按 cwd + 最近活跃时间启发式匹配，不保证 100% 准；快照 json 里每个 pane 都附了候选 session 列表，匹配可疑时让用户核对。
- 工程里的 `.ps1` 必须是 UTF-8 with BOM，否则 Windows PowerShell 5.1 按 GBK 解析中文会语法报错；编辑脚本后务必确认 BOM 仍在。
- 复原会真实开窗口、在 pane 里执行 resume 命令，属于有副作用操作——默认先 `-WhatIf` 给用户看过再真跑。
