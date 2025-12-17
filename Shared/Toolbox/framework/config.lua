-- Shared/Toolbox/framework/config.lua
-- ExtState 持久化配置：一份 config 表 + 可扩展字段。

local U = require("util")
local M = {}

M.defaults = {
  -- UI/行为
  scale = 1.0,
  always_on_top = false,
  low_cpu = false,

  -- 字体
  font_size = 14,
  font_name = nil, -- nil=系统默认（Windows 优先 Segoe UI）

  -- Demo/工具窗口
  show_demo_window = false,
  show_log = true,
  show_terminal = false,
  show_style_editor = false,
  show_theme_editor = false,

  -- 皮肤覆盖（可选）
  -- style_overrides: { WindowRounding=..., FramePadding={x,y}, ... }
  style_overrides = nil,
  -- color_overrides: { Col_WindowBg=u32, Col_Button=u32, ... }
  color_overrides = nil,
}

local function ext_section(app)
  return (app and app.ext_section) or "Toolbox_UI"
end

function M.load(app)
  local sec = ext_section(app)
  local raw = reaper.GetExtState(sec, "config")

  local cfg = U.deepcopy(M.defaults)
  if raw ~= "" then
    local t = U.deserialize(raw)
    if type(t) == "table" then
      for k, v in pairs(t) do
        cfg[k] = v
      end
    end
  end

  -- 兜底
  cfg.scale = tonumber(cfg.scale) or M.defaults.scale
  cfg.scale = U.clamp(cfg.scale, 0.5, 2.0)
  cfg.font_size = tonumber(cfg.font_size) or M.defaults.font_size
  cfg.font_size = math.floor(U.clamp(cfg.font_size, 8, 32))
  cfg.always_on_top = not not cfg.always_on_top
  cfg.low_cpu = not not cfg.low_cpu

  return cfg
end

function M.save(app, cfg)
  local sec = ext_section(app)
  local raw = U.serialize(cfg)
  reaper.SetExtState(sec, "config", raw, true)
end

return M
