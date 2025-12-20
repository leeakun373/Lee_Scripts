-- FXMiner/src/db/db_fields.lua
-- 字段配置管理

local json = require("json")
local Utils = require("db.db_utils")

local Fields = {}

-- Default fields config: simple array of {key, label}
local function default_fields_config()
  return {
    { key = "Designer", label = "Designer" },
    { key = "Project",  label = "Project" },
    { key = "Keywords", label = "Keywords" },
  }
end

-- Default tag config (legacy)
local function default_tag_config()
  return {
    Category = {
      type = "single",
      options = { "Processing", "Design", "Utility" },
    },
    Project = {
      type = "multi",
      options = { "Hero_Wukong", "General_Library" },
    },
    Element = {
      type = "multi",
      options = { "Fire", "Water", "Magic", "Tech" },
    },
  }
end

-- Initialize fields methods on DB instance
function Fields.init(DB)
  -- Load fields config from file
  function DB:load_fields_config(script_root)
    local root = tostring(script_root or "")
    if root == "" then
      return false, "script_root missing"
    end

    local path = Utils.path_join(root, "config_fields.json")
    self.fields_config_path = path

    if not Utils.file_exists(path) then
      local ok, err = json.save_to_file(default_fields_config(), path, true)
      if not ok then
        return false, err
      end
    end

    local data, err = json.load_from_file(path)
    if not data then
      return false, err
    end

    -- Accept array format; fallback to default if not array
    if type(data) ~= "table" or #data == 0 then
      data = default_fields_config()
    end

    self.fields_config = data
    return true
  end

  -- Get fields config (with fallback to default)
  function DB:get_fields_config()
    return self.fields_config or default_fields_config()
  end

  -- Get fields config path
  function DB:get_fields_config_path()
    return self.fields_config_path
  end

  -- Load tag config (legacy)
  function DB:load_tag_config(script_root)
    -- script_root: .../Lee_Scripts/FX/FXMiner/
    local root = tostring(script_root or "")
    if root == "" then
      return false, "script_root missing"
    end

    local sep = self.cfg and self.cfg.PATH_SEP or package.config:sub(1, 1)
    local path = root:gsub("[\\/]+$", "") .. sep .. "config_tags.json"
    self.tag_config_path = path

    if not Utils.file_exists(path) then
      local ok, err = json.save_to_file(default_tag_config(), path, true)
      if not ok then
        return false, err
      end
    end

    local data, err = json.load_from_file(path)
    if not data then
      return false, err
    end

    self.tag_config = data
    return true
  end

  -- Get tag config (legacy)
  function DB:get_tag_config()
    return self.tag_config or {}
  end

  -- Get tag config path (legacy)
  function DB:get_tag_config_path()
    return self.tag_config_path
  end
end

return Fields

