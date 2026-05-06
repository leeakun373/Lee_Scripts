--[[
  REAPER Lua Script: Marker Workstation (Modular Version)
  Description: Modular marker/region management tool
  - Dynamically loads marker/region functions from MarkerFunctions directory
  - Provides unified GUI interface for all marker/region operations
  - Filter by Marker (M) or Region (R) type
  
  Architecture: Modular design for easy maintenance and extension
]]

-- Check if ReaImGui is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("This script requires ReaImGui extension.\nPlease install 'ReaImGui' from Extensions > ReaPack > Browse packages", "Missing Dependency", 0)
    return
end

-- Get script directory
local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
local path_sep = package.config:sub(1,1) == "/" and "/" or "\\"

-- Helper function to load module
local function loadModule(module_path)
    local f = loadfile(module_path)
    if f then
        return f()
    end
    return nil
end

-- Load modules
local Constants = loadModule(script_path .. "Config" .. path_sep .. "Constants.lua")
local Colors = loadModule(script_path .. "Config" .. path_sep .. "Colors.lua")
local Themes = loadModule(script_path .. "Config" .. path_sep .. "Themes.lua")
local DataManager = loadModule(script_path .. "Modules" .. path_sep .. "DataManager.lua")
local FunctionLoader = loadModule(script_path .. "Modules" .. path_sep .. "FunctionLoader.lua")
local Helpers = loadModule(script_path .. "Utils" .. path_sep .. "Helpers.lua")

-- Load remaining modules
local LayoutManager = loadModule(script_path .. "Modules" .. path_sep .. "LayoutManager.lua")
local CustomActionsManager = loadModule(script_path .. "Modules" .. path_sep .. "CustomActionsManager.lua")
local GUI = loadModule(script_path .. "Modules" .. path_sep .. "GUI.lua")

-- Get functions directory (MarkerFunctions is now in MarkersWorkstation folder)
local functions_dir = script_path .. "MarkerFunctions" .. path_sep

-- Toggle functionality: Check if script is already running
if DataManager.isScriptRunning() then
    -- Script is already running, request it to close
    DataManager.setCloseRequest(true)
    -- Wait a moment for the other instance to close
    reaper.defer(function()
        DataManager.setScriptRunning(false)
        DataManager.setCloseRequest(false)
    end)
    return
else
    -- Mark script as running
    DataManager.setScriptRunning(true)
    DataManager.setCloseRequest(false)
end

-- Initialize state
local state = {
    gui = {
        ctx = reaper.ImGui_CreateContext('Marker Workstation'),
        visible = true,
        window_state = DataManager.loadWindowState()
    },
    filter_state = {
        show_markers = true,
        show_regions = true
    },
    tooltip_timers = {},
    status_message = "Ready",
    pending_swaps = {},
    marker_functions = {},
    custom_actions = DataManager.loadCustomActions(),
    layout = DataManager.loadLayout(),
    layout_presets = DataManager.loadLayoutPresets(),
    function_order = DataManager.loadFunctionOrder()
}

-- Store functions directory in state
state.functions_dir = functions_dir

-- Force use Modern theme (no theme selector)
Themes.setCurrentTheme("modern")

-- Get theme colors for function loading
local current_theme = Themes.getCurrentTheme()
local theme_colors = {
    BTN_MARKER_ON  = current_theme.BTN_MARKER_ON,
    BTN_MARKER_OFF = current_theme.BTN_MARKER_OFF,
    BTN_REGION_ON  = current_theme.BTN_REGION_ON,
    BTN_REGION_OFF = current_theme.BTN_REGION_OFF,
    BTN_RELOAD     = current_theme.BTN_RELOAD,
    BTN_MANAGER    = current_theme.BTN_MANAGER,
    BTN_CUSTOM     = current_theme.BTN_CUSTOM,
    BTN_DELETE     = current_theme.BTN_DELETE,
    TEXT_NORMAL    = current_theme.TEXT_NORMAL,
    TEXT_DIM       = current_theme.TEXT_DIM,
    BG_HEADER      = current_theme.BG_HEADER,
}

-- Load marker functions (with theme colors)
state.marker_functions = FunctionLoader.loadFunctions(functions_dir, DataManager, theme_colors)

-- Initialize layout (first time setup)
if LayoutManager.initializeLayout(state.layout, state.marker_functions, state.custom_actions) then
    DataManager.saveLayout(state.layout)
end

-- Initialize UI state
state.new_action = {
    name = "",
    action_id = "",
    description = "",
    type = "marker"
}
state.editing_index = nil
state.current_preset_name = ""
state.new_preset_name = ""
-- Cache flags for performance optimization
state.layout_cache_dirty = false
state.stash_cache = nil

-- Main loop
local function main_loop()
    -- Check for close request (toggle functionality)
    if DataManager.isCloseRequested() then
        state.gui.visible = false
        DataManager.setScriptRunning(false)
        DataManager.setCloseRequest(false)
        DataManager.saveWindowState(state.gui.window_state)
        return
    end
    
    if not GUI then
        reaper.ShowMessageBox("GUI module not found. Please ensure GUI.lua exists in Modules directory.", "Error", 0)
        return
    end
    
        local should_continue = GUI.render(state, {
            Constants = Constants,
            Colors = Colors,
            Themes = Themes,
            DataManager = DataManager,
            FunctionLoader = FunctionLoader,
            LayoutManager = LayoutManager,
            CustomActionsManager = CustomActionsManager,
            Helpers = Helpers
        })
    
    -- Update window state
    local win_x, win_y = reaper.ImGui_GetWindowPos(state.gui.ctx)
    local win_width, win_height = reaper.ImGui_GetWindowSize(state.gui.ctx)
    if win_x and win_y then
        state.gui.window_state.x = win_x
        state.gui.window_state.y = win_y
    end
    if win_width and win_height and win_width > 0 and win_height > 0 then
        state.gui.window_state.width = win_width
        state.gui.window_state.height = win_height
    end
    
    if should_continue and state.gui.visible then
        reaper.defer(main_loop)
    else
        DataManager.saveWindowState(state.gui.window_state)
        DataManager.setScriptRunning(false)
        DataManager.setCloseRequest(false)
        return
    end
end

-- Launch GUI
main_loop()

