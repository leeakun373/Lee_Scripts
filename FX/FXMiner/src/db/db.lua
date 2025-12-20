-- FXMiner/src/db/db.lua
-- 主入口：DB 类定义和模块协调

local Utils = require("db.db_utils")
local Core = require("db.db_core")
local Fields = require("db.db_fields")
local Entries = require("db.db_entries")
local Folders = require("db.db_folders")
local TeamSync = require("db.db_team_sync")
local Themes = require("db.db_themes")

local DB = {}
DB.__index = DB

-- Constructor
function DB:new(cfg)
  local o = setmetatable({}, self)
  o.cfg = cfg or require("config")
  o.data = nil
  o._index = {}
  -- legacy (previous static tags config)
  o.tag_config = nil
  o.tag_config_path = nil

  -- dynamic fields config (new)
  o.fields_config = nil
  o.fields_config_path = nil

  -- folders db (new)
  o.folders = nil
  o.folders_path = nil

  -- themes db (new)
  o.themes_data = nil
  o.themes_db_path = nil

  -- Initialize all modules
  Core.init(o)
  Fields.init(o)
  Entries.init(o)
  Folders.init(o)
  TeamSync.init(o)
  Themes.init(o)

  return o
end

-- Path accessors
function DB:db_dir()
  return self.cfg.DATA_DIR_PATH
end

function DB:db_path()
  return self.cfg.DB_PATH
end

-- Initialize environment: ensure directories and files exist
function DB:ensure_initialized(script_root)
  -- 1. Ensure data directory exists
  local data_dir = self:db_dir()
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(data_dir, 0)
  end

  -- 2. Load/initialize fields config
  self:load_fields_config(script_root)

  -- 3. Load/initialize themes DB
  self:load_themes_db(script_root)

  -- 4. Load/initialize folders DB
  self:load_folders(script_root)

  -- 5. Load main entries DB
  self:load()

  -- 6. Migrate entries after load (ensure defaults are applied)
  if self.data and type(self.data.entries) == "table" then
    for _, e in ipairs(self.data.entries) do
      self:_ensure_entry_defaults(e)
      -- 如果 keywords 不存在或为空，补一次
      if not e.keywords or e.keywords == "" then
        self:rebuild_keywords(e)
      end
      -- 如果 status 不存在或非法，补一次
      e.status = (e.status == "indexed" or e.status == "unindexed") and e.status or self:calc_status(e)
    end
    self:_reindex()
  end

  -- 7. Local scan and prune
  pcall(function()
    self:scan_fxchains()
    self:prune_missing_files()
    self:migrate_entries({ save = true })
  end)
  
  return true
end

return DB

