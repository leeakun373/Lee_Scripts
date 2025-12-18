-- FXMiner/src/gui_browser.lua
-- Dynamic fields + Virtual folders Browser

local W = require("widgets")

local GuiBrowser = {}

local App, DB, Config, Engine

local state = {
  search = "",
  selected_folder_id = -1, -- -1 == All, >=0 == virtual folder id
  selected_rel = nil,

  -- Multi-selection support
  selected_items = {}, -- rel_path -> true (set of selected items)
  last_clicked_idx = nil, -- for shift-click range selection

  -- inspector edits
  edit_name = "",
  edit_desc = "",
  category_idx = 0,

  field_inputs = {}, -- key -> current input string
  status = "",

  -- new folder modal
  new_folder_name = "",
  show_new_folder_popup = false,

  -- drag & drop (external drop)
  dnd_name = nil,

  -- folder UI
  folder_open = {}, -- id -> bool
  folder_rename_id = nil,
  folder_rename_text = "",
  folder_rename_init = false,

  -- icons (optional): prefer emoji, with font if available
  icon_font = nil, -- emoji font if attached
  icon_plus = "➕",
  icon_folder = "📁",
  icon_folder_add = "🗂️",
  icon_delete = "🗑️",

  -- Context tracking: continuously track cursor context for accurate item/track detection
  -- 0 = TCP (track panel), 1 = Items/Arrange, 2 = Envelopes
  last_valid_context = -1,

  -- Settings panel
  show_settings = false,
  settings_team_path = "",
  settings_team_path_valid = false,

  -- Library mode: "local" or "team"
  library_mode = "local",

  -- Team sync state
  team_entries = {},
  team_sync_status = "",
  team_last_sync = 0,

  -- Sync in progress flag
  sync_in_progress = false,
}

local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(s)
  return tostring(s or ""):lower()
end

