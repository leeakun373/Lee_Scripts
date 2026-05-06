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

-- Get script directory and set up module path
local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
local markers_dir = script_path:match("(.+[/\\])MarkersWorkstation")
package.path = package.path .. ";" .. script_path .. "?.lua"
package.path = package.path .. ";" .. markers_dir .. "?.lua"

-- Load modules
local Constants = require("MarkersWorkstation.Config.Constants")
local Colors = require("MarkersWorkstation.Config.Colors")
local DataManager = require("MarkersWorkstation.Modules.DataManager")
local FunctionLoader = require("MarkersWorkstation.Modules.FunctionLoader")
local Helpers = require("MarkersWorkstation.Utils.Helpers")

-- TODO: Load remaining modules when completed
-- local LayoutManager = require("MarkersWorkstation.Modules.LayoutManager")
-- local CustomActionsManager = require("MarkersWorkstation.Modules.CustomActionsManager")
-- local GUI = require("MarkersWorkstation.Modules.GUI")

-- Get functions directory
local functions_dir = markers_dir .. "MarkerFunctions" .. (package.config:sub(1,1) == "/" and "/" or "\\")

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

-- Load marker functions
state.marker_functions = FunctionLoader.loadFunctions(functions_dir)

-- TODO: Initialize layout manager
-- TODO: Initialize custom actions manager
-- TODO: Initialize GUI

-- Main loop placeholder
local function main_loop()
    -- Check for close request (toggle functionality)
    if DataManager.isCloseRequested() then
        state.gui.visible = false
        DataManager.setScriptRunning(false)
        DataManager.setCloseRequest(false)
        DataManager.saveWindowState(state.gui.window_state)
        return
    end
    
    -- TODO: Render GUI
    -- GUI.render(state)
    
    -- TODO: Update window state
    
    if state.gui.visible then
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


