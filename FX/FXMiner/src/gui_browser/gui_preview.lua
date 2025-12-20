-- FXMiner/src/gui_browser/gui_preview.lua
-- Chain Preview 面板：显示选中 Chain 的插件列表

local W = require("widgets")

local GuiPreview = {}

-- Get dependencies (will be injected)
local state = nil
local App, DB, Config = nil, nil, nil

-- Initialize dependencies
function GuiPreview.init(_state, _App, _DB, _Config)
  state = _state
  App = _App
  DB = _DB
  Config = _Config
end

-- Draw the preview panel
function GuiPreview.draw(ctx)
  local ImGui = App.ImGui

  W.separator_text(ctx, ImGui, "Chain Preview")

  -- Get current selected entry
  local e = nil
  local is_team_item = state.selected_rel and state.selected_rel:match("^team:")
  
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
  elseif state.selected_rel then
    -- Local mode: find entry from local DB
    e = DB:find_entry_by_rel(state.selected_rel)
  end

  -- If no selection or no data
  if not e then
    ImGui.TextDisabled(ctx, "Select a chain to preview")
    return
  end

  -- Ensure entry defaults (only for local entries)
  if not is_team_item then
    DB:_ensure_entry_defaults(e)
  end

  -- Check if plugins data is available
  if not e.plugins or type(e.plugins) ~= "table" then
    ImGui.TextDisabled(ctx, "No plugin data (Try Refresh)")
    return
  end

  if #e.plugins == 0 then
    ImGui.TextDisabled(ctx, "(Empty Chain)")
    return
  end

  -- Draw plugin list with scrollable area
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
  if ImGui.BeginChild(ctx, "##preview_list", 0, avail_h - 5, ImGui.ChildFlags_Border or 0) then
    for i, plugin_name in ipairs(e.plugins) do
      local name = tostring(plugin_name or "")
      if name ~= "" then
        -- Display with index number
        ImGui.Text(ctx, string.format("%d. %s", i, name))
        
        -- Show full name on hover (for long plugin names)
        if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.SetTooltip then
          ImGui.SetTooltip(ctx, name)
        end
      end
    end
    ImGui.EndChild(ctx)
  end
end

return GuiPreview

