-- FXMiner/src/gui_browser/gui_list.lua
-- 列表面板的绘制和交互逻辑（包括多选支持）

local W = require("widgets")

local GuiList = {}

-- Get dependencies (will be injected)
local state = nil
local App, DB, Config = nil, nil, nil
local Utils = nil

-- Initialize dependencies
function GuiList.init(_state, _App, _DB, _Config, _Utils)
  state = _state
  App = _App
  DB = _DB
  Config = _Config
  Utils = _Utils
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

-- Draw the list panel
function GuiList.draw(ctx)
  local ImGui = App.ImGui

  local is_team_mode = (state.library_mode == "team")
  local lib_label = is_team_mode and "Team Library" or "Local Library"

  -- Header with selection count
  local sel_count = count_selected()
  if sel_count > 1 then
    lib_label = lib_label .. " (" .. sel_count .. " selected)"
  end
  W.separator_text(ctx, ImGui, lib_label)

  ImGui.TextDisabled(ctx, "Shift+Click: range select | Ctrl+Click: toggle | Ctrl+A: select all | Click empty: deselect")
  ImGui.Separator(ctx)
  
  local tokens = Utils.split_tokens(state.search)
  local folder_id = tonumber(state.selected_folder_id) or 0

  local items = {}

  if is_team_mode then
    -- Team mode: show entries from team DB
    for _, e in ipairs(state.team_entries or {}) do
      if e then
        -- Build search content for team entries
        local search_content = Utils.lower(tostring(e.name or "") .. " " .. tostring(e.description or ""))
        if type(e.metadata) == "table" then
          for _, v in pairs(e.metadata) do
            search_content = search_content .. " " .. Utils.lower(tostring(v or ""))
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
        -- Folder filter: -1 means "All", otherwise match folder_id
        local in_folder = true
        if state.selected_folder_id ~= -1 then
          local e_folder_id = tonumber(e.folder_id) or 0
          in_folder = (e_folder_id == folder_id)
        end
        if in_folder and Utils.matches_search(e, tokens) then
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
          local ok, err = Utils.safe_append_fxchain_to_selected_items_or_track(abs)
          state.status = ok and ("Loaded from Team: " .. label) or ("Load failed: " .. tostring(err))
        end
      end
    else
      -- Local entry
      local rel = tostring(e.rel_path or "")

      if ImGui.Selectable(ctx, label .. "##it_" .. tostring(i), is_sel) then
        handle_selection_click(items, i, item_id)
        Utils.set_selected_entry(rel)
      end

      -- Double click load
      if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0) then
        local abs = DB:rel_to_abs(e.rel_path)
        local ok, err = Utils.safe_append_fxchain_to_selected_items_or_track(abs)
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

      -- Right-click context menu for local entries
      local popup_id = "fxminer_item_menu_" .. tostring(i)
      -- Use BeginPopupContextItem if available (more reliable)
      if ImGui.BeginPopupContextItem then
        if ImGui.BeginPopupContextItem(ctx, popup_id) then
          if ImGui.MenuItem(ctx, "删除") then
            state.show_delete_confirm = true
            state.delete_target_rel = rel
            state.delete_target_name = label
            state.delete_selected_items = false
            ImGui.CloseCurrentPopup(ctx)
          end
          ImGui.EndPopup(ctx)
        end
      else
        -- Fallback: use IsItemClicked + OpenPopup (same as folder menu)
        if ImGui.IsItemClicked and ImGui.IsItemClicked(ctx, 1) and ImGui.OpenPopup then
          ImGui.OpenPopup(ctx, popup_id)
        end
        if ImGui.BeginPopup and ImGui.EndPopup and ImGui.BeginPopup(ctx, popup_id) then
          if ImGui.MenuItem(ctx, "删除") then
            state.show_delete_confirm = true
            state.delete_target_rel = rel
            state.delete_target_name = label
            state.delete_selected_items = false
            ImGui.CloseCurrentPopup(ctx)
          end
          ImGui.EndPopup(ctx)
        end
      end
    end
  end
  
  -- Handle Ctrl+A for select all (check after all items are rendered)
  if ImGui.IsWindowFocused and ImGui.IsWindowFocused(ctx) then
    local mod_ctrl = ImGui.Mod_Ctrl or 0x0001
    local key_a = ImGui.Key_A or 65
    local ctrl_held = false
    local a_pressed = false
    
    if ImGui.IsKeyDown then
      ctrl_held = ImGui.IsKeyDown(ctx, mod_ctrl)
    end
    if ImGui.GetKeyMods then
      local mods = ImGui.GetKeyMods(ctx)
      ctrl_held = (mods & mod_ctrl) ~= 0
    end
    
    if ImGui.IsKeyPressed then
      a_pressed = ImGui.IsKeyPressed(ctx, key_a)
    end
    
    if ctrl_held and a_pressed then
      -- Select all items
      state.selected_items = {}
      for _, e in ipairs(items) do
        local item_id = get_item_id(e)
        state.selected_items[item_id] = true
      end
      if #items > 0 then
        state.selected_rel = get_item_id(items[1])
      end
    end
  end
  
  -- Handle click on empty area to deselect
  -- Use InvisibleButton to capture clicks on empty area below items
  if ImGui.InvisibleButton then
    local avail_x, avail_y = ImGui.GetContentRegionAvail(ctx)
    if avail_y and avail_y > 0 then
      -- Use full width and available height
      if ImGui.InvisibleButton(ctx, "##empty_area", avail_x or -1, avail_y) then
        -- Button was clicked
        local mod_ctrl = ImGui.Mod_Ctrl or 0x0001
        local mod_shift = ImGui.Mod_Shift or 0x0002
        local ctrl_held = false
        local shift_held = false
        
        if ImGui.IsKeyDown then
          ctrl_held = ImGui.IsKeyDown(ctx, mod_ctrl)
          shift_held = ImGui.IsKeyDown(ctx, mod_shift)
        end
        if ImGui.GetKeyMods then
          local mods = ImGui.GetKeyMods(ctx)
          ctrl_held = (mods & mod_ctrl) ~= 0
          shift_held = (mods & mod_shift) ~= 0
        end
        
        -- Only deselect if no modifiers are held
        if not ctrl_held and not shift_held then
          state.selected_items = {}
          state.selected_rel = nil
          state.last_clicked_idx = nil
        end
      end
    end
  end
end

-- Export selection helpers for use in other modules
GuiList.count_selected = count_selected
GuiList.get_item_id = get_item_id
GuiList.is_item_selected = is_item_selected

return GuiList
