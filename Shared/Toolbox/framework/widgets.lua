-- Shared/Toolbox/framework/widgets.lua
-- 一些常用的小组件封装（可按需自行扩展）。

local M = {}

function M.separator_text(ctx, ImGui, label)
  if ImGui.SeparatorText then
    ImGui.SeparatorText(ctx, label)
  else
    ImGui.Separator(ctx)
    ImGui.Text(ctx, label)
    ImGui.Separator(ctx)
  end
end

function M.help_marker(ctx, ImGui, text)
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.BeginTooltip(ctx)
    ImGui.PushTextWrapPos(ctx, 320)
    ImGui.Text(ctx, text)
    ImGui.PopTextWrapPos(ctx)
    ImGui.EndTooltip(ctx)
  end
end

return M
