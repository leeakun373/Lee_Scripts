-- Shared/Toolbox/framework/ui_style.lua
-- 默认 StyleVar：做一个可复用的“外观层”。

local M = {}

-- 默认 StyleVar
M.defaults = {
  Alpha = 1.0,
  DisabledAlpha = 0.6,
  WindowPadding = {8, 4},
  FramePadding = {4, 3},
  CellPadding = {4, 4},
  ItemSpacing = {4, 4},
  ItemInnerSpacing = {4, 4},
  IndentSpacing = 21,
  ScrollbarSize = 14,
  GrabMinSize = 12,
  WindowBorderSize = 1,
  ChildBorderSize = 1,
  PopupBorderSize = 1,
  FrameBorderSize = 0,
  WindowRounding = 8,
  ChildRounding = 0,
  FrameRounding = 2,
  PopupRounding = 4,
  ScrollbarRounding = 4,
  GrabRounding = 2,
  TabRounding = 2,
  WindowTitleAlign = {0.5, 0.5},
  ButtonTextAlign = {0.5, 0.5},
  SelectableTextAlign = {0.0, 0.5},
}

M.scalable = {
  WindowPadding = true,
  FramePadding = true,
  CellPadding = true,
  ItemSpacing = true,
  ItemInnerSpacing = true,
  IndentSpacing = true,
  ScrollbarSize = true,
  GrabMinSize = true,
}

local function scale_value(name, v, scale)
  if not M.scalable[name] then
    return v
  end
  return v * (scale or 1)
end

-- 返回 push 的数量（用于 PopStyleVar）
function M.push(ctx, ImGui, scale, overrides)
  scale = scale or 1
  overrides = overrides or {}

  local count = 0
  for name, def in pairs(M.defaults) do
    local var = ImGui["StyleVar_" .. name]
    if var then
      local v = overrides[name]
      if v == nil then
        v = def
      end

      if type(v) == "table" then
        local x = scale_value(name, v[1], scale)
        local y = scale_value(name, v[2], scale)
        ImGui.PushStyleVar(ctx, var, x, y)
      else
        ImGui.PushStyleVar(ctx, var, scale_value(name, v, scale))
      end
      count = count + 1
    end
  end

  return count
end

function M.pop(ctx, ImGui, count)
  if count and count > 0 then
    ImGui.PopStyleVar(ctx, count)
  end
end

return M
