--[[
  REAPER Lua Script: FX Manager
  Description: Modular FX management tool
  - Open all FX windows for selected tracks (with auto-arrangement)
  - Close all FX windows
  - Toggle Bypass/Active (smart detection)
  - Toggle FX Chain window (auto-detect Item/Track)
  
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
local FXFunctions = loadModule(script_path .. "Modules" .. path_sep .. "FXFunctions.lua")
local CustomActionsManager = loadModule(script_path .. "Modules" .. path_sep .. "CustomActionsManager.lua")
local LayoutManager = loadModule(script_path .. "Modules" .. path_sep .. "LayoutManager.lua")
local FXLoader = loadModule(script_path .. "Modules" .. path_sep .. "FXLoader.lua")
local Helpers = loadModule(script_path .. "Utils" .. path_sep .. "Helpers.lua")
local GUI = loadModule(script_path .. "Modules" .. path_sep .. "GUI.lua")

-- Check if all modules loaded successfully
if not Constants or not Colors or not Themes or not DataManager or not FXFunctions or not Helpers or not GUI then
    reaper.ShowMessageBox("Failed to load required modules. Please ensure all module files exist.", "Error", 0)
    return
end

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
        ctx = reaper.ImGui_CreateContext('FX Manager'),
        visible = true,
        window_state = DataManager.loadWindowState()
    },
    status_message = "就绪",
    tooltip_timers = {},
    -- Built-in functions
    builtin_functions = {
        {name = "OpenAllTrackFXWindows", is_custom = false},
        {name = "CloseAllFXWindows", is_custom = false},
        {name = "ToggleBypassOrActive", is_custom = false},
        {name = "ToggleFXChainWindow", is_custom = false}
    },
    -- Layout and custom actions
    layout = DataManager.loadLayout(),
    custom_actions = DataManager.loadCustomActions(),
    layout_presets = DataManager.loadLayoutPresets(),
    -- FX Loader
    fx_buttons = DataManager.loadFXButtons(),
    fx_presets = DataManager.loadFXPresets(),
    buttons_per_row = 2
}

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
        FXFunctions = FXFunctions,
        CustomActionsManager = CustomActionsManager,
        LayoutManager = LayoutManager,
        FXLoader = FXLoader,
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