local function split_tokens(s)
  local out = {}
  s = trim(s)
  if s == "" then return out end
  for tok in s:gmatch("%S+") do
    out[#out + 1] = lower(tok)
  end
  return out
end

local function array_contains(arr, value)
  if type(arr) ~= "table" then return false end
  for _, v in ipairs(arr) do
    if tostring(v) == tostring(value) then
      return true
    end
  end
  return false
end

local function array_remove(arr, value)
  if type(arr) ~= "table" then return end
  for i = #arr, 1, -1 do
    if tostring(arr[i]) == tostring(value) then
      table.remove(arr, i)
    end
  end
end

local function array_add_unique(arr, value)
  if type(arr) ~= "table" then return end
  value = trim(value)
  if value == "" then return end
  if array_contains(arr, value) then return end
  arr[#arr + 1] = value
end

local function safe_append_fxchain(abs_path)
  local r = reaper
  local tr = r.GetSelectedTrack(0, 0)
  if not tr then
    return false, "No selected track"
  end

  abs_path = tostring(abs_path or "")
  if abs_path == "" then
    return false, "Invalid path"
  end

  -- FXCHAIN prefers path relative to FXChains root
  local fxchains_root = tostring((Config and Config.FXCHAINS_ROOT) or ""):gsub("[\\/]+$", "")
  local abs_norm = abs_path:gsub("\\", "/")
  local root_norm = fxchains_root:gsub("\\", "/")

  local rel_under_fxchains = nil
  if root_norm ~= "" and abs_norm:lower():find(root_norm:lower(), 1, true) == 1 then
    rel_under_fxchains = abs_norm:sub(#root_norm + 1):gsub("^[\\/]+", "")
  end

  local tried = {}
  local function try_add(s)
    if not s or s == "" then return -1 end
    if tried[s] then return -1 end
    tried[s] = true
    return r.TrackFX_AddByName(tr, s, false, -1)
  end

  local idx = -1
  if rel_under_fxchains then
    idx = try_add("FXCHAIN:" .. rel_under_fxchains)
    if idx == -1 then idx = try_add(rel_under_fxchains) end
  end
  if idx == -1 then idx = try_add("FXCHAIN:" .. abs_path) end
  if idx == -1 then idx = try_add(abs_path) end
  if idx == -1 then
    return false, "Failed to load FX chain"
  end

  return true
end

local function safe_append_fxchain_to_track(track, abs_path)
  local r = reaper
  if not track then
    return safe_append_fxchain(abs_path)
  end
  abs_path = tostring(abs_path or "")
  if abs_path == "" then
    return false, "Invalid path"
  end

  local fxchains_root = tostring((Config and Config.FXCHAINS_ROOT) or ""):gsub("[\\/]+$", "")
  local abs_norm = abs_path:gsub("\\", "/")
  local root_norm = fxchains_root:gsub("\\", "/")

  local rel_under_fxchains = nil
  if root_norm ~= "" and abs_norm:lower():find(root_norm:lower(), 1, true) == 1 then
    rel_under_fxchains = abs_norm:sub(#root_norm + 1):gsub("^[\\/]+", "")
  end

  local tried = {}
  local function try_add(s)
    if not s or s == "" then return -1 end
    if tried[s] then return -1 end
    tried[s] = true
    return r.TrackFX_AddByName(track, s, false, -1)
  end

  local idx = -1
  if rel_under_fxchains then
    idx = try_add("FXCHAIN:" .. rel_under_fxchains)
    if idx == -1 then idx = try_add(rel_under_fxchains) end
  end
  if idx == -1 then idx = try_add("FXCHAIN:" .. abs_path) end
  if idx == -1 then idx = try_add(abs_path) end

  if idx == -1 then
    return false, "Failed to load FX chain"
  end
  return true
end

local function safe_append_fxchain_to_take(take, abs_path)
  local r = reaper
  if not (take and r and r.TakeFX_AddByName and r.ValidatePtr and r.ValidatePtr(take, "MediaItem_Take*")) then
    return false, "Invalid take"
  end

  abs_path = tostring(abs_path or "")
  if abs_path == "" then
    return false, "Invalid path"
  end

  local fxchains_root = tostring((Config and Config.FXCHAINS_ROOT) or ""):gsub("[\\/]+$", "")
  local abs_norm = abs_path:gsub("\\", "/")
  local root_norm = fxchains_root:gsub("\\", "/")

  local rel_under_fxchains = nil
  if root_norm ~= "" and abs_norm:lower():find(root_norm:lower(), 1, true) == 1 then
    rel_under_fxchains = abs_norm:sub(#root_norm + 1):gsub("^[\\/]+", "")
  end

  local tried = {}
  local function try_add(s)
    if not s or s == "" then return -1 end
    if tried[s] then return -1 end
    tried[s] = true
    return r.TakeFX_AddByName(take, s, -1)
  end

  local idx = -1
  if rel_under_fxchains then
    idx = try_add("FXCHAIN:" .. rel_under_fxchains)
    if idx == -1 then idx = try_add(rel_under_fxchains) end
  end
  if idx == -1 then idx = try_add("FXCHAIN:" .. abs_path) end
  if idx == -1 then idx = try_add(abs_path) end

  if idx == -1 then
    return false, "Failed to load FX chain"
  end
  return true
end

-- Determine if we should target tracks (true) or items (false/nil)
-- Based on NVK's target_track logic from fx.lua
local function should_target_track(track_count, item_count)
  -- No tracks selected -> use items
  if track_count == 0 then
    return false
  end
  -- No items selected -> use tracks
  if item_count == 0 then
    return true
  end
  -- Both selected: use cursor_context
  -- cursor_context == 0 means TCP (Track Control Panel) -> use tracks
  -- cursor_context == 1 means Arrange/Items -> use items
  return state.last_valid_context == 0
end

-- Smart context detection: determine whether to load on items or tracks
-- Based on NVK's FX.AddContextualTargets logic
local function detect_load_context()
  local r = reaper

  -- Count selections
  local item_count = (r.CountSelectedMediaItems and r.CountSelectedMediaItems(0)) or 0
  local track_count = (r.CountSelectedTracks and r.CountSelectedTracks(0)) or 0

  -- No selection at all
  if item_count == 0 and track_count == 0 then
    return nil, nil
  end

  -- Update cursor context (like NVK does in FX.AddContextualTargets)
  -- GetCursorContext returns -1 when cursor is in ImGui window
  -- We only update if we get a valid value (0, 1, or 2)
  local focus = r.GetCursorContext and r.GetCursorContext() or -1
  if focus ~= -1 then
    state.last_valid_context = focus
  end
  -- If focus is -1, keep using the previously stored last_valid_context

  -- Decide target based on NVK's logic
  if should_target_track(track_count, item_count) then
    -- Target tracks
    local selected_tracks = {}
    for i = 0, track_count - 1 do
      local track = r.GetSelectedTrack(0, i)
      if track then
        table.insert(selected_tracks, track)
      end
    end
    return "track", selected_tracks
  else
    -- Target items
    local all_items = {}
    for i = 0, item_count - 1 do
      local item = r.GetSelectedMediaItem(0, i)
      if item then
        local take = r.GetActiveTake(item)
        if take then
          table.insert(all_items, { item = item, take = take })
        end
      end
    end
    -- If no valid takes found, fallback to tracks
    if #all_items == 0 and track_count > 0 then
      local selected_tracks = {}
      for i = 0, track_count - 1 do
        local track = r.GetSelectedTrack(0, i)
        if track then
          table.insert(selected_tracks, track)
        end
      end
      return "track", selected_tracks
    end
    return "item", all_items
  end
end

local function safe_append_fxchain_to_selected_items_or_track(abs_path)
  local r = reaper

  local context_type, context_objs = detect_load_context()

  if context_type == "item" and context_objs and #context_objs > 0 then
    -- Load on selected items
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local ok_any = false
    local last_err = nil
    for _, obj in ipairs(context_objs) do
      local ok, err = safe_append_fxchain_to_take(obj.take, abs_path)
      if ok then
        ok_any = true
      else
        last_err = err
      end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("FXMiner: Load FX Chain on selected items", -1)
    if ok_any then
      return true
    end
    return false, last_err or "Failed to load on items"
  end

  if context_type == "track" and context_objs and #context_objs > 0 then
    -- Load on selected tracks
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local ok_any = false
    local last_err = nil
    for _, track in ipairs(context_objs) do
      local ok, err = safe_append_fxchain_to_track(track, abs_path)
      if ok then
        ok_any = true
      else
        last_err = err
      end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("FXMiner: Load FX Chain on selected tracks", -1)
    if ok_any then
      return true
    end
    return false, last_err or "Failed to load on tracks"
  end

  -- Fallback: load on first selected track
  return safe_append_fxchain(abs_path)
end

-- Drag & drop:
-- while dragging inside ImGui, detect mouse-over track/item and accept payload on drop.
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
          ok2, err = safe_append_fxchain_to_take(take, abs)
          if not ok2 then
            ok2, err = safe_append_fxchain_to_track(track, abs)
          end
        else
          ok2, err = safe_append_fxchain_to_track(track, abs)
        end
        state.status = ok2 and ("Loaded: " .. tostring(e.name or "")) or ("Load failed: " .. tostring(err))
      end
      state.dnd_name = nil
    end
  end
end

local function set_selected_entry(rel)
  state.selected_rel = rel
  local e = rel and DB:find_entry_by_rel(rel) or nil
  if not e then
    state.edit_name = ""
    state.edit_desc = ""
    state.field_inputs = {}
    return
  end

  DB:_ensure_entry_defaults(e)
  state.edit_name = tostring(e.name or "")
  state.edit_desc = tostring(e.description or "")

  -- Sync field inputs from entry metadata (all strings)
  state.field_inputs = {}
  local fields = DB:get_fields_config()
  if type(fields) == "table" then
    for _, field in ipairs(fields) do
      local key = tostring(field.key or "")
      if key ~= "" then
        state.field_inputs[key] = tostring((e.metadata and e.metadata[key]) or "")
      end
    end
  end
end

local function build_search_content(e)
  -- Build a single lowercase string containing all searchable text
  local parts = {}

  -- Name
  local name = tostring(e.name or ""):lower()
  if name ~= "" then parts[#parts + 1] = name end

  -- Description
  local desc = tostring(e.description or ""):lower()
  if desc ~= "" then parts[#parts + 1] = desc end

  -- All metadata values
  if type(e.metadata) == "table" then
    for _, v in pairs(e.metadata) do
      local s = tostring(v or ""):lower()
      if s ~= "" then parts[#parts + 1] = s end
    end
  end

  -- Also include pre-built keywords for backward compatibility
  local kw = tostring(e.keywords or ""):lower()
  if kw ~= "" then parts[#parts + 1] = kw end

  return table.concat(parts, " ")
end

local function matches_search(e, tokens)
  if #tokens == 0 then return true end

  local search_content = build_search_content(e)

  -- All tokens must be found in the search content
  for _, t in ipairs(tokens) do
    if not search_content:find(t, 1, true) then
      return false
    end
  end
  return true
end

local function draw_topbar(ctx)
  local ImGui = App.ImGui

  -- Title row + settings + close button on the right
  local title = "FXMiner"
  local x_label = "X"
  local gear_label = "⚙"
  local btn_w = 24

  if App._theme and App._theme.fonts and App._theme.fonts.heading1 then
    ImGui.PushFont(ctx, App._theme.fonts.heading1)
    ImGui.Text(ctx, title)
    ImGui.PopFont(ctx)
  else
    ImGui.Text(ctx, title)
  end

  -- Status text next to title (dimmer font)
  if state.status and state.status ~= "" then
    ImGui.SameLine(ctx)
    local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text
    if ImGui.PushStyleColor and col_text then
      ImGui.PushStyleColor(ctx, col_text, 0x888888FF) -- More dim
      ImGui.Text(ctx, "| " .. state.status)
      ImGui.PopStyleColor(ctx, 1)
    else
      ImGui.Text(ctx, "| " .. state.status)
    end
  end

  -- Right-side buttons: Settings + Close
  if ImGui.SameLine and ImGui.SetCursorPosX and ImGui.GetContentRegionAvail then
    local avail = ImGui.GetContentRegionAvail(ctx)
    local cur_x = ImGui.GetCursorPosX(ctx)
    local total_btn_w = btn_w * 2 + 8
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, math.max(cur_x, cur_x + avail - total_btn_w))
  else
    ImGui.SameLine(ctx)
  end

  -- Settings button (gear icon)
  if ImGui.PushStyleColor and ImGui.PopStyleColor then
    local gear_col = state.show_settings and 0x80B0FFFF or 0xA0A0A0FF
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x404040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, gear_col)
    if ImGui.Button(ctx, gear_label .. "##settings_btn", btn_w, 0) then
      state.show_settings = not state.show_settings
    end
    ImGui.PopStyleColor(ctx, 4)
  else
    if ImGui.Button(ctx, gear_label .. "##settings_btn") then
      state.show_settings = not state.show_settings
    end
  end

  ImGui.SameLine(ctx)

  -- Close button (red X)
  if ImGui.PushStyleColor and ImGui.PopStyleColor then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x404040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF4040FF)
    if ImGui.Button(ctx, x_label .. "##close_btn", btn_w, 0) then
      App.open = false
    end
    ImGui.PopStyleColor(ctx, 4)
  else
    if ImGui.Button(ctx, x_label .. "##close_btn") then
      App.open = false
    end
  end

  ImGui.Separator(ctx)

  -- Search row with Library mode toggle
  -- [Local] [Team] | [Search.............]

  -- Library mode buttons
  local local_active = (state.library_mode == "local")
  local team_active = (state.library_mode == "team")

  if local_active then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x4080B0FF)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x303030FF)
  end
  if ImGui.Button(ctx, "Local##lib_local", 50, 0) then
    state.library_mode = "local"
  end
  ImGui.PopStyleColor(ctx, 1)

  ImGui.SameLine(ctx)

  if team_active then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x4080B0FF)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x303030FF)
  end
  local team_enabled = Config.TEAM_PUBLISH_PATH and Config.TEAM_PUBLISH_PATH ~= ""
  if not team_enabled and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end
  if ImGui.Button(ctx, "Team##lib_team", 50, 0) then
    if team_enabled then
      state.library_mode = "team"
      -- Load team entries when switching
      local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
      if team_db_path then
        state.team_entries = DB:get_team_entries(team_db_path)
        state.team_last_sync = os.time()
      end
    end
  end
  if not team_enabled and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end
  ImGui.PopStyleColor(ctx, 1)

  ImGui.SameLine(ctx)

  -- Refresh button
  if ImGui.Button(ctx, "Refresh", 55, 0) then
    state.status = "Refreshing..."
    -- Perform full scan and prune to remove ghost files
    DB:scan_fxchains()
    DB:prune_missing_files()
    DB:load() -- Reload local DB
    if team_enabled then
      local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
      if team_db_path then
        state.team_entries = DB:get_team_entries(team_db_path)
      end
    end
    state.status = "Refreshed"
  end

  ImGui.SameLine(ctx, nil, 20)

  -- Folder buttons (using SmallButton to save space)
  local function open_folder(path)
    if not path or path == "" then return end
    if reaper.CF_ShellExecute then
      reaper.CF_ShellExecute(path)
    else
      local cmd = string.format('explorer "%s"', path:gsub("/", "\\"))
      os.execute(cmd)
    end
  end

  if ImGui.SmallButton(ctx, "Local Folder") then
    open_folder(Config.FXCHAINS_ROOT)
  end

  ImGui.SameLine(ctx)

  if not team_enabled and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end
  if ImGui.SmallButton(ctx, "Team Folder") then
    open_folder(Config.TEAM_PUBLISH_PATH)
  end
  if not team_enabled and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end

  ImGui.Spacing(ctx)

  -- Search input (leave space for sync buttons on the right)
  local sync_btn_width = team_enabled and 130 or 0
  ImGui.SetNextItemWidth(ctx, -sync_btn_width - 8)
  _, state.search = ImGui.InputText(ctx, "##search_input", state.search)

  -- Sync buttons on the right of search bar
  if team_enabled then
    ImGui.SameLine(ctx)

    -- Pull/Sync button
    if ImGui.Button(ctx, "↓Sync", 60, 0) then
      if not state.sync_in_progress then
        state.sync_in_progress = true
        state.team_sync_status = "Syncing..."

        local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
        if team_db_path then
          local ok, msg, stats = DB:pull_from_team(
            Config.TEAM_PUBLISH_PATH,
            team_db_path,
            Config.FXCHAINS_ROOT
          )

          if ok then
            state.team_entries = DB:get_team_entries(team_db_path)
            state.team_last_sync = os.time()
            state.team_sync_status = "✓ " .. tostring(msg)
            state.status = "Sync success: " .. tostring(msg)
          else
            state.team_sync_status = "✗ " .. tostring(msg)
            state.status = "Sync failed: " .. tostring(msg)
          end
        else
          state.team_sync_status = "Team path not configured"
          state.status = "Team path not configured"
        end
        state.sync_in_progress = false
      end
    end

    ImGui.SameLine(ctx)

    -- Push button (push selected items)
    local sel_count = 0
    for _ in pairs(state.selected_items) do sel_count = sel_count + 1 end
    local push_label = sel_count > 1 and ("↑Push(" .. sel_count .. ")") or "↑Push"

    local can_push = sel_count > 0 and state.library_mode == "local"
    if not can_push and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end

    if ImGui.Button(ctx, push_label, 65, 0) then
      if not state.sync_in_progress and sel_count > 0 then
        state.sync_in_progress = true
        state.team_sync_status = "Pushing " .. sel_count .. " item(s)..."

        local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
        
        -- Run in pcall to ensure sync_in_progress is reset
        local ok_sync, err_sync = pcall(function()
          local success_count = 0
          local fail_count = 0
          
          if not Engine then
            error("Engine module not loaded. Please check if src/fx_engine.lua exists.")
          end

          for rel, _ in pairs(state.selected_items) do
            if not rel:match("^team:") then
              local e = DB:find_entry_by_rel(rel)
              if e then
                local abs_path = DB:rel_to_abs(e.rel_path)
                if abs_path then
                  -- Copy file
                  local result, msg = Engine.publish_to_team(Config, abs_path, { force_overwrite = true })

                  if result == Engine.PUBLISH_OK then
                    -- Sync metadata with lock
                    if team_db_path then
                      local metadata = {
                        name = e.name,
                        description = e.description,
                        metadata = e.metadata,
                        plugins = e.plugins,
                      }
                      DB:push_to_team_locked(Config.TEAM_PUBLISH_PATH, team_db_path, abs_path, metadata)
                    end
                    success_count = success_count + 1
                  else
                    fail_count = fail_count + 1
                  end
                end
              end
            end
          end

          -- Refresh team entries
          if team_db_path then
            state.team_entries = DB:get_team_entries(team_db_path)
          end

          if fail_count == 0 then
            state.team_sync_status = "✓ Pushed " .. success_count .. " item(s)"
            -- Clear local selection after successful push
            state.selected_items = {}
          else
            state.team_sync_status = "Pushed " .. success_count .. ", failed " .. fail_count
          end
        end)

        if not ok_sync then
          state.team_sync_status = "✗ Error: " .. tostring(err_sync)
          state.status = "Push error: " .. tostring(err_sync)
        else
          state.status = state.team_sync_status
        end
        state.sync_in_progress = false
      end
    end

    if not can_push and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end
  end

  ImGui.Spacing(ctx)
end

-- Draw settings panel
local function draw_settings_panel(ctx)
  local ImGui = App.ImGui

  W.separator_text(ctx, ImGui, "Settings")

  -- Team Publish Path
  ImGui.Text(ctx, "Team Server Path (NAS/Network Drive):")
  ImGui.PushItemWidth(ctx, -80)

  -- Initialize from Config if empty
  if state.settings_team_path == "" and Config.TEAM_PUBLISH_PATH then
    state.settings_team_path = Config.TEAM_PUBLISH_PATH
  end

  local _, new_path = ImGui.InputText(ctx, "##team_path", state.settings_team_path)
  state.settings_team_path = new_path
  ImGui.PopItemWidth(ctx)

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Browse##team_browse", 70, 0) then
    -- Try to use JS_Dialog_BrowseForFolder if available
    if reaper.JS_Dialog_BrowseForFolder then
      local rv, path = reaper.JS_Dialog_BrowseForFolder("Select Team Server Folder", state.settings_team_path or "")
      if rv == 1 and path and path ~= "" then
        state.settings_team_path = path
      end
    else
      state.team_sync_status = "Install js_ReaScriptAPI for folder browser"
    end
  end

  -- Apply button
  if ImGui.Button(ctx, "Apply Path", 80, 0) then
    -- Update Config
    Config.TEAM_PUBLISH_PATH = trim(state.settings_team_path)

    -- Validate path
    local f = io.open(Config.TEAM_PUBLISH_PATH .. "/.fxminer_test", "w")
    if f then
      f:close()
      os.remove(Config.TEAM_PUBLISH_PATH .. "/.fxminer_test")
      state.settings_team_path_valid = true
      state.team_sync_status = "✓ Path valid and writable"
    else
      state.settings_team_path_valid = false
      state.team_sync_status = "✗ Path not writable"
    end
  end

  ImGui.SameLine(ctx)
  local valid_text = state.settings_team_path_valid and "✓ Valid" or ""
  ImGui.TextDisabled(ctx, valid_text)

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)

  -- Team Sync Actions
  W.separator_text(ctx, ImGui, "Team Sync (with File Locking)")

  local team_enabled = Config.TEAM_PUBLISH_PATH and Config.TEAM_PUBLISH_PATH ~= ""

  if not team_enabled and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end

  -- Full Sync button (Pull + refresh)
  if ImGui.Button(ctx, "Full Sync", 80, 0) then
    local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
    if team_db_path then
      state.team_sync_status = "Syncing..."

      -- Use the locked pull function
      local ok, msg, stats = DB:pull_from_team(
        Config.TEAM_PUBLISH_PATH,
        team_db_path,
        Config.FXCHAINS_ROOT
      )

      if ok then
        -- Refresh team entries list
        state.team_entries = DB:get_team_entries(team_db_path)
        state.team_last_sync = os.time()
        state.team_sync_status = "✓ " .. tostring(msg)
      else
        state.team_sync_status = "✗ Sync failed: " .. tostring(msg)
      end
    else
      state.team_sync_status = "Team DB path not configured"
    end
  end

  ImGui.SameLine(ctx)

  -- Pull from Team (view only, no download)
  if ImGui.Button(ctx, "Refresh List", 85, 0) then
    local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
    if team_db_path then
      state.team_entries = DB:get_team_entries(team_db_path)
      state.team_last_sync = os.time()
      state.team_sync_status = string.format("Loaded %d entries from team DB", #state.team_entries)
    else
      state.team_sync_status = "Team DB path not configured"
    end
  end

  ImGui.SameLine(ctx)

  -- Force release stale lock
  if ImGui.Button(ctx, "Clear Lock", 75, 0) then
    local removed = DB:force_release_stale_lock(Config.TEAM_PUBLISH_PATH, 0)
    if removed then
      state.team_sync_status = "Lock file removed"
    else
      state.team_sync_status = "No lock file found"
    end
  end

  ImGui.Spacing(ctx)

  -- Push Selected to Team (with locking)
  if ImGui.Button(ctx, "Push Selected to Team", 140, 0) then
    if state.selected_rel and not state.selected_rel:match("^team:") then
      local e = DB:find_entry_by_rel(state.selected_rel)
      if e then
        local abs_path = DB:rel_to_abs(e.rel_path)
        if abs_path then
          state.team_sync_status = "Pushing..."

          -- Step 1: Copy file to team folder
          local Engine = require("fx_engine")
          local result, msg, published_path = Engine.publish_to_team(Config, abs_path, { force_overwrite = true })

          if result == Engine.PUBLISH_OK then
            -- Step 2: Sync metadata with locking
            local team_db_path = Config.get_team_db_path and Config.get_team_db_path()
            if team_db_path then
              local metadata = {
                name = e.name,
                description = e.description,
                metadata = e.metadata,
                plugins = e.plugins,
              }

              local sync_ok, sync_msg = DB:push_to_team_locked(
                Config.TEAM_PUBLISH_PATH,
                team_db_path,
                abs_path,
                metadata
              )

              if sync_ok then
                -- Refresh team entries
                state.team_entries = DB:get_team_entries(team_db_path)
                state.team_sync_status = "✓ Pushed: " .. tostring(e.name)
              else
                state.team_sync_status = "File copied but DB sync failed: " .. tostring(sync_msg)
              end
            else
              state.team_sync_status = "✓ Pushed (no DB sync)"
            end
          else
            state.team_sync_status = "✗ Push failed: " .. tostring(msg)
          end
        else
          state.team_sync_status = "Cannot resolve file path"
        end
      else
        state.team_sync_status = "Entry not found in local DB"
      end
    else
      if state.selected_rel and state.selected_rel:match("^team:") then
        state.team_sync_status = "Cannot push team entries (select a local item)"
      else
        state.team_sync_status = "Select a local item first"
      end
    end
  end

  if not team_enabled and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)

  -- Sync explanation
  W.separator_text(ctx, ImGui, "How Sync Works")
  ImGui.TextDisabled(ctx, "Full Sync: Downloads missing files from team server,")
  ImGui.TextDisabled(ctx, "updates local metadata if server version is newer.")
  ImGui.TextDisabled(ctx, "Push: Uploads selected file + metadata to team server.")
  ImGui.TextDisabled(ctx, "File locking prevents concurrent write conflicts.")

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)

  -- Status area
  W.separator_text(ctx, ImGui, "Status")

  if state.team_sync_status and state.team_sync_status ~= "" then
    -- Color based on status
    local is_error = state.team_sync_status:find("✗") or state.team_sync_status:find("failed")
    local is_success = state.team_sync_status:find("✓")

    -- Get Col_Text constant (handle both function and constant forms)
    local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text

    if is_error and ImGui.PushStyleColor and col_text then
      ImGui.PushStyleColor(ctx, col_text, 0xFF6060FF)
      ImGui.TextWrapped(ctx, state.team_sync_status)
      ImGui.PopStyleColor(ctx, 1)
    elseif is_success and ImGui.PushStyleColor and col_text then
      ImGui.PushStyleColor(ctx, col_text, 0x60FF60FF)
      ImGui.TextWrapped(ctx, state.team_sync_status)
      ImGui.PopStyleColor(ctx, 1)
    else
      ImGui.TextWrapped(ctx, state.team_sync_status)
    end
  else
    ImGui.TextDisabled(ctx, "No recent activity")
  end

  if state.team_last_sync > 0 then
    local ago = os.time() - state.team_last_sync
    local ago_str
    if ago < 60 then
      ago_str = ago .. " seconds ago"
    elseif ago < 3600 then
      ago_str = math.floor(ago / 60) .. " minutes ago"
    else
      ago_str = math.floor(ago / 3600) .. " hours ago"
    end
    ImGui.TextDisabled(ctx, "Last sync: " .. ago_str)
  end

  -- Team entries count
  if state.team_entries and #state.team_entries > 0 then
    ImGui.TextDisabled(ctx, "Team library: " .. #state.team_entries .. " items")
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)

  -- Close settings button
  if ImGui.Button(ctx, "Close Settings", -1, 0) then
    state.show_settings = false
  end
