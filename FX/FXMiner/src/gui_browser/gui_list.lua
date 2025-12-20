-- FXMiner/src/gui_browser/gui_list.lua
-- 列表面板的绘制和交互逻辑（包括多选支持）

local W = require("widgets")

local GuiList = {}

-- Get dependencies (will be injected)
local state = nil
local App, DB, Config = nil, nil, nil
local Utils = nil

function GuiList.init(_state, _App, _DB, _Config, _Utils)
  state = _state
  App = _App
  DB = _DB
  Config = _Config
  Utils = _Utils
end

local function get_item_id(e)
  -- Check if we're in team mode or if entry has is_team flag
  if state.library_mode == "team" then
    return "team:" .. tostring(e.filename or "")
  elseif e.is_team then
    return "team:" .. tostring(e.filename or "")
  else
    return tostring(e.rel_path or "")
  end
end

local function is_item_selected(item_id)
  return state.selected_items[item_id] == true
end

function GuiList.count_selected()
  local n = 0
  for _ in pairs(state.selected_items) do n = n + 1 end
  return n
end

local function handle_selection_click(items, idx, item_id, ctrl, shift)
  if shift and state.last_clicked_idx then
    state.selected_items = {}
    local start_i = math.min(state.last_clicked_idx, idx)
    local end_i = math.max(state.last_clicked_idx, idx)
    for i = start_i, end_i do
      local e = items[i]
      if e then
        local eid = get_item_id(e)
        state.selected_items[eid] = true
        if i == idx then state.selected_rel = eid end
      end
    end
  elseif ctrl then
    if state.selected_items[item_id] then
      state.selected_items[item_id] = nil
      if state.selected_rel == item_id then state.selected_rel = nil end
    else
      state.selected_items[item_id] = true
      state.selected_rel = item_id
      state.last_clicked_idx = idx
    end
  else
    state.selected_items = { [item_id] = true }
    state.selected_rel = item_id
    state.last_clicked_idx = idx
  end
end

function GuiList.draw(ctx)
  local ImGui = App.ImGui

  local entries = {}
  if state.library_mode == "team" then entries = state.team_entries or {} else entries = DB:entries() end

  local items = {}
  local search = Utils.lower(Utils.trim(state.search))

  for _, e in ipairs(entries) do
    if state.library_mode == "local" then
      local show = false
      if state.selected_folder_id == -1 then
        show = true
      else
        if tonumber(e.folder_id) == state.selected_folder_id then show = true end
      end
      if not show then goto continue_entry end
    end

    if state.library_filter then
      local f = state.library_filter
      local val = ""
      if e.metadata then val = e.metadata[f.field] or "" end
      if Utils.lower(val) ~= Utils.lower(f.value) then goto continue_entry end
    end

    if search ~= "" then
      local match = false
      if (e.name and Utils.lower(e.name):find(search, 1, true)) then match = true end
      if not match and (e.keywords and Utils.lower(e.keywords):find(search, 1, true)) then match = true end
      if not match and e.metadata then
        for k, v in pairs(e.metadata) do
          if type(v) == "string" and Utils.lower(v):find(search, 1, true) then match = true; break end
        end
      end
      if not match then goto continue_entry end
    end

    table.insert(items, e)
    ::continue_entry::
  end

  table.sort(items, function(a,b) return (a.name or "") < (b.name or "") end)

  if ImGui.BeginTable(ctx, "EntriesTable", 2, ImGui.TableFlags_RowBg) then
    ImGui.TableSetupColumn(ctx, "Name", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "Tags", ImGui.TableColumnFlags_WidthFixed, 100)
    
    -- Reuse ListClipper instance (avoid excessive creation)
    if not state.list_clipper or (ImGui.ValidatePtr and not ImGui.ValidatePtr(state.list_clipper, "ImGui_ListClipper*")) then
      state.list_clipper = ImGui.CreateListClipper(ctx)
    end
    
    if state.list_clipper then
      ImGui.ListClipper_Begin(state.list_clipper, #items)
      while ImGui.ListClipper_Step(state.list_clipper) do
        local display_start, display_end = ImGui.ListClipper_GetDisplayRange(state.list_clipper)
        for i = display_start + 1, display_end do
        local e = items[i]
        local item_id = get_item_id(e)
        local is_sel = is_item_selected(item_id)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx)
        
        local icon = "📄"
        local label = icon .. " " .. (e.name or "???") .. "##" .. item_id
        if ImGui.Selectable(ctx, label, is_sel, ImGui.SelectableFlags_SpanAllColumns) then
           local mod_ctrl = ImGui.Mod_Ctrl or 0
           local mod_shift = ImGui.Mod_Shift or 0
           local ctrl = false
           local shift = false
           if ImGui.GetKeyMods then
             local mods = ImGui.GetKeyMods(ctx)
             ctrl = (mods & mod_ctrl) ~= 0
             shift = (mods & mod_shift) ~= 0
           end
           handle_selection_click(items, i, item_id, ctrl, shift)
        end
        
        if ImGui.BeginDragDropSource and ImGui.BeginDragDropSource(ctx) then
          if ImGui.SetDragDropPayload then
            ImGui.SetDragDropPayload(ctx, "FXMINER_ENTRY", item_id)
            ImGui.Text(ctx, e.name or "")
            state.dnd_name = e.name
          end
          ImGui.EndDragDropSource(ctx)
        end

        if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
          Utils.load_chain(e)
        end

        ImGui.TableNextColumn(ctx)
        local kw = e.keywords or ""
        if kw == "" and e.metadata and e.metadata.Theme then
           kw = "(" .. e.metadata.Theme .. ")"
        end
        ImGui.TextDisabled(ctx, kw)
      end
    end
    ImGui.ListClipper_End(state.list_clipper)
    end
    ImGui.EndTable(ctx)
  end
  
  if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx, 0) and not ImGui.IsAnyItemHovered(ctx) then
     state.selected_items = {}
     state.selected_rel = nil
  end
end

return GuiList
