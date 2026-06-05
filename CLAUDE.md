# WezTermInstall — WezTerm 配置工程

这个工程**只管一件事**：维护 WezTerm 终端的 Lua 配置。

## 重要：真源与部署目标

- **本工程的 `wezterm.lua` 是唯一的"真源"（source of truth）。所有改动都改这里。**
- 实际生效的 live 配置在用户家目录：`C:\Users\bandingyue\.wezterm.lua`（bash 下即 `$HOME/.wezterm.lua`）。
- **绝不要直接编辑 live 文件。** 改完工程里的 `wezterm.lua` 后，用部署脚本同步过去。

WezTerm 读配置只认 `$HOME/.wezterm.lua`，**不读这个工程目录**。所以"改 WezTerm 行为/快捷键"= 改本工程的 `wezterm.lua` 再部署，而不是在这个目录里找别的东西。

## 这不是什么

- 这里**没有 WezTerm 的 Rust 源码**，也不编译 WezTerm。改快捷键、配色、字体、分屏行为等全是 Lua 配置，不需要源码。
- 只有在需要改 WezTerm 本体行为（无法通过配置实现）时，才需要去 clone `https://github.com/wez/wezterm` 并用 cargo 编译——那是另一回事，本工程不涉及。

## 工作流（改配置的标准步骤）

1. 编辑本工程的 `wezterm.lua`。
2. 运行部署：
   ```bash
   bash scripts/deploy.sh
   ```
   它会先把当前 live 配置备份到 `backups/`，再把工程的 `wezterm.lua` 覆盖过去。
3. WezTerm 默认会自动重载配置（`automatically_reload_config` 默认开），通常无需重启。若没生效，手动重启 WezTerm。

如果 live 配置被别人直接改过、想让工程追上：
```bash
bash scripts/import.sh   # live -> 工程，改完记得 review diff
```

## 目录结构

- `wezterm.lua` — 配置真源，编辑这里。
- `install.bat` — 一键安装入口（双击即用，纯 ASCII 包装，不需要 bash）。调 `scripts/setup.ps1`：部署配置 + 装快照计划任务。给别人/新机器分享时用这个。
- `scripts/setup.ps1` — 一键安装实体：备份并部署 `wezterm.lua` → `~/.wezterm.lua`，默认连每 5 分钟自动快照计划任务一起装（加 `-NoTask` 只部署配置）。
- `scripts/deploy.sh` — 工程 → live（带自动备份）。
- `scripts/import.sh` — live → 工程（回拉）。
- `backups/` — 每次部署前的 live 配置时间戳备份。
- `scripts/snapshot.ps1` — 拍会话快照（布局 + agent + session id）。
- `scripts/restore.ps1` — 按快照全自动复原（重建 tab、自动 resume）。
- `scripts/install-snapshot-task.ps1` — 注册/卸载每 5 分钟自动快照的计划任务。
- `scripts/run-snapshot-hidden.vbs` — 计划任务用的隐藏启动器（经 wscript 以 SW_HIDE 拉起 snapshot.ps1，无窗口闪烁）。
- `snapshots/` — 快照输出（`latest.json` + 时间戳份；自动保留最近 288 份）。

## 崩溃复原（会话快照系统）

WezTerm 长时间运行会反复卡死（GUI socket 不再响应），用这套机制在崩前定期存档、崩后一键复原。

- **抓快照**：`snapshot.ps1` 采集 `wezterm cli list` 的窗口/tab/pane 布局 + 每个 pane 的 cwd，并扫描磁盘上 `~/.claude/projects` 与 `~/.codex/sessions` 的近期 session（按 cwd 把 pane 对到 session id）。已注册计划任务 `WezTermSnapshot` 每 5 分钟自动跑一次。
  - wezterm 卡死时，`snapshot.ps1` 仍会写出磁盘侧的 session 索引（`weztermAvailable=false`），只是缺布局——所以**布局必须靠崩前的定时快照**，session 清单崩后也能从磁盘重建。
- **复原**：重开一个健康的 wezterm 后，`powershell -File scripts/restore.ps1`（默认直接执行；加 `-WhatIf` 仅预览）。它按 `latest.json` 重建窗口/tab/分屏，每个 pane 切到原 cwd 并发送 `claude --resume <id>` / `codex resume <id>`。
- **注意**：所有 `.ps1` 必须存成 **UTF-8 with BOM**，否则 Windows PowerShell 5.1 按 GBK 解析中文会语法报错。新增/编辑后用 `New-Object System.Text.UTF8Encoding $true` 重存确认 BOM。

## 当前配置概览（便于快速定位）

`wezterm.lua` 里已有的自定义：

- **基础**：默认 shell 为 PowerShell；通知 `AlwaysShow`；系统蜂鸣 + 光标视觉响铃。
- **自定义函数**：
  - `copy_or_send_ctrl_c` — Ctrl+C 有选区则复制、无选区则发中断。
  - `split_auto` — 按宽高比自动决定左右/上下分屏。
  - `merge_adjacent_tab` — 合并相邻标签页的 pane（内部调 `wezterm cli split-pane`）。
  - `detach_pane_to_new_tab` — 把当前 pane 拆成新标签页。
  - 命令面板加了 "Rename tab"。
- **快捷键**：见 `config.keys`（剪贴板 / 标签窗口 / 分屏 / 搜索面板全屏 / 字号 / 滚动）。

## 注意事项

- `merge_adjacent_tab` 用 `wezterm.run_child_process` 调 `wezterm cli`，走的是 mux IPC 通道。手动按键触发没问题；**不要把这类 `wezterm cli` 调用放进会高频反复触发的逻辑**——高频 `wezterm cli get-text`/`split-pane` 会把 GUI 的控制 socket 灌死、导致 wezterm-gui 卡死无响应。
- 改键位后注意和系统/shell 已有快捷键的冲突。