end

local function draw_folder_tree_node(ctx, folder, depth)
  local ImGui = App.ImGui

  local id = tonumber(folder.id) or 0
  local name = tostring(folder.name or "")
  if name == "" then name = (id == 0) and "Root" or ("Folder " .. id) end

  depth = tonumber(depth) or 0
  local INDENT_W = 12
  local ARROW_W = 16

  local children = DB:list_children(id)
  local has_children = false
  for _, c in ipairs(children) do
    if tonumber(c.id) ~= id then
      has_children = true
      break
    end
  end

  local function begin_rename(folder_id, current_name)
    state.folder_rename_id = tonumber(folder_id) or 0
    state.folder_rename_text = tostring(current_name or "")
    state.folder_rename_init = true
  end

  -- Inline rename row
  if state.folder_rename_id == id then
    if ImGui.Indent and ImGui.Unindent and depth > 0 then
      ImGui.Indent(ctx, depth * 16)
    end
    if state.folder_rename_init and ImGui.SetKeyboardFocusHere then
      ImGui.SetKeyboardFocusHere(ctx, 0)
    end
    if ImGui.SetNextItemWidth then
      ImGui.SetNextItemWidth(ctx, -1)
    end
    local flags = ImGui.InputTextFlags_AutoSelectAll or 0
    local _, newv = ImGui.InputText(ctx, "###fxminer_rename_folder_" .. tostring(id), state.folder_rename_text, flags)
    state.folder_rename_text = newv
    -- commit on focus lost
    if (ImGui.IsItemActive and not ImGui.IsItemActive(ctx)) and not state.folder_rename_init then
      local new_name = trim(state.folder_rename_text)
      if new_name ~= "" then
        local ok, err = DB:rename_folder(id, new_name)
        if not ok then
          state.status = "Rename failed: " .. tostring(err)
        end
      end
      state.folder_rename_id = nil
      state.folder_rename_text = ""
    end
    state.folder_rename_init = false
    if ImGui.Indent and ImGui.Unindent and depth > 0 then
      ImGui.Unindent(ctx, depth * 16)
    end
    return
  end

  -- Folder row (fully manual, avoids TreePop issues across ReaImGui versions)
  local selected = (state.selected_folder_id == id)
  state.folder_open[id] = (state.folder_open[id] == nil) and false or state.folder_open[id]

  if ImGui.Indent and ImGui.Unindent and depth > 0 then
    ImGui.Indent(ctx, depth * INDENT_W)
  end

  -- Arrow toggle for parents (only if has children)
  if has_children then
    local arrow = state.folder_open[id] and "▼" or "▶"
    if ImGui.SmallButton(ctx, arrow .. "###fxminer_folder_arrow_" .. tostring(id)) then
      state.folder_open[id] = not state.folder_open[id]
    end
    ImGui.SameLine(ctx)
  end
  -- No dummy for leaf: keeps leaf aligned with All

  local label = name .. "###fxminer_folder_row_" .. tostring(id)
  if ImGui.Selectable(ctx, label, selected) then
    state.selected_folder_id = id
  end

  -- Right-click context menu (OpenPopup + BeginPopup is most stable)
  local popup_id = "fxminer_folder_menu_" .. tostring(id)
  if ImGui.IsItemClicked and ImGui.IsItemClicked(ctx, 1) and ImGui.OpenPopup then
    ImGui.OpenPopup(ctx, popup_id)
  end
  if ImGui.BeginPopup and ImGui.EndPopup and ImGui.BeginPopup(ctx, popup_id) then
    if ImGui.MenuItem(ctx, "New folder below") then
      local cur = DB:get_folder(id)
      local pid = cur and tonumber(cur.parent_id) or 0
      local ok, new_id_or_err = DB:create_folder("New folder", pid, { insert_after_id = id })
      if ok then
        state.selected_folder_id = new_id_or_err
        begin_rename(new_id_or_err, "New folder")
      else
        state.status = "Create failed: " .. tostring(new_id_or_err)
      end
    end
    if ImGui.MenuItem(ctx, "New subfolder") then
      local ok, new_id_or_err = DB:create_folder("New folder", id, { insert_after_id = nil })
      if ok then
        state.folder_open[id] = true
        state.selected_folder_id = new_id_or_err
        begin_rename(new_id_or_err, "New folder")
      else
        state.status = "Create failed: " .. tostring(new_id_or_err)
      end
    end
    if id ~= 0 and ImGui.MenuItem(ctx, "New parent folder") then
      local ok, new_id_or_err = DB:create_parent_folder(id, "New parent folder")
      if ok then
        state.selected_folder_id = new_id_or_err
        begin_rename(new_id_or_err, "New parent folder")
      else
        state.status = "Create parent failed: " .. tostring(new_id_or_err)
      end
    end
    if ImGui.Separator then ImGui.Separator(ctx) end
    if id ~= 0 and ImGui.MenuItem(ctx, "Rename") then
      begin_rename(id, name)
    end
    if ImGui.Separator then ImGui.Separator(ctx) end
    if id ~= 0 and ImGui.MenuItem(ctx, "Remove folder") then
      local ok, err = DB:delete_folder(id)
      if not ok then
        state.status = "Remove failed: " .. tostring(err)
      else
        if state.selected_folder_id == id then
          state.selected_folder_id = -1
        end
        state.folder_open[id] = nil
        if state.folder_rename_id == id then
          state.folder_rename_id = nil
          state.folder_rename_text = ""
          state.folder_rename_init = false
        end
      end
    end
    ImGui.EndPopup(ctx)
  end

  -- Double-click rename
  if id ~= 0 and ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0) then
    begin_rename(id, name)
  end

  -- Drop target: move entry into this folder
  if ImGui.BeginDragDropTarget and ImGui.BeginDragDropTarget(ctx) then
    if ImGui.AcceptDragDropPayload then
      local ok, payload = pcall(ImGui.AcceptDragDropPayload, ctx, "FXMINER_ENTRY")
      if ok and payload and payload ~= "" then
        DB:set_entry_folder(tostring(payload), id)
      end
    end
    ImGui.EndDragDropTarget(ctx)
  end

  if ImGui.Indent and ImGui.Unindent and depth > 0 then
    ImGui.Unindent(ctx, depth * 16)
  end

  -- Children
  if has_children and state.folder_open[id] == true then
    for _, c in ipairs(children) do
      if tonumber(c.id) ~= id then
        draw_folder_tree_node(ctx, c, depth + 1)
      end
    end
  end
