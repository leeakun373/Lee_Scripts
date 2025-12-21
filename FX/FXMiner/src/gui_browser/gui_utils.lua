-- FXMiner/src/gui_browser/gui_utils.lua
-- 工具函数和 FX Chain 加载逻辑

local Utils = {}

-- Get state (will be injected)
local state = nil
local App, DB, Config = nil, nil, nil

-- String utilities
local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(s)
  return tostring(s or ""):lower()
end

function Utils.trim(s)
  return trim(s)
end

function Utils.lower(s)
  return lower(s)
end

-- Token splitting
function Utils.split_tokens(s)
  local out = {}
  s = trim(s)
  if s == "" then return out end
  for tok in s:gmatch("%S+") do
    out[#out + 1] = lower(tok)
  end
  return out
end

-- Array utilities
function Utils.array_contains(arr, value)
  if type(arr) ~= "table" then return false end
  for _, v in ipairs(arr) do
    if tostring(v) == tostring(value) then
      return true
    end
  end
  return false
end

function Utils.array_remove(arr, value)
  if type(arr) ~= "table" then return end
  for i = #arr, 1, -1 do
    if tostring(arr[i]) == tostring(value) then
      table.remove(arr, i)
    end
  end
end

function Utils.array_add_unique(arr, value)
  if type(arr) ~= "table" then return end
  value = trim(value)
  if value == "" then return end
  if Utils.array_contains(arr, value) then return end
  arr[#arr + 1] = value
end

-- FX Chain loading functions
function Utils.safe_append_fxchain(abs_path)
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

function Utils.safe_append_fxchain_to_track(track, abs_path)
  local r = reaper
  if not track then
    return Utils.safe_append_fxchain(abs_path)
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

function Utils.safe_append_fxchain_to_take(take, abs_path)
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
function Utils.detect_load_context()
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

function Utils.safe_append_fxchain_to_selected_items_or_track(abs_path)
  local r = reaper

  local context_type, context_objs = Utils.detect_load_context()

  if context_type == "item" and context_objs and #context_objs > 0 then
    -- Load on selected items
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local ok_any = false
    local last_err = nil
    for _, obj in ipairs(context_objs) do
      local ok, err = Utils.safe_append_fxchain_to_take(obj.take, abs_path)
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
      local ok, err = Utils.safe_append_fxchain_to_track(track, abs_path)
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
  return Utils.safe_append_fxchain(abs_path)
end

-- Smart track detection for drag & drop (handles empty area)
-- Returns track, take, and whether a new track was created
-- Based on RadialMenu_Tool's implementation pattern
local function smart_get_track_from_point(x, y, create_if_empty)
  local r = reaper
  local track = nil
  local take = nil
  local created_new_track = false
  
  -- 1. 优先检测 Item (GetItemFromPoint 是最准确的) - 参考 RadialMenu_Tool
  local item
  if r.GetItemFromPoint then
    item, take = r.GetItemFromPoint(x, y, true)
    if item then
      track = r.GetMediaItem_Track(item)
      if track then
        return track, take, false -- Found item, return immediately
      end
    end
  end
  
  -- 2. 如果不是 Item，检测 Track - 参考 RadialMenu_Tool 的简洁实现
  if r.GetTrackFromPoint then
    -- GetTrackFromPoint returns (track, info) or just track
    local ok, result = pcall(function()
      return r.GetTrackFromPoint(x, y)
    end)
    if ok then
      -- Handle different return formats
      if result then
        -- Check if it's a valid track pointer
        if r.ValidatePtr and r.ValidatePtr(result, "MediaTrack*") then
          track = result
        elseif type(result) == "userdata" then
          -- Might be a track pointer without ValidatePtr available
          track = result
        end
      end
    end
  end
  
  -- 3. 如果都不是且 create_if_empty 为 true，新建轨道 - 完全参考 RadialMenu_Tool 的实现
  if not track and create_if_empty then
    r.PreventUIRefresh(1)
    r.InsertTrackAtIndex(r.CountTracks(0), true)
    -- 插入后重新查询总数，新轨道索引 = CountTracks(0) - 1
    track = r.GetTrack(0, r.CountTracks(0) - 1)
    created_new_track = true
    
    -- Select the new track for visual feedback
    if track then
      r.SetOnlyTrackSelected(track)
    end
    
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
  end
  
  return track, take, created_new_track
end

-- Drag & drop update
function Utils.dnd_update(ctx)
  local ImGui = App.ImGui
  local r = reaper

  if not (ImGui.GetDragDropPayload and ImGui.GetDragDropPayload(ctx)) then
    state.dnd_name = nil
    return
  end

  if state.dnd_name and ImGui.SetTooltip then
    ImGui.SetTooltip(ctx, state.dnd_name)
  end

  -- Check if we're dragging outside our UI window
  if ImGui.IsWindowHovered and ImGui.HoveredFlags_AnyWindow then
    if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_AnyWindow) then
      -- Mouse is over our UI, don't process drag to REAPER
      return
    end
  end

  if ImGui.AcceptDragDropPayload then
    local ok, rv, payload = pcall(function()
      local rrv, pp = ImGui.AcceptDragDropPayload(ctx, "FXMINER_ENTRY")
      return rrv, pp
    end)
    if ok and rv and payload and payload ~= "" then
      -- Get mouse position when payload is accepted
      local x, y = r.GetMousePosition()
      
      -- Use smart track detection with create_if_empty=true
      -- This will create a new track if mouse is over empty area
      local track, take, created_new = smart_get_track_from_point(x, y, true)
      
      local rel = tostring(payload)
      local e = DB:find_entry_by_rel(rel)
      if e then
        local abs = DB:rel_to_abs(e.rel_path)
        local ok2, err
        
        if not track then
          -- Still no track after trying to create - might be outside arrange view
          state.status = "Drop failed: Not over a valid track or arrange area"
          state.dnd_name = nil
          return
        end
        
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        
        -- Prefer take when dropping on item
        if take then
          ok2, err = Utils.safe_append_fxchain_to_take(take, abs)
          if not ok2 then
            ok2, err = Utils.safe_append_fxchain_to_track(track, abs)
          end
        else
          ok2, err = Utils.safe_append_fxchain_to_track(track, abs)
        end
        
        r.PreventUIRefresh(-1)
        local undo_name = created_new and "FXMiner: Load FX Chain (New Track)" or "FXMiner: Load FX Chain"
        r.Undo_EndBlock(undo_name, -1)
        r.UpdateArrange()
        
        state.status = ok2 and ("Loaded: " .. tostring(e.name or "")) or ("Load failed: " .. tostring(err))
      end
      state.dnd_name = nil
    end
  end
end

-- Set selected entry (update inspector fields)
function Utils.set_selected_entry(rel)
  state.selected_rel = rel
  if not rel then
    state.edit_name = ""
    state.edit_desc = ""
    state.field_inputs = {}
    return
  end

  local is_team_item = rel:match("^team:")
  local e = nil

  if is_team_item then
    -- Team mode: find entry from team_entries
    local filename = rel:gsub("^team:", "")
    if state.team_entries and type(state.team_entries) == "table" then
      for _, team_e in ipairs(state.team_entries) do
        if team_e and team_e.filename == filename then
          e = team_e
          break
        end
      end
    end
  else
    -- Local mode: find entry from local DB
    e = rel and DB:find_entry_by_rel(rel) or nil
  end

  if not e then
    state.edit_name = ""
    state.edit_desc = ""
    state.field_inputs = {}
    return
  end

  -- For local entries, ensure defaults
  if not is_team_item then
    DB:_ensure_entry_defaults(e)
  end

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

-- Build search content from entry
function Utils.build_search_content(e)
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

-- Check if entry matches search tokens and filter criteria
function Utils.matches_search(e, tokens, filter_criteria)
  -- First check filter criteria (strict field matching)
  if filter_criteria and type(filter_criteria) == "table" then
    local field = tostring(filter_criteria.field or "")
    local value = tostring(filter_criteria.value or "")
    
    if field ~= "" and value ~= "" then
      DB:_ensure_entry_defaults(e)
      local entry_value = Utils.trim(tostring((e.metadata and e.metadata[field]) or ""))
      
      -- Case-insensitive comparison
      if Utils.lower(entry_value) ~= Utils.lower(value) then
        return false
      end
    end
  end

  -- Then check search tokens (fuzzy string matching)
  if #tokens == 0 then return true end

  local search_content = Utils.build_search_content(e)

  -- All tokens must be found in the search content
  for _, t in ipairs(tokens) do
    if not search_content:find(t, 1, true) then
      return false
    end
  end
  return true
end

-- Initialize utils module
function Utils.init(app_ctx, db_instance, cfg, state_table)
  App = app_ctx
  DB = db_instance
  Config = cfg
  state = state_table
end

return Utils

