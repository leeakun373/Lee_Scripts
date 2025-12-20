-- FXMiner/src/gui_browser.lua
-- 主入口文件：整合所有 GUI 子模块

local GuiBrowser = {}

-- Require sub-modules
local State = require("gui_browser.gui_state")
local Utils = require("gui_browser.gui_utils")
local Topbar = require("gui_browser.gui_topbar")
local Settings = require("gui_browser.gui_settings")
local Folders = require("gui_browser.gui_folders")
local List = require("gui_browser.gui_list")
local Inspector = require("gui_browser.gui_inspector")
local Preview = require("gui_browser.gui_preview")
local DeleteDialog = require("gui_browser.gui_delete_dialog")

-- Global references (will be set in init)
local App, DB, Config, Engine = nil, nil, nil, nil
local state = nil

-- Drag & drop update (external drop)
local function dnd_update(ctx)
  local ImGui = App.ImGui
  local r = reaper

  if not (ImGui.GetDragDropPayload and ImGui.GetDragDropPayload(ctx)) then
    state.dnd_name = nil
    return
  end

  if state.dnd_name and ImGui.SetTooltip then
    ImGui.SetTooltip(ctx, state.dnd_name)
  end

  local x, y = r.GetMousePosition()
  local track = nil
  local take = nil

  if r.GetItemFromPoint and r.GetMediaItem_Track then
    local item
    item, take = r.GetItemFromPoint(x, y, false)
    if item then
      track = r.GetMediaItem_Track(item)
    end
  end

  if (not track) and r.GetThingFromPoint then
    local t = r.GetThingFromPoint(x, y)
    if t then track = t end
  end

  if not track and ImGui.IsWindowHovered and ImGui.HoveredFlags_AnyWindow then
    if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_AnyWindow) then
      return
    end
  end

  if ImGui.AcceptDragDropPayload then
    local ok, rv, payload = pcall(function()
      local rrv, pp = ImGui.AcceptDragDropPayload(ctx, "FXMINER_ENTRY")
      return rrv, pp
    end)
    if ok and rv and payload and payload ~= "" then
      local rel = tostring(payload)
      local e = DB:find_entry_by_rel(rel)
      if e then
        local abs = DB:rel_to_abs(e.rel_path)
        local ok2, err
        if take then
          ok2, err = Utils.safe_append_fxchain_to_take(take, abs)
          if not ok2 then
            ok2, err = Utils.safe_append_fxchain_to_track(track, abs)
          end
        else
          ok2, err = Utils.safe_append_fxchain_to_track(track, abs)
        end
        state.status = ok2 and ("Loaded: " .. tostring(e.name or "")) or ("Load failed: " .. tostring(err))
      end
      state.dnd_name = nil
    end
  end
end

function GuiBrowser.init(app_ctx, db_instance, cfg)
  App = app_ctx
  DB = db_instance
  Config = cfg

  State.init(Config)

  local ok_eng, eng = pcall(require, "fx_engine")
  if ok_eng then
    Engine = eng
  else
    local script_dir = debug.getinfo(1, "S").source:match("^@(.+[\\/])")
    local eng_path = (script_dir or "") .. "fx_engine.lua"
    local f, err = loadfile(eng_path)
    if f then Engine = f() end
  end

  state = State.get()

  -- Font loading disabled - using default font with Emojis

  Utils.init(App, DB, Config, state)
  List.init(state, App, DB, Config, Utils)
  Topbar.init(App, DB, Config, Engine, state, Utils, List)
  Settings.init(App, DB, Config, Engine, state, State.save_user_config)
  Folders.init(state, App, DB, Config, Utils)
  Inspector.init(state, App, DB, Config, Utils, List)
  Preview.init(state, App, DB, Config)
  DeleteDialog.init(state, App, DB, Config, Utils, List)
end

function GuiBrowser.draw(ctx)
  local ImGui = App.ImGui
  local focus = reaper.GetCursorContext and reaper.GetCursorContext() or -1
  if focus ~= -1 then state.last_valid_context = focus end

  if state.show_delete_confirm and ImGui.OpenPopup then
    ImGui.OpenPopup(ctx, "确认删除##delete_confirm")
  end
  DeleteDialog.draw(ctx)

  Topbar.draw(ctx)
  dnd_update(ctx)

  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)

  if state.show_settings then
    if ImGui.BeginChild(ctx, "##fxminer_settings", 0, avail_h, ImGui.ChildFlags_Border or 0) then
      Settings.draw(ctx)
      ImGui.EndChild(ctx)
    end
    return
  end

  -- Layout handling
  local layout = Config.layout or {}
  local folder_w = layout.folder_width or layout.folder_w or 240
  local inspector_w = layout.inspector_width or layout.inspector_w or 320
  local preview_w = layout.preview_width or layout.preview_w or 220

  local is_team_mode = (state.library_mode == "team")
  local actual_folder_w = is_team_mode and 0 or folder_w
  local list_w = math.max(100, avail_w - actual_folder_w - inspector_w - preview_w - 24)

  if not is_team_mode then
    if ImGui.BeginChild(ctx, "##fxminer_folders", folder_w, avail_h, ImGui.ChildFlags_Border or 0) then
      Folders.draw(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)
  end

  if ImGui.BeginChild(ctx, "##fxminer_list", list_w, avail_h, ImGui.ChildFlags_Border or 0) then
    List.draw(ctx)
    ImGui.EndChild(ctx)
  end
  ImGui.SameLine(ctx)

  if ImGui.BeginChild(ctx, "##fxminer_inspector", inspector_w, avail_h, ImGui.ChildFlags_Border or 0) then
    Inspector.draw(ctx)
    ImGui.EndChild(ctx)
  end
  ImGui.SameLine(ctx)

  if ImGui.BeginChild(ctx, "##fxminer_preview", preview_w, avail_h, ImGui.ChildFlags_Border or 0) then
    Preview.draw(ctx)
    ImGui.EndChild(ctx)
  end
end

return GuiBrowser