end

local function draw_folders_panel(ctx)
  local ImGui = App.ImGui

  W.separator_text(ctx, ImGui, "Folders")

  -- Toolbar: create default name then inline-rename
  local function begin_rename(folder_id, current_name)
    state.folder_rename_id = tonumber(folder_id) or 0
    state.folder_rename_text = tostring(current_name or "")
    state.folder_rename_init = true
  end

  local function flat_button(label, tooltip, on_click, disabled)
    disabled = not not disabled
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
    if disabled and ImGui.Col_TextDisabled then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x808080FF)
    end
    if state.icon_font and ImGui.PushFont and ImGui.PopFont then
      ImGui.PushFont(ctx, state.icon_font)
    end
    local clicked = ImGui.Button(ctx, label)
    if state.icon_font and ImGui.PushFont and ImGui.PopFont then
      ImGui.PopFont(ctx)
    end
    if disabled then clicked = false end
    if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and tooltip and tooltip ~= "" and ImGui.SetTooltip then
      ImGui.SetTooltip(ctx, tooltip)
    end
    if disabled and ImGui.Col_TextDisabled then
      ImGui.PopStyleColor(ctx, 1)
    end
    ImGui.PopStyleColor(ctx, 3)
    if clicked and on_click then on_click() end
    return clicked
  end

  local parent_id_for_create = tonumber(state.selected_folder_id) or -1
  local insert_after_id = nil
  if parent_id_for_create > 0 then
    local cur = DB:get_folder(parent_id_for_create)
    insert_after_id = parent_id_for_create
    parent_id_for_create = cur and tonumber(cur.parent_id) or 0
  else
    parent_id_for_create = 0 -- All -> Root container
  end

  flat_button(state.icon_plus or "+", "Add folder", function()
    local ok, new_id_or_err = DB:create_folder("New folder", parent_id_for_create, { insert_after_id = insert_after_id })
    if ok then
      state.selected_folder_id = new_id_or_err
      begin_rename(new_id_or_err, "New folder")
    else
      state.status = "Create failed: " .. tostring(new_id_or_err)
    end
  end, false)
  ImGui.SameLine(ctx)
  flat_button((state.icon_folder_add and state.icon_folder_add ~= "" and state.icon_folder_add) or "Parent+", "Add parent folder", function()
    local ok, new_id_or_err = DB:create_parent_folder(state.selected_folder_id, "New parent folder")
    if ok then
      state.selected_folder_id = new_id_or_err
      begin_rename(new_id_or_err, "New parent folder")
    else
      state.status = "Create parent failed: " .. tostring(new_id_or_err)
    end
  end, state.selected_folder_id <= 0)
  ImGui.SameLine(ctx)
  flat_button((state.icon_delete and state.icon_delete ~= "" and state.icon_delete) or "Del", "Delete folder", function()
    local id = tonumber(state.selected_folder_id) or -1
    if id > 0 then
      local ok, err = DB:delete_folder(id)
      if not ok then
        state.status = "Remove failed: " .. tostring(err)
      else
        state.selected_folder_id = -1
        state.folder_open[id] = nil
        if state.folder_rename_id == id then
          state.folder_rename_id = nil
          state.folder_rename_text = ""
          state.folder_rename_init = false
        end
      end
    end
  end, state.selected_folder_id <= 0)
  ImGui.Separator(ctx)

  -- "All" (top entry) - no arrow, no tree
  do
    local sel = (state.selected_folder_id == -1)
    local label = "All"
    if ImGui.Selectable(ctx, label .. "###fxminer_folder_all", sel) then
      state.selected_folder_id = -1
    end
  end

  -- Hide internal Root container; render its children as top-level list
  local root = DB:get_folder(0)
  if not root then
    ImGui.TextDisabled(ctx, "folders_db not loaded")
  else
    local top = DB:list_children(0)
    for _, f in ipairs(top) do
      if tonumber(f.id) ~= 0 then
        draw_folder_tree_node(ctx, f, 0)
      end
    end
  end

  ImGui.Spacing(ctx)
