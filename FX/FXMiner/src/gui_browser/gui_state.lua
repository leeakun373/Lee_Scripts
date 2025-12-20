-- FXMiner/src/gui_browser/gui_state.lua
-- 全局状态管理和用户配置

local json = require("json")

local State = {}

-- Global state table
local state = {
  search = "",
  selected_folder_id = -1, -- -1 == All, >=0 == virtual folder id
  selected_rel = nil,

  -- Multi-selection support
  selected_items = {}, -- rel_path -> true (set of selected items)
  last_clicked_idx = nil, -- for shift-click range selection

  -- inspector edits
  edit_name = "",
  edit_desc = "",
  category_idx = 0,

  field_inputs = {}, -- key -> current input string
  status = "",

  -- new folder modal
  new_folder_name = "",
  show_new_folder_popup = false,

  -- drag & drop (external drop)
  dnd_name = nil,

  -- folder UI
  folder_open = {}, -- id -> bool
  folder_rename_id = nil,
  folder_rename_text = "",
  folder_rename_init = false,

  -- library tree UI
  library_open = {}, -- node_id -> bool

  -- icons: using emojis only
  icon_plus = "➕",
  icon_folder = "📁",
  icon_folder_add = "🗂️",
  icon_delete = "🗑️",

  -- Context tracking: continuously track cursor context for accurate item/track detection
  -- 0 = TCP (track panel), 1 = Items/Arrange, 2 = Envelopes
  last_valid_context = -1,

  -- Settings panel
  show_settings = false,
  settings_team_path = "",
  settings_team_path_valid = false,

  -- Library mode: "local" or "team"
  library_mode = "local",

  -- Team sync state
  team_entries = {},
  team_sync_status = "",
  team_last_sync = 0,

  -- Sync in progress flag
  sync_in_progress = false,

  -- Delete confirmation dialog
  show_delete_confirm = false,
  delete_target_rel = nil,
  delete_target_name = nil,
  delete_selected_items = false,

  -- Library filter: nil or { field = "Project", value = "TFT" }
  library_filter = nil,
}

-- User config file path
local function get_user_config_path(Config)
  if not Config or not Config.DATA_DIR_PATH then return nil end
  local sep = Config.PATH_SEP or package.config:sub(1, 1)
  return Config.DATA_DIR_PATH .. sep .. "user_config.json"
end

-- Load user config
local function load_user_config(Config)
  local config_path = get_user_config_path(Config)
  if not config_path then return end
  
  local f = io.open(config_path, "r")
  if not f then return end
  
  local content = f:read("*all")
  f:close()
  
  if not content or content == "" then return end
  
  local ok, data = pcall(function() return json.decode(content) end)
  if ok and type(data) == "table" then
    -- Load team publish path
    if data.team_publish_path and data.team_publish_path ~= "" then
      Config.TEAM_PUBLISH_PATH = data.team_publish_path
      -- IMPORTANT: Clear TEAM_DB_PATH so get_team_db_path() will derive it from TEAM_PUBLISH_PATH
      -- Set to empty string (not nil) to ensure get_team_db_path() uses TEAM_PUBLISH_PATH
      Config.TEAM_DB_PATH = ""
    end
  end
end

-- Save user config
local function save_user_config(Config)
  local config_path = get_user_config_path(Config)
  if not config_path then return false end
  
  local data = {
    team_publish_path = Config.TEAM_PUBLISH_PATH or "",
  }
  
  local ok, json_str = pcall(function() return json.encode(data) end)
  if not ok or not json_str then return false end
  
  -- Ensure directory exists
  local dir = config_path:match("^(.*)[\\/]")
  if dir then
    local r = reaper
    if r and r.RecursiveCreateDirectory then
      pcall(function() r.RecursiveCreateDirectory(dir, 0) end)
    end
  end
  
  local f = io.open(config_path, "w")
  if not f then return false end
  
  f:write(json_str)
  f:close()
  return true
end

-- Initialize state module
function State.init(Config)
  -- Load user config
  load_user_config(Config)
  
  -- Initialize settings_team_path from Config
  state.settings_team_path = Config.TEAM_PUBLISH_PATH or ""
  
  -- Reset state
  state.search = ""
  state.selected_folder_id = -1
  state.selected_rel = nil
  state.selected_items = {}
  state.last_clicked_idx = nil
  state.edit_name = ""
  state.edit_desc = ""
  state.category_idx = 0
  state.field_inputs = {}
  state.status = ""
  state.new_folder_name = ""
  state.show_new_folder_popup = false
  state.sync_in_progress = false
  state.team_sync_status = ""
  state.show_delete_confirm = false
  state.delete_target_rel = nil
  state.delete_target_name = nil
  state.delete_selected_items = false
  state.library_filter = nil
end

-- Get state table
function State.get()
  return state
end

-- Save user config (exported function)
function State.save_user_config(Config)
  return save_user_config(Config)
end

return State

