-- Shared/Toolbox/framework/ui_theme.lua
-- 把外观层（colors/style/font）组合成一个“每帧 begin/end”。

local Colors = require("ui_colors")
local Style = require("ui_style")
local Font = require("ui_font")

local M = {}

function M.begin(app)
  local ctx = app.ctx
  local ImGui = app.ImGui

  app._theme = app._theme or {}

  -- 字体
  app._theme.fonts = Font.ensure(ctx, ImGui, {
    scale = app.state.scale or 1,
    base_size = app.state.font_size or 14,
    font_name = app.state.font_name,
  })

  -- StyleVar + Colors
  app._theme.style_count = Style.push(ctx, ImGui, app.state.scale or 1, app.state.style_overrides)
  app._theme.color_count = Colors.push(ctx, ImGui, app.state.color_overrides)

  -- 聚焦时强化边框（模仿 nvk 的 border_focused）
  if app.focused and Colors.semantic.border_focused and ImGui.Col_Border then
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, Colors.semantic.border_focused)
    app._theme.color_count = app._theme.color_count + 1
  end

  -- 默认字体
  if app._theme.fonts and app._theme.fonts.default then
    ImGui.PushFont(ctx, app._theme.fonts.default)
    app._theme.font_pushed = true
  end
end

function M.end_(app)
  local ctx = app.ctx
  local ImGui = app.ImGui
  local t = app._theme or {}

  if t.font_pushed then
    ImGui.PopFont(ctx)
  end

  Colors.pop(ctx, ImGui, t.color_count)
  Style.pop(ctx, ImGui, t.style_count)

  app._theme = t
end

function M.destroy(app)
  Font.detach(app.ctx, app.ImGui)
end

return M