end

-- Helper: get item identifier (rel_path for local, "team:filename" for team)
local function get_item_id(e)
  if e.is_team then
    return "team:" .. tostring(e.filename or "")
  else
    return tostring(e.rel_path or "")
  end
end

-- Helper: check if item is selected (in multi-select set)
local function is_item_selected(item_id)
  return state.selected_items[item_id] == true
end

-- Helper: count selected items
local function count_selected()
  local n = 0
  for _ in pairs(state.selected_items) do n = n + 1 end
  return n
end

-- Helper: handle selection click with Shift/Ctrl modifiers
local function handle_selection_click(items, idx, item_id)
  local ImGui = App.ImGui

  -- Check modifiers
  local function get_mod(mod_name, fallback)
    local val = ImGui[mod_name]
    if not val then return fallback end
    return type(val) == "function" and val() or val
  end

  local mod_shift = get_mod("Mod_Shift", 0x0002)
  local mod_ctrl = get_mod("Mod_Ctrl", 0x0001)

  local shift_held = ImGui.IsKeyDown and ImGui.IsKeyDown(App.ctx, mod_shift)
  local ctrl_held = ImGui.IsKeyDown and ImGui.IsKeyDown(App.ctx, mod_ctrl)

  -- Fallback: check via GetKeyMods if IsKeyDown doesn't work
  if ImGui.GetKeyMods then
    local mods = ImGui.GetKeyMods(App.ctx)
    shift_held = (mods & mod_shift) ~= 0
    ctrl_held = (mods & mod_ctrl) ~= 0
  end

  if shift_held and state.last_clicked_idx then
    -- Shift+Click: range selection
    local from_idx = math.min(state.last_clicked_idx, idx)
    local to_idx = math.max(state.last_clicked_idx, idx)

    -- If not Ctrl, clear existing selection first
    if not ctrl_held then
      state.selected_items = {}
    end

    -- Select range
    for i = from_idx, to_idx do
      if items[i] then
        local id = get_item_id(items[i])
        state.selected_items[id] = true
      end
    end
  elseif ctrl_held then
    -- Ctrl+Click: toggle selection
    if state.selected_items[item_id] then
      state.selected_items[item_id] = nil
    else
      state.selected_items[item_id] = true
    end
    state.last_clicked_idx = idx
  else
    -- Normal click: single selection
    state.selected_items = {}
    state.selected_items[item_id] = true
    state.last_clicked_idx = idx
  end

  -- Update selected_rel for inspector (use first selected)
  state.selected_rel = item_id
