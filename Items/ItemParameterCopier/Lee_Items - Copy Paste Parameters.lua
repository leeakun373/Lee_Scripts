--[[
  REAPER Lua Script: Item Parameter Copier
  Description: Copy and paste item/take parameters between items
  - Copy parameters from selected item
  - Paste to any selected items (same track or different tracks)
  - GUI interface for selecting which parameters to copy/paste
]]

-- Check if ReaImGui is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("此脚本需要 ReaImGui 扩展。\n请从 Extensions > ReaPack > Browse packages 安装 'ReaImGui'", "缺少依赖", 0)
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
local ParameterManager = loadModule(script_path .. "Modules" .. path_sep .. "ParameterManager.lua")
local GUI = loadModule(script_path .. "Modules" .. path_sep .. "GUI.lua")
local Helpers = loadModule(script_path .. "Utils" .. path_sep .. "Helpers.lua")

-- Check if modules loaded successfully
if not Constants or not Themes or not DataManager or not ParameterManager or not GUI or not Helpers then
    reaper.ShowMessageBox("无法加载必要的模块。请检查脚本文件是否完整。", "错误", 0)
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
        ctx = reaper.ImGui_CreateContext('Item Parameter Copier'),
        visible = true,
        window_state = DataManager.loadWindowState()
    },
    status_message = "就绪",
    param_checkboxes = {},  -- Store checkbox states
    copied_data = nil,      -- Stored copied data
    selected_params = nil,  -- Selected parameters structure
}

-- Force use Modern theme
Themes.setCurrentTheme("modern")

-- Initialize parameter checkboxes (default: all unchecked)
for _, param in ipairs(Constants.TAKE_PARAMS) do
    state.param_checkboxes["take_" .. param.key] = false
end
for _, param in ipairs(Constants.ITEM_PARAMS) do
    state.param_checkboxes["item_" .. param.key] = false
end
for _, env in ipairs(Constants.ENVELOPES) do
    state.param_checkboxes["env_" .. env.name] = false
end

-- Load copied data if available
local loaded_data, loaded_keys = DataManager.loadCopiedData()
if loaded_data then
    state.copied_data = loaded_data
    -- Restore checkbox states from loaded keys
    if loaded_keys then
        for _, key in ipairs(loaded_keys) do
            state.param_checkboxes[key] = true
        end
        -- Rebuild selected_params structure from keys
        state.selected_params = ParameterManager.getSelectedParams(Constants, state.param_checkboxes)
    end
    state.status_message = "已加载已复制的参数"
end

-- Prepare modules for GUI
local modules = {
    Constants = Constants,
    Themes = Themes,
    DataManager = DataManager,
    ParameterManager = ParameterManager,
    Helpers = Helpers,
}

-- Main loop function
local function main_loop()
    -- Check if close was requested
    if DataManager.isCloseRequested() then
        DataManager.setCloseRequest(false)
        state.gui.visible = false
        return
    end
    
    -- Render GUI
    local should_continue = GUI.render(state, modules)
    
    -- Save window state periodically
    DataManager.saveWindowState(state.gui.window_state)
    
    -- Continue or stop
    if should_continue and state.gui.visible then
        reaper.defer(main_loop)
    else
        -- Cleanup
        DataManager.saveWindowState(state.gui.window_state)
        DataManager.setScriptRunning(false)
        -- ImGui context will be automatically cleaned up when script ends
        -- Only destroy if the function exists (for newer ReaImGui versions)
        if reaper.ImGui_DestroyContext then
            reaper.ImGui_DestroyContext(state.gui.ctx)
        end
    end
end

-- Start main loop
reaper.defer(main_loop)

