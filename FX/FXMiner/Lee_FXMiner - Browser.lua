-- @description Lee_FXMiner - Browser
-- @author Lee
-- @version 1.0.7
-- @about Browse/search FXChains via shadow DB
-- @provides
--   [main] Lee_FXMiner - Saver.lua
--   src/config.lua
--   src/db/db.lua
--   src/db/db_core.lua
--   src/db/db_entries.lua
--   src/db/db_fields.lua
--   src/db/db_folders.lua
--   src/db/db_team_sync.lua
--   src/db/db_utils.lua
--   src/fx_engine.lua
--   src/gui_browser.lua
--   src/gui_browser/gui_delete_dialog.lua
--   src/gui_browser/gui_folders.lua
--   src/gui_browser/gui_inspector.lua
--   src/gui_browser/gui_list.lua
--   src/gui_browser/gui_settings.lua
--   src/gui_browser/gui_state.lua
--   src/gui_browser/gui_topbar.lua
--   src/gui_browser/gui_utils.lua
--   src/gui_saver.lua
--   src/json.lua
--   config_fields.json
--   folders_db.json

local r = reaper

-- ReaImGui required
if not r or not r.APIExists or not r.APIExists("ImGui_GetBuiltinPath") then
  r.ShowMessageBox(
    "This script requires ReaImGui extension.\n\nInstall via ReaPack: ReaTeam Extensions -> ReaImGui.",
    "FXMiner",
    0
  )
  return
end

local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local root = script_dir() -- .../Lee_Scripts/FX/FXMiner/
local sep = package.config:sub(1, 1)

local function path_join(a, b)
  if not a or a == "" then return b end
  if not b or b == "" then return a end
  a = tostring(a):gsub("[\\/]+$", "")
  b = tostring(b):gsub("^[\\/]+", "")
  return a .. sep .. b
end

-- Add local src modules
package.path = path_join(root, "src") .. sep .. "?.lua;" .. package.path

-- Add Shared/Toolbox framework
local lee_root = root:gsub("[\\/]+$", "")
lee_root = lee_root:match("^(.*)[\\/]FX[\\/].-$") or (root .. ".." .. sep .. "..")
local toolbox_framework = path_join(path_join(lee_root, "Shared"), path_join("Toolbox", "framework"))
package.path = toolbox_framework .. sep .. "?.lua;" .. package.path

local function safe_require(mod)
  local ok, res = pcall(require, mod)
  if ok then return res end
  r.ShowMessageBox(
    "FXMiner failed to load module: " .. tostring(mod) .. "\n\n" ..
    tostring(res) .. "\n\npackage.path:\n" .. tostring(package.path),
    "FXMiner",
    0
  )
  return nil
end

local function safe_loadfile(abs_path, label)
  local f, err = loadfile(abs_path)
  if not f then
    r.ShowMessageBox(
      "FXMiner failed to load file: " .. tostring(label or abs_path) .. "\n\n" .. tostring(err),
      "FXMiner",
      0
    )
    return nil
  end
  local ok, res = pcall(f)
  if ok then return res end
  r.ShowMessageBox(
    "FXMiner failed to execute file: " .. tostring(label or abs_path) .. "\n\n" .. tostring(res),
    "FXMiner",
    0
  )
  return nil
end

local bootstrap = safe_require("bootstrap")
if not bootstrap then return end
local ImGui = bootstrap.ensure_imgui("0.9")
if not ImGui then return end

local app_mod = safe_require("app")
local Theme = safe_require("ui_theme")
local AppState = safe_require("app_state")
if not app_mod or not Theme or not AppState then return end
local App = app_mod.App

-- IMPORTANT: avoid conflict with Toolbox's framework/config.lua
local Config = safe_loadfile(path_join(path_join(root, "src"), "config.lua"), "FXMiner/src/config.lua")
local DB = safe_require("db.db")  -- 直接使用模块化版本
local GuiBrowser = safe_require("gui_browser")
if not Config or not DB or not GuiBrowser then return end

local app = App.new(ImGui, {
  title = "FXMiner - Browser",
  ext_section = "FXMiner_Browser",
})

local db = DB:new(Config)
db:ensure_initialized(root)

GuiBrowser.init(app, db, Config)

local destroyed = false
r.atexit(function()
  if destroyed then return end
  destroyed = true
  pcall(function()
    Theme.destroy(app)
    app:destroy()
  end)
end)

local function loop()
  Theme.begin(app)

  local visible, open
  if app.open == false then
    visible, open = false, false
  else
    visible, open = app:begin_window()
    if visible then
      GuiBrowser.draw(app.ctx)
    end
    app:end_window()
    if app.open == false then
      open = false
    end
  end

  Theme.end_(app)

  if open then
    AppState.tick(app, app.state.low_cpu and 2.0 or 0.75)
    r.defer(loop)
  else
    if not destroyed then
      destroyed = true
      Theme.destroy(app)
      app:destroy()
    end
  end
end

r.defer(loop)
