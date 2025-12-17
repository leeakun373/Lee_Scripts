-- Shared/Toolbox/framework/ui_colors.lua
-- 默认配色（U32）：提供一套暗色 + teal 点缀的皮肤。

local M = {}

-- 注意：ReaImGui 的 PushStyleColor 直接吃 U32。
M.u32 = {
  DragDropTarget = 331192831,
  FrameBg = 1920102948,
  FrameBgHovered = 2155905124,
  FrameBgActive = 2155905152,
  CheckMark = 331192831,
  TitleBg = 623191551,
  TitleBgActive = 808464639,
  TitleBgCollapsed = 538976511,
  Button = 1616928870,
  ButtonHovered = 1616929023,
  ButtonActive = 2155905279,
  Text = 4294967262,
  TextDisabled = 4294967137,
  TextSelectedBg = 905958500,
  ResizeGrip = 2155905024,
  ResizeGripHovered = 2155905024,
  ResizeGripActive = 2155905024,
  Separator = 2155905152,
  SeparatorHovered = 2155905223,
  SeparatorActive = 2155905279,
  Tab = 1616928870,
  TabHovered = 1616929023,
  TabActive = 1819045119,
  WindowBg = 538976511,
  PopupBg = 538976496,
  ScrollbarBg = 404232327,
  Header = 1616928870,
  HeaderHovered = 1616929023,
  HeaderActive = 2155905279,
  NavHighlight = 331192776,
  TableRowBg = 4294967040,
  TableRowBgAlt = 4294967044,
  SliderGrab = 331192776,
  SliderGrabActive = 905958621,
  PlotLines = 1403886591,
  PlotLinesHovered = 1403886591,
  PlotHistogram = 1339012402,
  PlotHistogramHovered = 1339012402,
  DockingPreview = 1123734963,
  TabUnfocused = 640034552,
  TabUnfocusedActive = 1819045119,
  Border = -2139062144,
  TableBorderLight = 993737727,
  TableBorderStrong = 1330597887,
  TableHeaderBg = 858993663,
}

-- 自定义用色（非 ImGui.Col_*，当作“语义色”用）
M.semantic = {
  IconBarEnabled = 1403886591,
  IconBarDisabled = 2155905279,
  Title = 1403886591,
  DimTableBorder = 2155905088,
  TextHighlight = 866944255,
  TextDim = 4294967193,
  border_focused = 2155905279,
}

local function push_if(ctx, ImGui, col_const, u32)
  if col_const ~= nil and u32 ~= nil then
    ImGui.PushStyleColor(ctx, col_const, u32)
    return 1
  end
  return 0
end

