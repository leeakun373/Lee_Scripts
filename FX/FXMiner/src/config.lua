-- FXMiner/src/config.lua
-- 配置与路径规则（尽量保持“纯配置 + 少量通用路径函数”）

local r = reaper

local M = {}

M.SCHEMA_VERSION = "1.0"

-- Path helpers
M.PATH_SEP = package.config:sub(1, 1)

function M.path_join(...)
  local sep = M.PATH_SEP
  local parts = {...}
  local out = ""
  for i = 1, #parts do
    local p = tostring(parts[i] or "")
    if p ~= "" then
      p = p:gsub("[\\/]+", sep)
      if out == "" then
        out = p
      else
        out = out:gsub("[\\/]+$", "") .. sep .. p:gsub("^[\\/]+", "")
      end
    end
  end
  return out
end

function M.norm_slash(p)
  return tostring(p or ""):gsub("\\", "/")
end

function M.strip_trailing_slash(p)
  p = tostring(p or "")
  p = p:gsub("[\\/]+$", "")
  return p
end

-- FXChains roots
M.REAPER_RESOURCE_PATH = (r and r.GetResourcePath) and r.GetResourcePath() or ""
M.FXCHAINS_ROOT = M.path_join(M.REAPER_RESOURCE_PATH, "FXChains")

-- Data store (non-intrusive)
M.DATA_DIR_NAME = "_FXMiner_Data"
M.DATA_DIR_PATH = M.path_join(M.FXCHAINS_ROOT, M.DATA_DIR_NAME)

M.DB_FILENAME = "FXMiner_Local_DB.json"
M.DB_PATH = M.path_join(M.DATA_DIR_PATH, M.DB_FILENAME)

-- Optional team publish
-- Set this to your team's shared folder path (e.g. "\\\\NAS\\Team\\FXChains" or "C:/temp/Fake_Team_Share")
M.TEAM_PUBLISH_PATH = "C:/temp/Fake_Team_Share" 

-- Team database path (full path to the .json file)
M.TEAM_DB_PATH = "C:/temp/Fake_Team_Share/server_db.json"

-- Get full path to team DB
function M.get_team_db_path()
  -- If we have a direct path defined, use it; otherwise derive from publish path
  if M.TEAM_DB_PATH and M.TEAM_DB_PATH ~= "" then
    return M.TEAM_DB_PATH
  end
  return M.path_join(M.TEAM_PUBLISH_PATH, "server_db.json")
end

-- Default tags (3 x 6)
M.DEFAULT_TAGS = {
  "SFX", "Ambience", "Bass", "Drums", "Kick", "Snare",
  "Vocal", "FX", "Distortion", "Delay", "Reverb", "Filter",
  "LoFi", "Clean", "Master", "Utility", "Synth", "Texture",
}

-- Excluded physical folders under FXChains
M.EXCLUDED_FOLDERS = {
  [M.DATA_DIR_NAME] = true,
}

return M
