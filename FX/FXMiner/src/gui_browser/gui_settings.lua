-- FXMiner/src/gui_browser/gui_settings.lua
-- 设置面板

local W = require("widgets")

local GuiSettings = {}
local App, DB, Config, Engine = nil, nil, nil, nil
local state, save_config_func = nil, nil

function GuiSettings.init(_App, _DB, _Config, _Engine, _state, _save_func)
  App = _App
  DB = _DB
  Config = _Config
  Engine = _Engine
  state = _state
  save_config_func = _save_func
end

function GuiSettings.draw(ctx)
  local ImGui = App.ImGui

  if ImGui.Button(ctx, "🔙 Back") then
    state.show_settings = false
  end
  ImGui.SameLine(ctx)
  W.separator_text(ctx, ImGui, "Settings")

  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- === Database ===
  W.separator_text(ctx, ImGui, "💽 Database")
  ImGui.Text(ctx, "Path: " .. (Config.DB_PATH or ""))
  
  if ImGui.Button(ctx, "Rescan All Files") then
    DB:refresh_db_from_disk(state.status)
    state.status = "Rescan started..."
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
  
  -- === Team ===
  W.separator_text(ctx, ImGui, "☁️ Team / Publish")
  local team_path = state.settings_team_path or ""
  local changed_tp, new_tp = ImGui.InputText(ctx, "Publish Path", team_path)
  if changed_tp then
    state.settings_team_path = new_tp
  end
  
  if ImGui.Button(ctx, "Save Configuration") then
    Config.TEAM_PUBLISH_PATH = state.settings_team_path
    if save_config_func then
      if save_config_func(Config) then
        state.status = "Settings saved."
      else
        state.status = "Error saving settings."
      end
    end
  end
end

return GuiSettings
