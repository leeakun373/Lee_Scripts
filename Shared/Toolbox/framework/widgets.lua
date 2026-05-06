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

local function has_fn(tbl, key)
  return tbl and type(tbl[key]) == "function"
end

-- Float slider with broad ReaImGui compatibility.
-- Returns: changed:boolean, value:number
function M.slider_float(ctx, ImGui, label, value, min_value, max_value, format)
  if has_fn(ImGui, "SliderDouble") then
    return ImGui.SliderDouble(ctx, label, value, min_value, max_value, format or "%.3f")
  end
  if has_fn(ImGui, "SliderFloat") then
    return ImGui.SliderFloat(ctx, label, value, min_value, max_value, format or "%.3f")
  end
  if has_fn(ImGui, "DragDouble") then
    return ImGui.DragDouble(ctx, label, value, 0.01, min_value, max_value, format or "%.3f")
  end
  if has_fn(ImGui, "DragFloat") then
    return ImGui.DragFloat(ctx, label, value, 0.01, min_value, max_value, format or "%.3f")
  end
  return false, value
end

-- Int slider with broad ReaImGui compatibility.
-- Returns: changed:boolean, value:number
function M.slider_int(ctx, ImGui, label, value, min_value, max_value, format)
  if has_fn(ImGui, "SliderInt") then
    return ImGui.SliderInt(ctx, label, value, min_value, max_value, format or "%d")
  end
  if has_fn(ImGui, "DragInt") then
    return ImGui.DragInt(ctx, label, value, 1, min_value, max_value, format or "%d")
  end
  return false, value
end

function M.drag_float(ctx, ImGui, label, value, speed, min_value, max_value, format)
  if has_fn(ImGui, "DragDouble") then
    return ImGui.DragDouble(ctx, label, value, speed or 0.01, min_value, max_value, format or "%.3f")
  end
  if has_fn(ImGui, "DragFloat") then
    return ImGui.DragFloat(ctx, label, value, speed or 0.01, min_value, max_value, format or "%.3f")
  end
  return M.slider_float(ctx, ImGui, label, value, min_value, max_value, format)
end

function M.drag_int(ctx, ImGui, label, value, speed, min_value, max_value, format)
  if has_fn(ImGui, "DragInt") then
    return ImGui.DragInt(ctx, label, value, speed or 1, min_value, max_value, format or "%d")
  end
  return M.slider_int(ctx, ImGui, label, value, min_value, max_value, format)
end

return M
