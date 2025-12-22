-- FXMiner/src/config.lua
-- 【纯净版】配置与路径

local r = reaper
local M = {}

M.SCHEMA_VERSION = "1.0"
M.PATH_SEP = package.config:sub(1, 1)

function M.path_join(...)
  local sep = M.PATH_SEP
  local parts = {...}
  local out = ""
  for i = 1, #parts do
    local p = tostring(parts[i] or "")
    if p ~= "" then
      p = p:gsub("[\\/]+", sep)
      if out == "" then out = p else out = out:gsub("[\\/]+$", "") .. sep .. p:gsub("^[\\/]+", "") end
    end
  end
  return out
end

M.REAPER_RESOURCE_PATH = (r and r.GetResourcePath) and r.GetResourcePath() or ""
M.FXCHAINS_ROOT = M.path_join(M.REAPER_RESOURCE_PATH, "FXChains")
M.DATA_DIR_NAME = "_FXMiner_Data"
M.DATA_DIR_PATH = M.path_join(M.FXCHAINS_ROOT, M.DATA_DIR_NAME)
M.DB_FILENAME = "FXMiner_Local_DB.json"
M.DB_PATH = M.path_join(M.DATA_DIR_PATH, M.DB_FILENAME)

-- [关键] 默认布局参数 (初始界面显示更全)
M.layout = {
  folder_width = 200,     -- 左侧
  inspector_width = 280,  -- 右侧
  preview_width = 250     -- 最右预览
}

-- Team DB path helper function
-- Derives team DB path from TEAM_PUBLISH_PATH
function M.get_team_db_path()
  if M.TEAM_PUBLISH_PATH and M.TEAM_PUBLISH_PATH ~= "" then
    return M.path_join(M.TEAM_PUBLISH_PATH, "server_db.json")
  end
  -- Fallback to explicit TEAM_DB_PATH if set
  if M.TEAM_DB_PATH and M.TEAM_DB_PATH ~= "" then
    return M.TEAM_DB_PATH
  end
  return nil
end

return M
