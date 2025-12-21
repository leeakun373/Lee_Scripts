-- @description Lee_FXMiner - Saver
-- @author Lee
-- @version 2.0.1
-- @about Save selected track FX Chain into FXChains with shadow DB
-- @noindex

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

-- NOTE:
-- Saver 优先使用原生 GetTrackStateChunk 提取 <FXCHAIN>，不强制要求 SWS。
-- 只有当 chunk 提取失败时才会尝试 SWS 剪贴板兜底（届时再提示安装 SWS）。

local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local root = script_dir() -- .../Lee_Scripts/FX/FXMiner/
local sep = package.config:sub(1, 1)

local function path_join(a, b)
  if not a or a == "" then return b end
  if not b or b == "" then return a end
  a = tostring(a)
  b = tostring(b)
  a = a:gsub("[\\/]+$", "")
  b = b:gsub("^[\\/]+", "")
  return a .. sep .. b
end

-- Add local src modules
package.path = path_join(root, "src") .. sep .. "?.lua;" .. package.path

-- Add Shared/Toolbox framework (two levels up: FX/FXMiner -> Lee_Scripts)
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
      "FXMiner failed to load file: " .. tostring(label or abs_path) .. "\n\n" ..
      tostring(err),
      "FXMiner",
      0
    )
    return nil
  end
  local ok, res = pcall(f)
  if ok then return res end
  r.ShowMessageBox(
    "FXMiner failed to execute file: " .. tostring(label or abs_path) .. "\n\n" ..
    tostring(res),
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

-- IMPORTANT:
-- Toolbox 的 app_state 会先 require("config")（Toolbox 的 config.lua），导致模块名冲突。
-- 这里改用 loadfile 直接加载 FXMiner 自己的 src/config.lua，绕开 require 缓存冲突。
local Config = safe_loadfile(path_join(path_join(root, "src"), "config.lua"), "FXMiner/src/config.lua")
local DB = safe_require("db.db")  -- 直接使用模块化版本
local FXEngine = safe_require("fx_engine")
local GuiSaver = safe_require("gui_saver")
if not Config or not DB or not FXEngine or not GuiSaver then return end

local app = App.new(ImGui, {
  title = "FXMiner - Saver",
  ext_section = "FXMiner_Saver",
})

-- Saver window wants to behave like modal
app.state.always_on_top = true

local db = DB:new(Config)
db:ensure_initialized(root)

GuiSaver.init(app, db, FXEngine, Config)

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
      GuiSaver.draw(app.ctx)
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
