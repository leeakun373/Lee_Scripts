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

  -- If not over a track/item and mouse is over our UI, don't consume payload
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
        -- Prefer take when dropping on item
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

  -- Initialize State module (loads user config and initializes state)
  State.init(Config)

  -- Load engine
  local ok_eng, eng = pcall(require, "fx_engine")
  if ok_eng then
    Engine = eng
  else
    -- Fallback to relative load if require fails
    local script_dir = debug.getinfo(1, "S").source:match("^@(.+[\\/])")
    local eng_path = (script_dir or "") .. "fx_engine.lua"
    local f, err = loadfile(eng_path)
    if f then
      Engine = f()
    end
  end

  -- Get state table from State module (already initialized by State.init())
  state = State.get()

  -- Icon font: prefer emoji (works well for "small icon" UI).
  do
    local ImGui = App.ImGui
    local ok, f = pcall(function()
      if ImGui.CreateFont and ImGui.Attach then
        local font_name
        if reaper.GetOS():match("Win") then
          font_name = "Segoe UI Emoji"
        elseif reaper.GetOS():match("OSX") then
          font_name = "Apple Color Emoji"
        else
          font_name = "Noto Color Emoji"
        end
        local font = ImGui.CreateFont(font_name, 14)
        ImGui.Attach(App.ctx, font)
        return font
      end
    end)
    if ok and f then
      state.icon_font = f
    end
  end

  -- Initialize all sub-modules
  Utils.init(App, DB, Config, state)
  List.init(state, App, DB, Config, Utils)  -- Initialize List first (Topbar needs it)
  Topbar.init(App, DB, Config, Engine, state, Utils, List)
  Settings.init(App, DB, Config, Engine, state, State.save_user_config)
  Folders.init(state, App, DB, Config, Utils)
  Inspector.init(state, App, DB, Config, Utils, List)
  DeleteDialog.init(state, App, DB, Config, Utils, List)
end

function GuiBrowser.draw(ctx)
  local ImGui = App.ImGui

  -- Context tracking: Update cursor context if we can get a valid value
  -- NVK style: only update when GetCursorContext returns valid (not -1)
  -- This preserves the last known context when user is inside ImGui window
  local focus = reaper.GetCursorContext and reaper.GetCursorContext() or -1
  if focus ~= -1 then
    state.last_valid_context = focus
  end

  -- Open delete confirmation popup if needed
  if state.show_delete_confirm and ImGui.OpenPopup then
    ImGui.OpenPopup(ctx, "确认删除##delete_confirm")
  end

  -- Draw delete confirmation dialog (must be called before other windows)
  DeleteDialog.draw(ctx)

  Topbar.draw(ctx)
  dnd_update(ctx)

  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)

  -- If settings panel is open, show it instead of the normal layout
  if state.show_settings then
    if ImGui.BeginChild(ctx, "##fxminer_settings", 0, avail_h, ImGui.ChildFlags_Border or 0) then
      Settings.draw(ctx)
      ImGui.EndChild(ctx)
    end
    return
  end

  -- Normal layout: three columns
  local folder_w = 260
  local inspector_w = 420

  -- Left: folders (hide in team mode)
  local is_team_mode = (state.library_mode == "team")
  local actual_folder_w = is_team_mode and 0 or folder_w

  if not is_team_mode then
    if ImGui.BeginChild(ctx, "##fxminer_folders", folder_w, avail_h, ImGui.ChildFlags_Border or 0) then
      Folders.draw(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)
  end

  -- Middle: list
  local list_w = math.max(220, avail_w - actual_folder_w - inspector_w - 16)
  if ImGui.BeginChild(ctx, "##fxminer_list", list_w, avail_h, ImGui.ChildFlags_Border or 0) then
    List.draw(ctx)
    ImGui.EndChild(ctx)
  end

  ImGui.SameLine(ctx)

  -- Right: inspector
  if ImGui.BeginChild(ctx, "##fxminer_inspector", 0, avail_h, ImGui.ChildFlags_Border or 0) then
    Inspector.draw(ctx)
    ImGui.EndChild(ctx)
  end
end

return GuiBrowser