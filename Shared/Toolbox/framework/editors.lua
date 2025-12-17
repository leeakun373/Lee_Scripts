-- Shared/Toolbox/framework/editors.lua
-- Theme/Style 编辑器（简化版）：用于调试/微调配色和样式。

local Colors = require("ui_colors")
local Style = require("ui_style")

local M = {}

local function u32_to_rgba(ctx, ImGui, u32)
  return ImGui.ColorConvertU32ToDouble4(u32)
end

local function rgba_to_u32(ctx, ImGui, r, g, b, a)
  return ImGui.ColorConvertDouble4ToU32(r, g, b, a)
end

local function color_key_to_colconst(ImGui, key)
  if type(key) == "number" then return key end
  if type(key) ~= "string" then return nil end
  if key:match("^Col_") then
    return ImGui[key]
  end
  return ImGui["Col_" .. key]
end

local function ensure_tbl(t)
  if type(t) ~= "table" then return {} end
  return t
end

function M.draw_style(ctx, ImGui, app)
  app.state.style_overrides = ensure_tbl(app.state.style_overrides)
  local o = app.state.style_overrides

  ImGui.SetNextWindowSize(ctx, 420, 520, ImGui.Cond_FirstUseEver)
  local visible
  visible, app._style_open = ImGui.Begin(ctx, "Lee UI - Style", true)
  if visible then
    ImGui.Text(ctx, "StyleVar overrides")
    ImGui.Separator(ctx)

    local changed
    changed, app.state.scale = ImGui.SliderDouble(ctx, "Scale", app.state.scale, 0.5, 2.0, "%.2f")

    changed, app.state.font_size = ImGui.SliderInt(ctx, "Font Size", app.state.font_size, 8, 32, "%d")

    ImGui.Separator(ctx)

    -- 一组高影响的 rounding/padding
    changed, o.WindowRounding = ImGui.SliderDouble(ctx, "WindowRounding", o.WindowRounding or Style.defaults.WindowRounding, 0, 12, "%.0f")
    changed, o.FrameRounding = ImGui.SliderDouble(ctx, "FrameRounding", o.FrameRounding or Style.defaults.FrameRounding, 0, 12, "%.0f")
    changed, o.PopupRounding = ImGui.SliderDouble(ctx, "PopupRounding", o.PopupRounding or Style.defaults.PopupRounding, 0, 12, "%.0f")

    local wp = o.WindowPadding or Style.defaults.WindowPadding
    local rv, x, y = ImGui.SliderDouble2(ctx, "WindowPadding", wp[1], wp[2], 0, 20, "%.0f")
    if rv then o.WindowPadding = {x, y} end

    local fp = o.FramePadding or Style.defaults.FramePadding
    rv, x, y = ImGui.SliderDouble2(ctx, "FramePadding", fp[1], fp[2], 0, 20, "%.0f")
    if rv then o.FramePadding = {x, y} end

    local is = o.ItemSpacing or Style.defaults.ItemSpacing
    rv, x, y = ImGui.SliderDouble2(ctx, "ItemSpacing", is[1], is[2], 0, 20, "%.0f")
    if rv then o.ItemSpacing = {x, y} end

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Reset overrides") then
      app.state.style_overrides = nil
    end
  end
  ImGui.End(ctx)

  if app._style_open == false then
    app.state.show_style_editor = false
  end
end

function M.draw_theme(ctx, ImGui, app)
  app.state.color_overrides = ensure_tbl(app.state.color_overrides)
  local o = app.state.color_overrides

  ImGui.SetNextWindowSize(ctx, 420, 520, ImGui.Cond_FirstUseEver)
  local visible
  visible, app._theme_open = ImGui.Begin(ctx, "Lee UI - Theme", true)
  if visible then
    ImGui.Text(ctx, "Color overrides")
    ImGui.Separator(ctx)

    local function edit_col(label, key, default_u32)
      local u32 = o[key] or default_u32
      local rv = false

      -- 兼容性说明：
      -- 你这版 ReaImGui 的 ImGui_ColorEdit4 明确提示 “expected 4 arguments maximum”，
      -- 说明它支持的签名是 U32 版本（ctx,label,u32[,flags]），而不是 r,g,b,a 版本。
      -- 同时有些版本即使在 pcall 里也会把“参数错误”刷到控制台，所以这里避免调用错误签名。
      local ok

      -- 优先 4 参数（带 flags=0）
      ok, rv, u32 = pcall(ImGui.ColorEdit4, ctx, label, u32, 0)
      if not ok then
        -- 回退 3 参数
        ok, rv, u32 = pcall(ImGui.ColorEdit4, ctx, label, u32)
      end
      if ok and rv then
        o[key] = u32
      end

      -- 显示当前值
      ImGui.SameLine(ctx)
      ImGui.TextDisabled(ctx, string.format("0x%08X", o[key] or u32))
    end

    edit_col("WindowBg", "WindowBg", Colors.u32.WindowBg)
    edit_col("FrameBg", "FrameBg", Colors.u32.FrameBg)
    edit_col("Button", "Button", Colors.u32.Button)
    edit_col("TabActive", "TabActive", Colors.u32.TabActive)
    edit_col("CheckMark", "CheckMark", Colors.u32.CheckMark)
    edit_col("Border", "Border", Colors.u32.Border)

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Reset overrides") then
      app.state.color_overrides = nil
    end
  end
  ImGui.End(ctx)

  if app._theme_open == false then
    app.state.show_theme_editor = false
  end
end

return M
