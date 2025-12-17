-- @description Toolbox - UI Demo (ReaImGui template)
-- @version 0.2
-- @author Lee
-- @about
--   共享“工具箱”入口 Demo（用于学习/复用 GUI 实现逻辑与通用组件）：
--   - framework/*  : 皮肤/控件/布局/日志/终端/配置等模块
--   - fonts/       : 可选字体目录

local r = reaper

local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local root = script_dir()
package.path = root .. "framework/?.lua;" .. package.path

local bootstrap = require("bootstrap")
local ImGui = bootstrap.ensure_imgui("0.9")
if not ImGui then
  return
end

local App = require("app").App
local W = require("widgets")
local Colors = require("ui_colors")
local Theme = require("ui_theme")
local AppState = require("app_state")
local Dock = require("dock")
local IconBar = require("icon_bar")
local Editors = require("editors")
local Log = require("log")
local Terminal = require("terminal")

local app = App.new(ImGui, {
  title = "Toolbox - UI Demo",
  ext_section = "Toolbox_UI_Demo",
})

local function safe_get(tbl, key)
  local ok, v = pcall(function()
    return tbl[key]
  end)
  if ok then return v end
  return nil
end

local function demo_state()
  app._demo = app._demo or {
    text = "Hello UI",
    multiline = "多行输入\\nLine 2\\nLine 3",
    i = 12,
    d = 0.42,
    slider = 0.5,
    combo = 0,
    radio = 1,
    check_a = true,
    check_b = false,
    table_rows = 30,
    selected = {},
    dd_payload = "payload",
    show_popup = false,
    show_modal = false,
  }
  return app._demo
end

local destroyed = false
r.atexit(function()
  if not destroyed then
    destroyed = true
    pcall(function()
      Theme.destroy(app)
      app:destroy()
    end)
  end
end)

local function draw()
  local ctx = app.ctx
  local s = demo_state()

  -- 顶部工具栏
  IconBar.draw(ctx, ImGui, app)
  ImGui.Separator(ctx)

  if app._theme and app._theme.fonts and app._theme.fonts.heading1 then
    ImGui.PushFont(ctx, app._theme.fonts.heading1)
    ImGui.Text(ctx, "Toolbox UI Demo")
    ImGui.PopFont(ctx)
  else
    ImGui.Text(ctx, "Toolbox UI Demo")
  end
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, Colors.semantic.TextDim or 4294967193)
  ImGui.Text(ctx, "目标：提供一套统一的暗色主题 + 组件封装 + 配置持久化，供脚本复用。")
  ImGui.PopStyleColor(ctx, 1)

  -- 备用关闭按钮（避免无标题栏时不好退出）
  if ImGui.Button(ctx, "关闭窗口 / Close") then
    app.open = false
    Log.warn(app.log, "Close requested from main button")
    return
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, "（顶部 X 若点不到就用这里）")

  W.separator_text(ctx, ImGui, "基础开关")
  local changed

  changed, app.state.show_demo_window = ImGui.Checkbox(ctx, "显示 ImGui 官方 Demo Window", app.state.show_demo_window)

  changed, app.state.always_on_top = ImGui.Checkbox(ctx, "窗口置顶 (TopMost)", app.state.always_on_top)
  W.help_marker(ctx, ImGui, "不同系统/版本支持情况不同，若无效可忽略。")

  ImGui.Spacing(ctx)
  W.separator_text(ctx, ImGui, "缩放 / 状态")
  ImGui.SetNextItemWidth(ctx, 220)
  changed, app.state.scale = ImGui.SliderDouble(ctx, "UI 缩放", app.state.scale, 0.70, 1.80, "%.2fx")

  if ImGui.Button(ctx, "保存状态") then
    AppState.save(app)
    Log.info(app.log, "Config saved")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "重置缩放") then
    app.state.scale = 1.0
  end

  ImGui.Spacing(ctx)
  W.separator_text(ctx, ImGui, "演示案例（更全）")

  if ImGui.CollapsingHeader(ctx, "1) 基础控件（Input/Slider/Combo/Radio）", ImGui.TreeNodeFlags_DefaultOpen) then
    ImGui.PushItemWidth(ctx, 260)
    _, s.text = ImGui.InputText(ctx, "InputText", s.text)
    ImGui.PopItemWidth(ctx)

    ImGui.PushItemWidth(ctx, 360)
    _, s.multiline = ImGui.InputTextMultiline(ctx, "InputTextMultiline", s.multiline, 400, 70)
    ImGui.PopItemWidth(ctx)

    _, s.i = ImGui.DragInt(ctx, "DragInt", s.i, 1, -128, 128)
    _, s.d = ImGui.DragDouble(ctx, "DragDouble", s.d, 0.01, -10, 10, "%.2f")
    _, s.slider = ImGui.SliderDouble(ctx, "SliderDouble", s.slider, 0, 1, "%.2f")

    _, s.check_a = ImGui.Checkbox(ctx, "Checkbox A", s.check_a)
    ImGui.SameLine(ctx)
    _, s.check_b = ImGui.Checkbox(ctx, "Checkbox B", s.check_b)

    if ImGui.RadioButton(ctx, "Radio 1", s.radio == 1) then s.radio = 1 end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Radio 2", s.radio == 2) then s.radio = 2 end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Radio 3", s.radio == 3) then s.radio = 3 end

    -- Combo（用 BeginCombo/Selectable 兼容更多版本）
    local items = {"One", "Two", "Three", "Four"}
    local preview = items[(s.combo or 0) + 1] or "One"
    if ImGui.BeginCombo(ctx, "Combo", preview) then
      for idx = 0, #items - 1 do
        if ImGui.Selectable(ctx, items[idx + 1], (s.combo == idx)) then
          s.combo = idx
        end
      end
      ImGui.EndCombo(ctx)
    end

    if ImGui.Button(ctx, "Log: hello") then
      Log.info(app.log, "Hello from demo button")
    end
  end

  if ImGui.CollapsingHeader(ctx, "2) 布局（Tabs / Child / Table）", ImGui.TreeNodeFlags_DefaultOpen) then
    W.separator_text(ctx, ImGui, "Tabs")
    if ImGui.BeginTabBar(ctx, "##main_tabs") then
      if ImGui.BeginTabItem(ctx, "Tab A") then
        ImGui.Text(ctx, "把你的 UI 代码放在 draw() 里即可。")
        ImGui.Text(ctx, "建议：把业务逻辑和 UI 分离成模块/函数。")
        ImGui.EndTabItem(ctx)
      end
      if ImGui.BeginTabItem(ctx, "Tab B") then
        ImGui.Text(ctx, "这个 Tab 用来放更复杂的布局示例。")
        ImGui.EndTabItem(ctx)
      end
      ImGui.EndTabBar(ctx)
    end

    W.separator_text(ctx, ImGui, "Child + Scroll")
    if ImGui.BeginChild(ctx, "##child_scroll", -1, 90, safe_get(ImGui, "ChildFlags_Border") or 0) then
      for i = 1, 50 do
        ImGui.Text(ctx, ("Line %02d"):format(i))
      end
      ImGui.EndChild(ctx)
    end

    W.separator_text(ctx, ImGui, "Table")
    local BeginTable = safe_get(ImGui, "BeginTable")
    local TableSetupColumn = safe_get(ImGui, "TableSetupColumn")
    local TableHeadersRow = safe_get(ImGui, "TableHeadersRow")
    local TableNextRow = safe_get(ImGui, "TableNextRow")
    local TableNextColumn = safe_get(ImGui, "TableNextColumn")
    local EndTable = safe_get(ImGui, "EndTable")
    if BeginTable and TableSetupColumn and TableHeadersRow and TableNextRow and TableNextColumn and EndTable then
      _, s.table_rows = ImGui.SliderInt(ctx, "Rows", s.table_rows, 5, 200, "%d")
      if BeginTable(ctx, "##tbl", 3, 0) then
        TableSetupColumn(ctx, "Name")
        TableSetupColumn(ctx, "Value")
        TableSetupColumn(ctx, "Select")
        TableHeadersRow(ctx)
        for i = 1, s.table_rows do
          TableNextRow(ctx)
          TableNextColumn(ctx); ImGui.Text(ctx, "Item " .. i)
          TableNextColumn(ctx); ImGui.Text(ctx, string.format("%.2f", math.sin(i * 0.1)))
          TableNextColumn(ctx)
          s.selected[i] = s.selected[i] or false
          local rv; rv, s.selected[i] = ImGui.Checkbox(ctx, "##sel" .. i, s.selected[i])
        end
        EndTable(ctx)
      end
    else
      ImGui.TextDisabled(ctx, "Table API not available in this ReaImGui build.")
    end
  end

  if ImGui.CollapsingHeader(ctx, "3) 弹出（Popup / Modal / Context menu）", ImGui.TreeNodeFlags_DefaultOpen) then
    if ImGui.Button(ctx, "Open Popup") then
      s.show_popup = true
      if safe_get(ImGui, "OpenPopup") then
        ImGui.OpenPopup(ctx, "demo_popup")
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Open Modal") then
      s.show_modal = true
      if safe_get(ImGui, "OpenPopup") then
        ImGui.OpenPopup(ctx, "demo_modal")
      end
    end

    local BeginPopup = safe_get(ImGui, "BeginPopup")
    local EndPopup = safe_get(ImGui, "EndPopup")
    if BeginPopup and EndPopup then
      if BeginPopup(ctx, "demo_popup") then
        ImGui.Text(ctx, "This is a popup.")
        if ImGui.Button(ctx, "Close") then
          ImGui.CloseCurrentPopup(ctx)
        end
        EndPopup(ctx)
      end
    end

    local BeginPopupModal = safe_get(ImGui, "BeginPopupModal")
    if BeginPopupModal and EndPopup then
      local rv, open_modal = BeginPopupModal(ctx, "demo_modal", true)
      if rv then
        ImGui.Text(ctx, "This is a modal dialog.")
        if ImGui.Button(ctx, "OK") then
          ImGui.CloseCurrentPopup(ctx)
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Cancel") then
          ImGui.CloseCurrentPopup(ctx)
        end
        EndPopup(ctx)
      end
      if open_modal == false then
        s.show_modal = false
      end
    end

    -- Context menu
    ImGui.Text(ctx, "Right-click this text:")
    if safe_get(ImGui, "BeginPopupContextItem") and ImGui.BeginPopupContextItem(ctx, "##ctxmenu") then
      if ImGui.MenuItem(ctx, "Copy") then
        ImGui.SetClipboardText(ctx, "Copied from context menu")
      end
      if ImGui.MenuItem(ctx, "Write log") then
        Log.warn(app.log, "Context menu clicked")
      end
      ImGui.EndPopup(ctx)
    end
  end

  if ImGui.CollapsingHeader(ctx, "4) Drag & Drop（如果支持）", ImGui.TreeNodeFlags_DefaultOpen) then
    local BeginDragDropSource = safe_get(ImGui, "BeginDragDropSource")
    local SetDragDropPayload = safe_get(ImGui, "SetDragDropPayload")
    local EndDragDropSource = safe_get(ImGui, "EndDragDropSource")
    local BeginDragDropTarget = safe_get(ImGui, "BeginDragDropTarget")
    local AcceptDragDropPayload = safe_get(ImGui, "AcceptDragDropPayload")
    local EndDragDropTarget = safe_get(ImGui, "EndDragDropTarget")

    ImGui.Button(ctx, "Drag me")
    if BeginDragDropSource and SetDragDropPayload and EndDragDropSource and BeginDragDropSource(ctx) then
      SetDragDropPayload(ctx, "LEE_PAYLOAD", s.dd_payload)
      ImGui.Text(ctx, "payload: " .. tostring(s.dd_payload))
      EndDragDropSource(ctx)
    end

    ImGui.SameLine(ctx)
    ImGui.Button(ctx, "Drop here")
    if BeginDragDropTarget and AcceptDragDropPayload and EndDragDropTarget and BeginDragDropTarget(ctx) then
      local ok, payload = pcall(AcceptDragDropPayload, ctx, "LEE_PAYLOAD")
      if ok and payload then
        s.dd_payload = tostring(payload)
        Log.info(app.log, "Dropped payload: " .. s.dd_payload)
      end
      EndDragDropTarget(ctx)
    end
  end

  if ImGui.CollapsingHeader(ctx, "5) Plot/Progress（如果支持）", ImGui.TreeNodeFlags_DefaultOpen) then
    local t = r.time_precise()
    local p = (math.sin(t) * 0.5 + 0.5)
    if safe_get(ImGui, "ProgressBar") then
      ImGui.ProgressBar(ctx, p, -1, 0, string.format("progress %.0f%%", p * 100))
    else
      ImGui.Text(ctx, string.format("progress %.0f%% (ProgressBar API not available)", p * 100))
    end

    local PlotLines = safe_get(ImGui, "PlotLines")
    if PlotLines then
      -- 你这版 ReaImGui 需要 reaper_array*（不是 Lua table）
      if reaper.new_array then
        s._plot = s._plot or {}
        local P = s._plot
        P.n = P.n or 120
        if not P.arr or P.arr_size ~= P.n then
          P.arr = reaper.new_array(P.n)
          P.arr_size = P.n
          P.zero_based = nil
        end

        -- 注意：reaper_array 在不同 REAPER 版本可能是 0/1 基索引；先探测一次
        if P.zero_based == nil then
          local ok0 = pcall(function()
            P.arr[0] = 0
          end)
          P.zero_based = ok0
        end

        if P.zero_based then
          for i = 0, P.n - 1 do
            P.arr[i] = math.sin(((i + 1) / 10) + t)
          end
        else
          for i = 1, P.n do
            P.arr[i] = math.sin((i / 10) + t)
          end
        end
        PlotLines(ctx, "Sine", P.arr, P.n)
      else
        ImGui.TextDisabled(ctx, "reaper.new_array not available; cannot demo PlotLines in this REAPER build.")
      end
    else
      ImGui.TextDisabled(ctx, "PlotLines API not available in this ReaImGui build.")
    end
  end
end

local function draw_log_window()
  local ctx = app.ctx
  if not app.state.show_log then return end

  local visible, open = ImGui.Begin(ctx, "Lee UI - Log", true)
  if visible then
    Log.draw(ctx, ImGui, app.log)
  end
  ImGui.End(ctx)
  if open == false then
    app.state.show_log = false
  end
end

local function draw_terminal_window()
  local ctx = app.ctx
  if not app.state.show_terminal then return end

  local visible, open = ImGui.Begin(ctx, "Lee UI - Terminal", true)
  if visible then
    Terminal.draw(ctx, ImGui, app)
  end
  ImGui.End(ctx)
  if open == false then
    app.state.show_terminal = false
  end
end

local function draw_theme_style_windows()
  local ctx = app.ctx

  if app.state.show_theme_editor then
    Editors.draw_theme(ctx, ImGui, app)
  end

  if app.state.show_style_editor then
    Editors.draw_style(ctx, ImGui, app)
  end
end

local function loop()
  Theme.begin(app)

  -- 全局 DockSpace（如果版本支持）
  Dock.ensure(app.ctx, ImGui, 0)

  local visible, open
  if app.open == false then
    -- 强制关闭：不要依赖 ImGui.Begin 的 open 参数兼容性
    visible, open = false, false
  else
    visible, open = app:begin_window()
    if visible then
      draw()
    end
    app:end_window()
    -- 如果 UI 内部按了关闭按钮，本帧立即生效（不等下一帧）
    if app.open == false then
      open = false
    end
  end

  -- 其它窗口也套同一套皮肤
  if open then
    draw_log_window()
    draw_terminal_window()
    draw_theme_style_windows()
  end

  Theme.end_(app)
  if open then
    AppState.tick(app, app.state.low_cpu and 2.0 or 0.75)
  end

  if open then
    r.defer(loop)
  else
    if not destroyed then
      destroyed = true
      Theme.destroy(app)
      app:destroy()
    end
  end
end

r.defer(loop)