end

local function draw_list_panel(ctx)
  local ImGui = App.ImGui

  local is_team_mode = (state.library_mode == "team")
  local lib_label = is_team_mode and "Team Library" or "Local Library"

  -- Header with selection count
  local sel_count = count_selected()
  if sel_count > 1 then
    lib_label = lib_label .. " (" .. sel_count .. " selected)"
  end
  W.separator_text(ctx, ImGui, lib_label)

  ImGui.TextDisabled(ctx, "Shift+Click: range select | Ctrl+Click: toggle")
  ImGui.Separator(ctx)

  local tokens = split_tokens(state.search)
  local folder_id = tonumber(state.selected_folder_id) or 0

  local items = {}

  if is_team_mode then
    -- Team mode: show entries from team DB
    for _, e in ipairs(state.team_entries or {}) do
      if e then
        -- Build search content for team entries
        local search_content = lower(tostring(e.name or "") .. " " .. tostring(e.description or ""))
        if type(e.metadata) == "table" then
          for _, v in pairs(e.metadata) do
            search_content = search_content .. " " .. lower(tostring(v or ""))
          end
        end

        -- Check search match
        local matches = true
        for _, t in ipairs(tokens) do
          if not search_content:find(t, 1, true) then
            matches = false
            break
          end
        end

        if matches then
          items[#items + 1] = {
            name = e.name or e.filename,
            filename = e.filename,
            description = e.description,
            metadata = e.metadata,
            published_by = e.published_by,
            is_team = true,
          }
        end
      end
    end
  else
    -- Local mode: show entries from local DB
    local entries = DB:entries()
    for _, e in ipairs(entries) do
      if e then
        DB:_ensure_entry_defaults(e)
        local in_folder = (state.selected_folder_id == -1) or (tonumber(e.folder_id) == folder_id)
        if in_folder and matches_search(e, tokens) then
          items[#items + 1] = e
        end
      end
    end
  end

  table.sort(items, function(a, b)
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)

  if #items == 0 then
    if is_team_mode then
      ImGui.TextDisabled(ctx, "No team items. Click ↓Sync to pull from team.")
    else
      ImGui.TextDisabled(ctx, "No items")
    end
    return
  end

  for i, e in ipairs(items) do
    local label = tostring(e.name or "(Unnamed)")
    local is_team = e.is_team
    local item_id = get_item_id(e)
    local is_sel = is_item_selected(item_id)

    if is_team then
      -- Team entry
      local display_label = label
      if e.published_by and e.published_by ~= "" then
        display_label = label .. " [" .. e.published_by .. "]"
      end

      if ImGui.Selectable(ctx, display_label .. "##team_" .. tostring(i), is_sel) then
        handle_selection_click(items, i, item_id)

        -- Update inspector for team entries
        state.edit_name = label
        state.edit_desc = tostring(e.description or "")
        state.field_inputs = {}
        if type(e.metadata) == "table" then
          for k, v in pairs(e.metadata) do
            state.field_inputs[k] = tostring(v or "")
          end
        end
      end

      -- Double click: download and load
      if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0) then
        local team_path = Config.TEAM_PUBLISH_PATH
        if team_path and team_path ~= "" then
          local filename = tostring(e.filename or "")
          local abs = team_path .. "/" .. filename
          abs = abs:gsub("\\", "/"):gsub("//+", "/")
          local ok, err = safe_append_fxchain_to_selected_items_or_track(abs)
          state.status = ok and ("Loaded from Team: " .. label) or ("Load failed: " .. tostring(err))
        end
      end
    else
      -- Local entry
      local rel = tostring(e.rel_path or "")

      if ImGui.Selectable(ctx, label .. "##it_" .. tostring(i), is_sel) then
        handle_selection_click(items, i, item_id)
        set_selected_entry(rel)
      end

      -- Double click load
      if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0) then
        local abs = DB:rel_to_abs(e.rel_path)
        local ok, err = safe_append_fxchain_to_selected_items_or_track(abs)
        state.status = ok and ("Loaded: " .. label) or ("Load failed: " .. tostring(err))
      end

      -- Drag source (for selected items)
      if ImGui.BeginDragDropSource and ImGui.BeginDragDropSource(ctx) then
        if ImGui.SetDragDropPayload then
          -- If multiple selected, indicate that
          if sel_count > 1 then
            ImGui.SetDragDropPayload(ctx, "FXMINER_ENTRY", rel)
            ImGui.Text(ctx, sel_count .. " items")
          else
            ImGui.SetDragDropPayload(ctx, "FXMINER_ENTRY", rel)
            ImGui.Text(ctx, label)
          end
        end
        state.dnd_name = sel_count > 1 and (sel_count .. " items") or label
        ImGui.EndDragDropSource(ctx)
      end
    end
  end
