-- @description RadialMenu Tool - Runtime config hot reload
-- @about
--   Handles ExtState-driven config reload and dependent refresh.

local M = {}

local config_manager = require("config_manager")
local styles = require("gui.styles")
local submenu_bake_cache = require("gui.submenu_bake_cache")

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
    -- 【极速缓存系统】配置重新加载时清除烘焙缓存
    submenu_bake_cache.clear()
  end

  R.last_config_update_time = current_update_time
  return true
end

return M
