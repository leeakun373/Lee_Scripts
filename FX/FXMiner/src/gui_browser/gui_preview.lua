-- FXMiner/src/gui_browser/gui_preview.lua
-- Chain Preview 面板：显示选中 Chain 的插件列表

local W = require("widgets")

local GuiPreview = {}

-- Get dependencies (will be injected)
local state = nil
local App, DB, Config = nil, nil, nil
local Engine = nil

-- Initialize dependencies
function GuiPreview.init(_state, _App, _DB, _Config, _Engine)
  state = _state
  App = _App
  DB = _DB
  Config = _Config
  Engine = _Engine
end

-- Lazy load Engine if not provided
local function ensure_engine()
  if Engine then return true end
  local ok, eng = pcall(require, "fx_engine")
  if ok and eng then
    Engine = eng
    return true
  end
  return false
end

-- Check if a plugin is installed
local function is_plugin_installed(plugin_name)
  if not plugin_name or plugin_name == "" then return false end
  
  -- Ensure Engine is available
  if not ensure_engine() then return true end -- If Engine not available, assume installed to avoid false positives
  
  -- Lazy load installed FX map
  if not state.installed_fx_map then
    if Engine and Engine.get_installed_fx_map then
      state.installed_fx_map = Engine.get_installed_fx_map()
    else
      state.installed_fx_map = {} -- Empty map if function not available
    end
  end
  
  local map = state.installed_fx_map or {}
  
  -- Try exact match first
  if map[plugin_name] then
    return true
  end
  
  -- Try fuzzy match (check if any key contains the plugin name or vice versa)
  for key, _ in pairs(map) do
    if key == plugin_name then
      return true
    end
    -- Simple substring matching
    if string.find(key, plugin_name, 1, true) or string.find(plugin_name, key, 1, true) then
      return true
    end
  end
  
  return false
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
        -- Check if plugin is installed
        local is_installed = is_plugin_installed(name)
        
        -- If not installed, use red color
        if not is_installed then
          local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text
          if ImGui.PushStyleColor and col_text then
            ImGui.PushStyleColor(ctx, col_text, 0xFF5555FF) -- Red color
          end
        end
        
        -- Display with index number
        ImGui.Text(ctx, string.format("%d. %s", i, name))
        
        -- Show tooltip
        if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.SetTooltip then
          if not is_installed then
            ImGui.SetTooltip(ctx, "Plugin not found on this system")
          else
            ImGui.SetTooltip(ctx, name)
          end
        end
        
        -- Pop color if we pushed it
        if not is_installed and ImGui.PopStyleColor then
          ImGui.PopStyleColor(ctx, 1)
        end
      end
    end
    ImGui.EndChild(ctx)
  end
end

return GuiPreview

