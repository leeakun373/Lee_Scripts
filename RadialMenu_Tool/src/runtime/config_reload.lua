-- @description RadialMenu Tool - Runtime config hot reload
-- @about
--   Handles ExtState-driven config reload and dependent refresh.

local M = {}

local config_manager = require("config_manager")
local styles = require("gui.styles")
local submenu_bake_cache = require("gui.submenu_bake_cache")
local submenu_cache = require("gui.submenu_cache")

-- Returns true if reloaded.
function M.maybe_reload(R)
  local current_update_time = reaper.GetExtState("RadialMenu", "ConfigUpdated")
  if not current_update_time or current_update_time == "" then
    return false
  end

  if R.last_config_update_time == nil then
    R.last_config_update_time = current_update_time
    return false
  end

  if R.last_config_update_time == current_update_time then
    return false
  end

  R.config = config_manager.load()
  if R.config then
    styles.init_from_config(R.config)
    local diameter = (R.config.menu.outer_radius or 200) * 2 + 20
    R.window_width = diameter
    R.window_height = diameter
    -- 【第三阶段修复】配置重新加载时清除所有缓存（烘焙缓存和子菜单缓存）
    -- 确保从 1 个扇区切换到 12 个扇区（或反之）时，缓存能无缝同步
    submenu_bake_cache.clear()
    submenu_cache.clear()
    
    -- 清除子菜单状态，避免切换后残留
    if R then
      R.clicked_sector = nil
      R.show_submenu = false
      R.last_hover_sector_id = nil
    end
  end

  R.last_config_update_time = current_update_time
  return true
end

return M