-- 返回 push 的数量（用于 PopStyleColor）
function M.push(ctx, ImGui, overrides)
  local c = M.u32
  overrides = type(overrides) == "table" and overrides or nil

  local function pick(key, default_u32)
    if not overrides then return default_u32 end
    -- 支持两种写法：WindowBg / Col_WindowBg
    if overrides[key] ~= nil then return overrides[key] end
    local k2 = "Col_" .. key
    if overrides[k2] ~= nil then return overrides[k2] end
    return default_u32
  end

  local count = 0

  count = count + push_if(ctx, ImGui, ImGui.Col_DragDropTarget, pick("DragDropTarget", c.DragDropTarget))
  count = count + push_if(ctx, ImGui, ImGui.Col_FrameBg, pick("FrameBg", c.FrameBg))
  count = count + push_if(ctx, ImGui, ImGui.Col_FrameBgHovered, pick("FrameBgHovered", c.FrameBgHovered))
  count = count + push_if(ctx, ImGui, ImGui.Col_FrameBgActive, pick("FrameBgActive", c.FrameBgActive))
  count = count + push_if(ctx, ImGui, ImGui.Col_CheckMark, pick("CheckMark", c.CheckMark))

  count = count + push_if(ctx, ImGui, ImGui.Col_TitleBg, pick("TitleBg", c.TitleBg))
  count = count + push_if(ctx, ImGui, ImGui.Col_TitleBgActive, pick("TitleBgActive", c.TitleBgActive))
  count = count + push_if(ctx, ImGui, ImGui.Col_TitleBgCollapsed, pick("TitleBgCollapsed", c.TitleBgCollapsed))

  count = count + push_if(ctx, ImGui, ImGui.Col_Button, pick("Button", c.Button))
  count = count + push_if(ctx, ImGui, ImGui.Col_ButtonHovered, pick("ButtonHovered", c.ButtonHovered))
  count = count + push_if(ctx, ImGui, ImGui.Col_ButtonActive, pick("ButtonActive", c.ButtonActive))

  count = count + push_if(ctx, ImGui, ImGui.Col_Text, pick("Text", c.Text))
  count = count + push_if(ctx, ImGui, ImGui.Col_TextDisabled, pick("TextDisabled", c.TextDisabled))
  count = count + push_if(ctx, ImGui, ImGui.Col_TextSelectedBg, pick("TextSelectedBg", c.TextSelectedBg))

  count = count + push_if(ctx, ImGui, ImGui.Col_ResizeGrip, pick("ResizeGrip", c.ResizeGrip))
  count = count + push_if(ctx, ImGui, ImGui.Col_ResizeGripHovered, pick("ResizeGripHovered", c.ResizeGripHovered))
  count = count + push_if(ctx, ImGui, ImGui.Col_ResizeGripActive, pick("ResizeGripActive", c.ResizeGripActive))

  count = count + push_if(ctx, ImGui, ImGui.Col_Separator, pick("Separator", c.Separator))
  count = count + push_if(ctx, ImGui, ImGui.Col_SeparatorHovered, pick("SeparatorHovered", c.SeparatorHovered))
  count = count + push_if(ctx, ImGui, ImGui.Col_SeparatorActive, pick("SeparatorActive", c.SeparatorActive))

  count = count + push_if(ctx, ImGui, ImGui.Col_Tab, pick("Tab", c.Tab))
  count = count + push_if(ctx, ImGui, ImGui.Col_TabHovered, pick("TabHovered", c.TabHovered))
  count = count + push_if(ctx, ImGui, ImGui.Col_TabActive, pick("TabActive", c.TabActive))
  count = count + push_if(ctx, ImGui, ImGui.Col_TabUnfocused, pick("TabUnfocused", c.TabUnfocused))
  count = count + push_if(ctx, ImGui, ImGui.Col_TabUnfocusedActive, pick("TabUnfocusedActive", c.TabUnfocusedActive))

  count = count + push_if(ctx, ImGui, ImGui.Col_WindowBg, pick("WindowBg", c.WindowBg))
  count = count + push_if(ctx, ImGui, ImGui.Col_PopupBg, pick("PopupBg", c.PopupBg))
  count = count + push_if(ctx, ImGui, ImGui.Col_ScrollbarBg, pick("ScrollbarBg", c.ScrollbarBg))

  count = count + push_if(ctx, ImGui, ImGui.Col_Header, pick("Header", c.Header))
  count = count + push_if(ctx, ImGui, ImGui.Col_HeaderHovered, pick("HeaderHovered", c.HeaderHovered))
  count = count + push_if(ctx, ImGui, ImGui.Col_HeaderActive, pick("HeaderActive", c.HeaderActive))

  count = count + push_if(ctx, ImGui, ImGui.Col_NavHighlight, pick("NavHighlight", c.NavHighlight))

  count = count + push_if(ctx, ImGui, ImGui.Col_TableRowBg, pick("TableRowBg", c.TableRowBg))
  count = count + push_if(ctx, ImGui, ImGui.Col_TableRowBgAlt, pick("TableRowBgAlt", c.TableRowBgAlt))
  count = count + push_if(ctx, ImGui, ImGui.Col_TableBorderLight, pick("TableBorderLight", c.TableBorderLight))
  count = count + push_if(ctx, ImGui, ImGui.Col_TableBorderStrong, pick("TableBorderStrong", c.TableBorderStrong))
  count = count + push_if(ctx, ImGui, ImGui.Col_TableHeaderBg, pick("TableHeaderBg", c.TableHeaderBg))

  count = count + push_if(ctx, ImGui, ImGui.Col_SliderGrab, pick("SliderGrab", c.SliderGrab))
  count = count + push_if(ctx, ImGui, ImGui.Col_SliderGrabActive, pick("SliderGrabActive", c.SliderGrabActive))

  count = count + push_if(ctx, ImGui, ImGui.Col_PlotLines, pick("PlotLines", c.PlotLines))
  count = count + push_if(ctx, ImGui, ImGui.Col_PlotLinesHovered, pick("PlotLinesHovered", c.PlotLinesHovered))
  count = count + push_if(ctx, ImGui, ImGui.Col_PlotHistogram, pick("PlotHistogram", c.PlotHistogram))
  count = count + push_if(ctx, ImGui, ImGui.Col_PlotHistogramHovered, pick("PlotHistogramHovered", c.PlotHistogramHovered))

  count = count + push_if(ctx, ImGui, ImGui.Col_DockingPreview, pick("DockingPreview", c.DockingPreview))

  count = count + push_if(ctx, ImGui, ImGui.Col_Border, pick("Border", c.Border))

  return count
end

function M.pop(ctx, ImGui, count)
  if count and count > 0 then
    ImGui.PopStyleColor(ctx, count)
  end
end

return M