end

local function draw_inspector_panel(ctx)
  local ImGui = App.ImGui

  W.separator_text(ctx, ImGui, "Inspector")

  local is_team_item = state.selected_rel and state.selected_rel:match("^team:")
  local e = nil
  if not is_team_item then
    e = state.selected_rel and DB:find_entry_by_rel(state.selected_rel) or nil
  end

  -- Return if neither local nor team item is selected
  if not e and not is_team_item then
    ImGui.TextDisabled(ctx, "Select an item...")
    return
  end

  if is_team_item then
    ImGui.BeginDisabled(ctx, true)
    ImGui.TextDisabled(ctx, "(Team View Only)")
  else
    DB:_ensure_entry_defaults(e)
    e.metadata = e.metadata or {}
  end

  -- Name
  ImGui.Text(ctx, "Name")
  ImGui.PushItemWidth(ctx, -1)
  _, state.edit_name = ImGui.InputText(ctx, "##insp_name", state.edit_name)
  ImGui.PopItemWidth(ctx)

  -- Description
  ImGui.Text(ctx, "Description")
  ImGui.PushItemWidth(ctx, -1)
  _, state.edit_desc = ImGui.InputTextMultiline(ctx, "##insp_desc", state.edit_desc, 0, 60)
  ImGui.PopItemWidth(ctx)

  ImGui.Spacing(ctx)

  -- Dynamic fields from config_fields.json (pure text inputs)
  local fields = DB:get_fields_config()
  if type(fields) == "table" then
    for _, field in ipairs(fields) do
      local key = tostring(field.key or "")
      local label = tostring(field.label or key)
      if key ~= "" then
        -- ensure state.field_inputs[key] is synced with entry ONLY for local files
        if not is_team_item then
          if state.field_inputs[key] == nil then
            state.field_inputs[key] = tostring(e.metadata[key] or "")
          end
        end

        ImGui.Text(ctx, label)
        ImGui.PushItemWidth(ctx, -1)
        local _, newv = ImGui.InputText(ctx, "##insp_field_" .. key, state.field_inputs[key])
        state.field_inputs[key] = newv
        ImGui.PopItemWidth(ctx)
      end
    end
  end

  if is_team_item then
    ImGui.EndDisabled(ctx)
  else
    -- Save/Clear buttons only for local items
    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- Save button
    if ImGui.Button(ctx, "Save", -1, 0) then
      e.name = trim(state.edit_name)
      e.description = tostring(state.edit_desc or "")
      -- save all field inputs to metadata as strings
      if type(fields) == "table" then
        for _, field in ipairs(fields) do
          local key = tostring(field.key or "")
          if key ~= "" then
            e.metadata[key] = tostring(state.field_inputs[key] or "")
          end
        end
      end
      DB:update_entry(e)
      state.status = "Saved"
    end

    -- Clear button
    if ImGui.Button(ctx, "Clear", -1, 0) then
      -- clear all metadata fields
      if type(fields) == "table" then
        for _, field in ipairs(fields) do
          local key = tostring(field.key or "")
          if key ~= "" then
            e.metadata[key] = ""
            state.field_inputs[key] = ""
          end
        end
      end
      DB:update_entry(e)
      state.status = "Cleared"
    end
  end
