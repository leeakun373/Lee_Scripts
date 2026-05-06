-- @description Lee_UI - Demo (entry)
-- @version 0.2
-- @author Lee
-- @about
--   入口脚本：转到 Shared/Toolbox 中的 Demo。

local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local root = script_dir() -- ...\Lee_Scripts\
local target = root .. "Shared/Toolbox/Demo_UI.lua"

local ok, err = pcall(dofile, target)
if not ok then
  reaper.ShowMessageBox("Failed to run Shared Toolbox demo:\n" .. tostring(err) .. "\n\nPath:\n" .. target, "Lee_UI", 0)
end
