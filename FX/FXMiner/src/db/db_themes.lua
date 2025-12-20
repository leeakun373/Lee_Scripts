-- FXMiner/src/db/db_themes.lua
-- 主题数据管理：加载和管理 themes_db.json

local json = require("json")
local Utils = require("db.db_utils")

local Themes = {}

-- Initialize themes methods on DB instance
function Themes.init(DB)
  -- Load themes database from file
  function DB:load_themes_db(script_root)
    local root = tostring(script_root or "")
    if root == "" then
      return false, "script_root missing"
    end

    local sep = self.cfg and self.cfg.PATH_SEP or package.config:sub(1, 1)
    local path = root:gsub("[\\/]+$", "") .. sep .. "themes_db.json"
    self.themes_db_path = path

    if not Utils.file_exists(path) then
      -- If themes_db.json doesn't exist, initialize with empty structure
      self.themes_data = {
        themes = {},
        all_keywords = {}
      }
      return true
    end

    local data, err = json.load_from_file(path)
    if not data then
      return false, err
    end

    -- Ensure structure
    if type(data) ~= "table" then
      data = { themes = {}, all_keywords = {} }
    end
    if type(data.themes) ~= "table" then
      data.themes = {}
    end

    self.themes_data = data
    return true
  end

  -- Get all theme names (sorted)
  function DB:get_all_themes()
    if not self.themes_data or type(self.themes_data.themes) ~= "table" then
      return {}
    end

    local themes = {}
    for theme_name, _ in pairs(self.themes_data.themes) do
      themes[#themes + 1] = tostring(theme_name)
    end

    -- Sort alphabetically
    table.sort(themes, function(a, b)
      return a:lower() < b:lower()
    end)

    return themes
  end

  -- Get keywords for a specific theme
  function DB:get_keywords_for_theme(theme_name)
    if not self.themes_data or type(self.themes_data.themes) ~= "table" then
      return {}
    end

    theme_name = tostring(theme_name or "")
    if theme_name == "" then
      return {}
    end

    local keywords = self.themes_data.themes[theme_name]
    if type(keywords) ~= "table" then
      return {}
    end

    -- Return a copy to avoid external modification
    local result = {}
    for _, kw in ipairs(keywords) do
      result[#result + 1] = tostring(kw)
    end

    return result
  end

  -- Get themes database path
  function DB:get_themes_db_path()
    return self.themes_db_path
  end
end

return Themes