end

function GuiBrowser.init(app_ctx, db_instance, cfg)
  App = app_ctx
  DB = db_instance
  Config = cfg

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

  state.search = ""
  state.selected_folder_id = -1
  state.selected_rel = nil
  state.selected_items = {} -- Multi-selection set
  state.last_clicked_idx = nil
  state.edit_name = ""
  state.edit_desc = ""
  state.category_idx = 0
  state.field_inputs = {}
  state.status = ""
  state.new_folder_name = ""
  state.show_new_folder_popup = false
  state.sync_in_progress = false
  state.team_sync_status = ""

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

  draw_topbar(ctx)
  dnd_update(ctx)

  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)

  -- If settings panel is open, show it instead of the normal layout
  if state.show_settings then
    if ImGui.BeginChild(ctx, "##fxminer_settings", 0, avail_h, ImGui.ChildFlags_Border or 0) then
      draw_settings_panel(ctx)
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
      draw_folders_panel(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)
  end

  -- Middle: list
  local list_w = math.max(220, avail_w - actual_folder_w - inspector_w - 16)
  if ImGui.BeginChild(ctx, "##fxminer_list", list_w, avail_h, ImGui.ChildFlags_Border or 0) then
    draw_list_panel(ctx)
    ImGui.EndChild(ctx)
  end

  ImGui.SameLine(ctx)

  -- Right: inspector
  if ImGui.BeginChild(ctx, "##fxminer_inspector", 0, avail_h, ImGui.ChildFlags_Border or 0) then
    draw_inspector_panel(ctx)
    ImGui.EndChild(ctx)
  end
end

return GuiBrowser
