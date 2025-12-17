-- @description RadialMenu Tool - Settings state
-- @about
--   Central state initialization/reset helpers for settings UI.

local M = {}

function M.new()
  return {
    is_modified = false,
    selected_sector_index = nil,
    selected_slot_index = nil,
    current_preset_name = "Default",
    save_feedback_time = 0,
    search = { actions = "", fx = "" },
  }
end

return M
