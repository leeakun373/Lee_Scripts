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

-- Draw the inspector panel
function GuiInspector.draw(ctx)
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
