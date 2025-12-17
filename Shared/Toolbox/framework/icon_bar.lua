-- Shared/Toolbox/framework/icon_bar.lua
-- 顶部工具栏：扁平按钮 + 语义色。

local Colors = require("ui_colors")

local M = {}

local function flat_button(ctx, ImGui, label, enabled, width)
  -- 做成“无背景”的扁平按钮，靠文字颜色表达状态
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)

  local col = enabled and (Colors.semantic.IconBarEnabled or 0x53C1FFFF) or (Colors.semantic.IconBarDisabled or 0x808080FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, col)

  local rv = ImGui.Button(ctx, label, width or 0, 0)

  ImGui.PopStyleColor(ctx, 4)
  return rv
end

function M.draw(ctx, ImGui, app)
  local s = app.state

  ImGui.BeginGroup(ctx)

  if flat_button(ctx, ImGui, "LOG", s.show_log, 44) then
    s.show_log = not s.show_log
  end
  ImGui.SameLine(ctx)

  if flat_button(ctx, ImGui, "TERM", s.show_terminal, 52) then
    s.show_terminal = not s.show_terminal
  end
  ImGui.SameLine(ctx)

  if flat_button(ctx, ImGui, "THEME", s.show_theme_editor, 60) then
    s.show_theme_editor = not s.show_theme_editor
  end
  ImGui.SameLine(ctx)

  if flat_button(ctx, ImGui, "STYLE", s.show_style_editor, 60) then
    s.show_style_editor = not s.show_style_editor
  end
  ImGui.SameLine(ctx)

  if flat_button(ctx, ImGui, s.low_cpu and "CPU:LOW" or "CPU:HI", s.low_cpu, 70) then
    s.low_cpu = not s.low_cpu
  end

  ImGui.SameLine(ctx)
  -- 关闭键：因为 NoTitleBar 没有系统自带 X，这里提供一个自定义关闭
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF4040FF) -- 红色
  local close_clicked = flat_button(ctx, ImGui, "X", false, 22)
  ImGui.PopStyleColor(ctx, 1)
  if close_clicked then
    app.open = false
  end

  ImGui.EndGroup(ctx)
end

return M
