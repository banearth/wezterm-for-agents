local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

config.default_prog = { 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' }
config.notification_handling = 'AlwaysShow'
config.audible_bell = 'SystemBeep'
config.visual_bell = {
  fade_in_duration_ms = 80,
  fade_out_duration_ms = 220,
  target = 'CursorColor',
}

local function copy_or_send_ctrl_c(window, pane)
  local has_selection = window:get_selection_text_for_pane(pane) ~= ''
  if has_selection then
    window:perform_action(act.CopyTo 'Clipboard', pane)
    window:perform_action(act.ClearSelection, pane)
  else
    window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
  end
end

local function split_auto(window, pane)
  local dimensions = pane:get_dimensions()
  local direction = 'Down'

  if dimensions.cols >= dimensions.viewport_rows * 2 then
    direction = 'Right'
  end

  window:perform_action(
    act.SplitPane {
      direction = direction,
      size = { Percent = 50 },
    },
    pane
  )
end

local function wezterm_exe()
  local exe = 'wezterm'
  if wezterm.target_triple:find 'windows' then
    exe = wezterm.executable_dir .. '/wezterm.exe'
  end

  return exe
end

local function toast(window, message)
  window:toast_notification('WezTerm', message, nil, 2500)
end

local function merge_adjacent_tab(window, pane, delta)
  local tabs = window:mux_window():tabs_with_info()
  local active_index = nil

  for index, item in ipairs(tabs) do
    if item.is_active then
      active_index = index
      break
    end
  end

  if not active_index then
    toast(window, 'Cannot find the active tab')
    return
  end

  local adjacent = tabs[active_index + delta]
  if not adjacent then
    local side = delta < 0 and 'left' or 'right'
    toast(window, 'No tab on the ' .. side)
    return
  end

  local moved_pane = adjacent.tab:active_pane()
  if not moved_pane then
    toast(window, 'Adjacent tab has no active pane')
    return
  end

  local side_arg = delta < 0 and '--left' or '--right'
  local success, stdout, stderr = wezterm.run_child_process {
    wezterm_exe(),
    'cli',
    'split-pane',
    '--pane-id',
    tostring(pane:pane_id()),
    side_arg,
    '--percent',
    '50',
    '--move-pane-id',
    tostring(moved_pane:pane_id()),
  }

  if not success then
    local detail = stderr ~= '' and stderr or stdout
    wezterm.log_error('Failed to merge adjacent tab: ' .. detail)
    toast(window, 'Failed to merge adjacent tab')
  end
end

local function detach_pane_to_new_tab(window, pane)
  local tab = pane:tab()
  if tab and #tab:panes() <= 1 then
    toast(window, 'Current tab only has one pane')
    return
  end

  local parent_index = nil
  for index, item in ipairs(window:mux_window():tabs_with_info()) do
    if item.is_active then
      parent_index = index
      break
    end
  end

  local ok, err = pcall(function()
    local new_tab = pane:move_to_new_tab()
    if parent_index then
      new_tab:activate()
      window:perform_action(act.MoveTab(parent_index), pane)
    end
  end)

  if not ok then
    wezterm.log_error('Failed to detach pane: ' .. tostring(err))
    toast(window, 'Failed to detach pane')
  end
end

local function rename_tab_action()
  return act.PromptInputLine {
    description = 'Enter new name for tab',
    action = wezterm.action_callback(function(window, pane, line)
      if line ~= nil then
        window:active_tab():set_title(line)
      end
    end),
  }
end

wezterm.on('augment-command-palette', function(window, pane)
  return {
    {
      brief = 'Rename tab',
      icon = 'md_rename_box',
      action = rename_tab_action(),
    },
  }
end)

-- Agent 完成通知：任何 pane 响铃（含 Claude Code 的 terminal_bell）都弹一个系统桌面通知。
-- 配合 ~/.claude/settings.json 里 "preferredNotifChannel": "terminal_bell"，
-- Claude 答完一轮等待输入时会响铃，这里就把它变成桌面弹窗（即使没盯着窗口也能看到）。
wezterm.on('bell', function(window, pane)
  local name = pane:get_title()
  if not name or name == '' then
    name = 'Pane ' .. tostring(pane:pane_id())
  end
  window:toast_notification('Agent 完成 / 需要关注', name, nil, 4000)
end)

config.keys = {
  -- Clipboard
  { key = 'c', mods = 'CTRL', action = wezterm.action_callback(copy_or_send_ctrl_c) },
  { key = 'v', mods = 'CTRL', action = act.PasteFrom 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
  { key = 'Insert', mods = 'SHIFT', action = act.PasteFrom 'Clipboard' },

  -- Tabs and windows
  { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'n', mods = 'CTRL|SHIFT', action = act.SpawnWindow },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab { confirm = true } },
  { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
  { key = 'Tab', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(-1) },
  { key = 'PageUp', mods = 'ALT|SHIFT', action = act.MoveTabRelative(-1) },
  { key = 'PageDown', mods = 'ALT|SHIFT', action = act.MoveTabRelative(1) },
  { key = '1', mods = 'CTRL|ALT', action = act.ActivateTab(0) },
  { key = '2', mods = 'CTRL|ALT', action = act.ActivateTab(1) },
  { key = '3', mods = 'CTRL|ALT', action = act.ActivateTab(2) },
  { key = '4', mods = 'CTRL|ALT', action = act.ActivateTab(3) },
  { key = '5', mods = 'CTRL|ALT', action = act.ActivateTab(4) },
  { key = '6', mods = 'CTRL|ALT', action = act.ActivateTab(5) },
  { key = '7', mods = 'CTRL|ALT', action = act.ActivateTab(6) },
  { key = '8', mods = 'CTRL|ALT', action = act.ActivateTab(7) },
  { key = '9', mods = 'CTRL|ALT', action = act.ActivateTab(-1) },

  -- Panes
  { key = 'd', mods = 'ALT|SHIFT', action = wezterm.action_callback(split_auto) },
  { key = '=', mods = 'ALT|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '+', mods = 'ALT|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '-', mods = 'ALT|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },
  { key = 'LeftArrow', mods = 'ALT|SHIFT', action = wezterm.action_callback(function(window, pane) merge_adjacent_tab(window, pane, -1) end) },
  { key = 'RightArrow', mods = 'ALT|SHIFT', action = wezterm.action_callback(function(window, pane) merge_adjacent_tab(window, pane, 1) end) },
  { key = 'UpArrow', mods = 'ALT|SHIFT', action = wezterm.action_callback(detach_pane_to_new_tab) },
  { key = 'DownArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Down', 1 } },

  -- Search, command palette, fullscreen
  { key = 'f', mods = 'CTRL|SHIFT', action = act.Search 'CurrentSelectionOrEmptyString' },
  { key = 'p', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },
  { key = 'Enter', mods = 'ALT', action = act.ToggleFullScreen },
  { key = 'm', mods = 'CTRL|SHIFT', action = act.ActivateCopyMode },

  -- Font size
  { key = '=', mods = 'CTRL', action = act.IncreaseFontSize },
  { key = '+', mods = 'CTRL', action = act.IncreaseFontSize },
  { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
  { key = '0', mods = 'CTRL', action = act.ResetFontSize },

  -- Scrollback
  { key = 'UpArrow', mods = 'CTRL|SHIFT', action = act.ScrollByLine(-1) },
  { key = 'DownArrow', mods = 'CTRL|SHIFT', action = act.ScrollByLine(1) },
  { key = 'PageUp', mods = 'CTRL|SHIFT', action = act.ScrollByPage(-1) },
  { key = 'PageDown', mods = 'CTRL|SHIFT', action = act.ScrollByPage(1) },
  { key = 'Home', mods = 'CTRL|SHIFT', action = act.ScrollToTop },
  { key = 'End', mods = 'CTRL|SHIFT', action = act.ScrollToBottom },
}

return config
