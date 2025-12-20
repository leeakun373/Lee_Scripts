-- FXMiner/src/gui_browser/gui_inspector.lua
-- 检查器面板的绘制和编辑逻辑

local W = require("widgets")

local GuiInspector = {}

-- Get dependencies (will be injected)
local state = nil
local App, DB, Config = nil, nil, nil
local Utils = nil
local GuiList = nil -- For count_selected

-- Initialize dependencies
function GuiInspector.init(_state, _App, _DB, _Config, _Utils, _GuiList)
  state = _state
  App = _App
  DB = _DB
  Config = _Config
  Utils = _Utils
  GuiList = _GuiList
end

-- Helper function: Append keywords to Keywords field (avoid duplicates)
local function append_keywords(state, new_keywords)
  if not new_keywords or type(new_keywords) ~= "table" or #new_keywords == 0 then
    return
  end

  local current_keywords = state.field_inputs["Keywords"] or ""
  local keyword_parts = {}
  local seen = {}

  -- Parse existing keywords (split by comma)
  if current_keywords ~= "" then
    for kw in current_keywords:gmatch("([^,]+)") do
      kw = Utils.trim(kw)
      if kw ~= "" then
        local kw_lower = Utils.lower(kw)
        if not seen[kw_lower] then
          seen[kw_lower] = true
          keyword_parts[#keyword_parts + 1] = kw
        end
      end
    end
  end

  -- Add new keywords (avoid duplicates)
  for _, new_kw in ipairs(new_keywords) do
    new_kw = Utils.trim(tostring(new_kw))
    if new_kw ~= "" then
      local kw_lower = Utils.lower(new_kw)
      if not seen[kw_lower] then
        seen[kw_lower] = true
        keyword_parts[#keyword_parts + 1] = new_kw
      end
    end
  end

  -- Update Keywords field
  state.field_inputs["Keywords"] = table.concat(keyword_parts, ", ")
end

-- Draw the inspector panel
function GuiInspector.draw(ctx)
  local ImGui = App.ImGui

  W.separator_text(ctx, ImGui, "Inspector")

  -- Sync inspector fields when selected_rel changes
  if state.selected_rel ~= (state._last_synced_rel or nil) then
    Utils.set_selected_entry(state.selected_rel)
    state._last_synced_rel = state.selected_rel
  end

  local is_team_item = state.selected_rel and state.selected_rel:match("^team:")
  local e = nil
  
  if is_team_item then
    -- Team mode: find entry from team_entries
    local filename = state.selected_rel:gsub("^team:", "")
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
    e = state.selected_rel and DB:find_entry_by_rel(state.selected_rel) or nil
  end

  -- Return if no item is selected
  if not e then
    ImGui.TextDisabled(ctx, "Select an item...")
    return
  end

  if is_team_item then
    -- Team entries are read-only
    ImGui.BeginDisabled(ctx, true)
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

  -- Dynamic fields from config_fields.json
  local fields = DB:get_fields_config()
  if type(fields) == "table" then
    for _, field in ipairs(fields) do
      local key = tostring(field.key or "")
      local label = tostring(field.label or key)
      if key ~= "" then
        -- state.field_inputs is already synced by Utils.set_selected_entry above

        ImGui.Text(ctx, label)
        ImGui.PushItemWidth(ctx, -1)

        -- Special handling for Theme field: use Autocomplete Input
        if key == "Theme" then
          local theme_val = state.field_inputs[key] or ""
          local theme_changed, new_theme = ImGui.InputText(ctx, "##insp_field_" .. key, theme_val)
          
          if theme_changed then
            state.field_inputs[key] = new_theme
            -- Note: We don't trigger smart tagging on every keystroke, only on final selection
          end

          -- Auto-complete Popup: Open if input is active or clicked
          local popup_id = "##theme_auto_complete_" .. key
          
          -- Open popup when input is active (user is typing)
          if ImGui.IsItemActive and ImGui.IsItemActive(ctx) then
            if ImGui.OpenPopup then
              ImGui.OpenPopup(ctx, popup_id)
            end
          end
          
          -- Also open on click
          if ImGui.IsItemClicked and ImGui.IsItemClicked(ctx, 0) then
            if ImGui.OpenPopup then
              ImGui.OpenPopup(ctx, popup_id)
            end
          end

          -- Configure popup position and size
          if ImGui.SetNextWindowPos then
            local item_min_x, item_min_y = ImGui.GetItemRectMin(ctx)
            local item_max_x, item_max_y = ImGui.GetItemRectMax(ctx)
            if item_min_x and item_min_y and item_max_y then
              ImGui.SetNextWindowPos(ctx, item_min_x, item_max_y)
            end
          end
          
          if ImGui.SetNextWindowSizeConstraints then
            ImGui.SetNextWindowSizeConstraints(ctx, 200, 0, 300, 200)
          end
          
          local window_flags = 0
          if ImGui.WindowFlags_NoFocusOnAppearing then
            window_flags = ImGui.WindowFlags_NoFocusOnAppearing
          end
          
          if ImGui.BeginPopup and ImGui.BeginPopup(ctx, popup_id, window_flags) then
            local all_themes = DB:get_all_themes() or {}
            local search_str = Utils.lower(new_theme or "")

            -- Add "None" option if search is empty or matches
            local none_str = "(none)"
            if search_str == "" or string.find(none_str, search_str, 1, true) then
              if ImGui.Selectable(ctx, "(None)") then
                state.field_inputs[key] = ""
                if ImGui.CloseCurrentPopup then
                  ImGui.CloseCurrentPopup(ctx)
                end
              end
            end

            -- Filter and display matching themes
            for _, theme_name in ipairs(all_themes) do
              -- Filter: Show all if input is empty, otherwise show matches
              local theme_lower = Utils.lower(theme_name)
              if search_str == "" or string.find(theme_lower, search_str, 1, true) then
                local is_selected = (new_theme == theme_name)
                if ImGui.Selectable(ctx, theme_name, is_selected) then
                  -- User selected a theme from list
                  state.field_inputs[key] = theme_name

                  -- Smart Tagging Trigger: Append keywords to Keywords field
                  if theme_name ~= "" then
                    local keywords = DB:get_keywords_for_theme(theme_name)
                    if keywords and #keywords > 0 then
                      append_keywords(state, keywords)
                    end
                  end

                  if ImGui.CloseCurrentPopup then
                    ImGui.CloseCurrentPopup(ctx)
                  end
                end
                if is_selected and ImGui.SetItemDefaultFocus then
                  ImGui.SetItemDefaultFocus(ctx)
                end
              end
            end
            
            ImGui.EndPopup(ctx)
          end
        else
          -- Regular text input for other fields
          local _, newv = ImGui.InputText(ctx, "##insp_field_" .. key, state.field_inputs[key])
          state.field_inputs[key] = newv
        end
        
        ImGui.PopItemWidth(ctx)
      end
    end
  end

  -- Display team entry data (read-only)
  if is_team_item then
    -- Name (read-only for team entries)
    ImGui.Text(ctx, "Name")
    ImGui.PushItemWidth(ctx, -1)
    ImGui.InputText(ctx, "##insp_name", tostring(e.name or ""), ImGui.InputTextFlags_ReadOnly or 0)
    ImGui.PopItemWidth(ctx)

    -- Description (read-only for team entries)
    ImGui.Text(ctx, "Description")
    ImGui.PushItemWidth(ctx, -1)
    ImGui.InputTextMultiline(ctx, "##insp_desc", tostring(e.description or ""), 0, 60, ImGui.InputTextFlags_ReadOnly or 0)
    ImGui.PopItemWidth(ctx)

    ImGui.Spacing(ctx)

    -- Dynamic fields from config_fields.json (read-only)
    local fields = DB:get_fields_config()
    if type(fields) == "table" then
      for _, field in ipairs(fields) do
        local key = tostring(field.key or "")
        local label = tostring(field.label or key)
        if key ~= "" then
          local val = ""
          if e.metadata and e.metadata[key] then
            val = tostring(e.metadata[key])
          end
          ImGui.Text(ctx, label)
          ImGui.PushItemWidth(ctx, -1)
          ImGui.InputText(ctx, "##insp_field_" .. key, val, ImGui.InputTextFlags_ReadOnly or 0)
          ImGui.PopItemWidth(ctx)
        end
      end
    end

    ImGui.EndDisabled(ctx)
  else
    -- Save/Clear buttons only for local items
    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- Save button
    if ImGui.Button(ctx, "Save", -1, 0) then
      e.name = Utils.trim(state.edit_name)
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

    ImGui.Spacing(ctx)

    -- Delete button (red)
    if ImGui.PushStyleColor and ImGui.PopStyleColor then
      local col_button = type(ImGui.Col_Button) == "function" and ImGui.Col_Button() or ImGui.Col_Button
      ImGui.PushStyleColor(ctx, col_button, 0xCC0000FF)
      local col_button_hovered = type(ImGui.Col_ButtonHovered) == "function" and ImGui.Col_ButtonHovered() or ImGui.Col_ButtonHovered
      ImGui.PushStyleColor(ctx, col_button_hovered, 0xFF0000FF)
    end

    local sel_count = GuiList and GuiList.count_selected() or 0
    local delete_label = sel_count > 1 and ("删除选中 (" .. sel_count .. ")") or "删除"
    if ImGui.Button(ctx, delete_label, -1, 0) then
      state.show_delete_confirm = true
      if sel_count > 1 then
        state.delete_selected_items = true
        state.delete_target_rel = nil
        state.delete_target_name = nil
      else
        state.delete_selected_items = false
        state.delete_target_rel = state.selected_rel
        state.delete_target_name = e.name or "(Unnamed)"
      end
    end

    if ImGui.PushStyleColor and ImGui.PopStyleColor then
      ImGui.PopStyleColor(ctx, 2)
    end
  end
end

return GuiInspector
