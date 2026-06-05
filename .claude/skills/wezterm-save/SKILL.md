---
name: wezterm-save
description: 立刻保存/存档当前 WezTerm 会话快照（tab 布局 + 每个 pane 的 agent 与 session id）。当用户说“保存 wezterm 会话”“存一下当前会话”“拍个快照”“备份当前 tab/session”“snapshot wezterm”，或在做有风险的操作前想立刻存一份时使用。复原请改用 wezterm-restore。
---

# WezTerm 会话保存（手动快照）

立刻拍一份当前 WezTerm 会话快照，供之后用 wezterm-restore 复原。

工程目录：`D:\CursorProject\WezTermInstall`
脚本：`D:\CursorProject\WezTermInstall\scripts\snapshot.ps1`
输出：`D:\CursorProject\WezTermInstall\snapshots\`（`latest.json` + 时间戳份，自动保留最近 288 份）

## 怎么做

直接跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\CursorProject\WezTermInstall\scripts\snapshot.ps1
```

脚本会：
- 自动发现并设置 `WEZTERM_UNIX_SOCKET`（外部进程不在 pane 里也能连上 wezterm cli），采集窗口/tab/pane 布局 + 每个 pane 的 cwd；
- 扫描 `~/.claude/projects` 与 `~/.codex/sessions` 近期 session，按 cwd 把 pane 对到 claude/codex 的 session id；
- 写出 json 快照。

跑完确认输出里 `weztermAvailable` 为 `true`、`panes` 大于 0，说明布局抓到了。若为 `false`，说明没找到运行中的 wezterm-gui（或 socket 文件缺失），此时只存了磁盘上的 session 索引、没有布局。

## 说明

- 已有计划任务 `WezTermSnapshot` 每 5 分钟自动跑一次同一个脚本（经 `run-snapshot-hidden.vbs` 纯后台、无窗口闪烁），所以平时无需手动。手动保存用于“现在就要一份最新的”——比如重启 wezterm、或做有风险改动之前。
- 这一步是只读采集，不改动 wezterm，安全。
