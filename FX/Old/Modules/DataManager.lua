--[[
  Data Manager Module
  Handles all ExtState read/write operations and script state management
]]

local DataManager = {}
local r = reaper

-- Get constants from Constants module
local function getConstants()
    local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
    local path_sep = package.config:sub(1,1) == "/" and "/" or "\\"
    local Constants = loadfile(script_path .. ".." .. path_sep .. "Config" .. path_sep .. "Constants.lua")()
    return Constants
end

local Constants = getConstants()
local SECTION = Constants.EXT_STATE_SECTION
local SCRIPT_ID = Constants.SCRIPT_ID
local CLOSE_REQUEST = Constants.CLOSE_REQUEST

-- Check if script is already running
function DataManager.isScriptRunning()
    return r.GetExtState(SECTION, SCRIPT_ID) == "1"
end

-- Set script running state
function DataManager.setScriptRunning(running)
    r.SetExtState(SECTION, SCRIPT_ID, running and "1" or "0", false)
end

-- Check if close was requested
function DataManager.isCloseRequested()
    return r.GetExtState(SECTION, CLOSE_REQUEST) == "1"
end

-- Set close request
function DataManager.setCloseRequest(request)
    r.SetExtState(SECTION, CLOSE_REQUEST, request and "1" or "0", false)
end

-- Window state management
function DataManager.loadWindowState()
    local state = {
        x = nil,
        y = nil,
        width = Constants.DEFAULT_WIDTH,
        height = Constants.DEFAULT_HEIGHT
    }
    
    local saved_x = r.GetExtState(SECTION, "WindowX")
    local saved_y = r.GetExtState(SECTION, "WindowY")
    local saved_width = r.GetExtState(SECTION, "WindowWidth")
    local saved_height = r.GetExtState(SECTION, "WindowHeight")
    
    if saved_x ~= "" and saved_y ~= "" then
        state.x = tonumber(saved_x)
        state.y = tonumber(saved_y)
    end
    
    if saved_width ~= "" and saved_height ~= "" then
        local w = tonumber(saved_width)
        local h = tonumber(saved_height)
        if w and h and w > 0 and h > 0 then
            state.width = w
            state.height = h
        end
    end
    
    return state
end

function DataManager.saveWindowState(state)
    if state.x and state.y then
        r.SetExtState(SECTION, "WindowX", tostring(state.x), true)
        r.SetExtState(SECTION, "WindowY", tostring(state.y), true)
    end
    r.SetExtState(SECTION, "WindowWidth", tostring(state.width), true)
    r.SetExtState(SECTION, "WindowHeight", tostring(state.height), true)
end

-- Layout management
function DataManager.loadLayout()
    local layout = {
        active = {},
        stash = {}
    }
    
    local active_count = tonumber(r.GetExtState(SECTION, "ActiveFunctionCount")) or 0
    for i = 1, active_count do
        local func_id = r.GetExtState(SECTION, "ActiveFunction_" .. i)
        if func_id and func_id ~= "" then
            table.insert(layout.active, func_id)
        end
    end
    
    local stash_count = tonumber(r.GetExtState(SECTION, "StashFunctionCount")) or 0
    for i = 1, stash_count do
        local func_id = r.GetExtState(SECTION, "StashFunction_" .. i)
        if func_id and func_id ~= "" then
            table.insert(layout.stash, func_id)
        end
    end
    
    return layout
end

function DataManager.saveLayout(layout)
    r.SetExtState(SECTION, "ActiveFunctionCount", tostring(#layout.active), true)
    for i, func_id in ipairs(layout.active) do
        r.SetExtState(SECTION, "ActiveFunction_" .. i, func_id, true)
    end
    
    r.SetExtState(SECTION, "StashFunctionCount", tostring(#layout.stash), true)
    for i, func_id in ipairs(layout.stash) do
        r.SetExtState(SECTION, "StashFunction_" .. i, func_id, true)
    end
end

-- Layout presets management
function DataManager.loadLayoutPresets()
    local layout_presets = {}
    local preset_count = tonumber(r.GetExtState(SECTION, "LayoutPresetCount")) or 0
    for i = 1, preset_count do
        local name = r.GetExtState(SECTION, "LayoutPreset_" .. i .. "_Name")
        if name and name ~= "" then
            local active_count = tonumber(r.GetExtState(SECTION, "LayoutPreset_" .. i .. "_ActiveCount")) or 0
            local stash_count = tonumber(r.GetExtState(SECTION, "LayoutPreset_" .. i .. "_StashCount")) or 0
            local active = {}
            local stash = {}
            for j = 1, active_count do
                local func_id = r.GetExtState(SECTION, "LayoutPreset_" .. i .. "_Active_" .. j)
                if func_id and func_id ~= "" then
                    table.insert(active, func_id)
                end
            end
            for j = 1, stash_count do
                local func_id = r.GetExtState(SECTION, "LayoutPreset_" .. i .. "_Stash_" .. j)
                if func_id and func_id ~= "" then
                    table.insert(stash, func_id)
                end
            end
            layout_presets[name] = {active = active, stash = stash}
        end
    end
    return layout_presets
end

function DataManager.saveLayoutPresets(layout_presets)
    local preset_names = {}
    for name, _ in pairs(layout_presets) do
        table.insert(preset_names, name)
    end
    table.sort(preset_names)
    
    r.SetExtState(SECTION, "LayoutPresetCount", tostring(#preset_names), true)
    for i, name in ipairs(preset_names) do
        local preset = layout_presets[name]
        r.SetExtState(SECTION, "LayoutPreset_" .. i .. "_Name", name, true)
        r.SetExtState(SECTION, "LayoutPreset_" .. i .. "_ActiveCount", tostring(#preset.active), true)
        r.SetExtState(SECTION, "LayoutPreset_" .. i .. "_StashCount", tostring(#preset.stash), true)
        for j, func_id in ipairs(preset.active) do
            r.SetExtState(SECTION, "LayoutPreset_" .. i .. "_Active_" .. j, func_id, true)
        end
        for j, func_id in ipairs(preset.stash) do
            r.SetExtState(SECTION, "LayoutPreset_" .. i .. "_Stash_" .. j, func_id, true)
        end
    end
end

-- Custom actions management
function DataManager.loadCustomActions()
    local custom_actions = {}
    local count = tonumber(r.GetExtState(SECTION, "CustomActionCount")) or 0
    for i = 1, count do
        local name = r.GetExtState(SECTION, "CustomAction_" .. i .. "_Name")
        local action_id = r.GetExtState(SECTION, "CustomAction_" .. i .. "_ID")
        local description = r.GetExtState(SECTION, "CustomAction_" .. i .. "_Description")
        if name ~= "" and action_id ~= "" then
            table.insert(custom_actions, {
                name = name,
                action_id = action_id,
                description = description or ""
            })
        end
    end
    return custom_actions
end

function DataManager.saveCustomActions(custom_actions)
    r.SetExtState(SECTION, "CustomActionCount", tostring(#custom_actions), true)
    for i, action in ipairs(custom_actions) do
        r.SetExtState(SECTION, "CustomAction_" .. i .. "_Name", action.name, true)
        r.SetExtState(SECTION, "CustomAction_" .. i .. "_ID", action.action_id, true)
        r.SetExtState(SECTION, "CustomAction_" .. i .. "_Description", action.description or "", true)
    end
end

-- FX Presets management
function DataManager.loadFXPresets()
    local fx_presets = {}
    local preset_count = tonumber(r.GetExtState(SECTION, "FXPresetCount")) or 0
    for i = 1, preset_count do
        local name = r.GetExtState(SECTION, "FXPreset_" .. i .. "_Name")
        if name and name ~= "" then
            local fx_count = tonumber(r.GetExtState(SECTION, "FXPreset_" .. i .. "_FXCount")) or 0
            local fx_list = {}
            for j = 1, fx_count do
                local fx_name = r.GetExtState(SECTION, "FXPreset_" .. i .. "_FX_" .. j .. "_Name")
                local fx_guid = r.GetExtState(SECTION, "FXPreset_" .. i .. "_FX_" .. j .. "_GUID")
                local display_name = r.GetExtState(SECTION, "FXPreset_" .. i .. "_FX_" .. j .. "_DisplayName")
                local position = tonumber(r.GetExtState(SECTION, "FXPreset_" .. i .. "_FX_" .. j .. "_Position")) or j
                if fx_name and fx_name ~= "" then
                    table.insert(fx_list, {
                        fx_name = fx_name,
                        fx_guid = fx_guid ~= "" and fx_guid or nil,
                        display_name = display_name ~= "" and display_name or fx_name,
                        position = position
                    })
                end
            end
            local buttons_per_row = tonumber(r.GetExtState(SECTION, "FXPreset_" .. i .. "_ButtonsPerRow")) or 2
            fx_presets[name] = {
                fx_list = fx_list,
                buttons_per_row = buttons_per_row
            }
        end
    end
    return fx_presets
end

function DataManager.saveFXPresets(fx_presets)
    local preset_names = {}
    for name, _ in pairs(fx_presets) do
        table.insert(preset_names, name)
    end
    table.sort(preset_names)
    
    r.SetExtState(SECTION, "FXPresetCount", tostring(#preset_names), true)
    for i, name in ipairs(preset_names) do
        local preset = fx_presets[name]
        r.SetExtState(SECTION, "FXPreset_" .. i .. "_Name", name, true)
        r.SetExtState(SECTION, "FXPreset_" .. i .. "_FXCount", tostring(#preset.fx_list), true)
        r.SetExtState(SECTION, "FXPreset_" .. i .. "_ButtonsPerRow", tostring(preset.buttons_per_row), true)
        for j, fx_info in ipairs(preset.fx_list) do
            r.SetExtState(SECTION, "FXPreset_" .. i .. "_FX_" .. j .. "_Name", fx_info.fx_name, true)
            r.SetExtState(SECTION, "FXPreset_" .. i .. "_FX_" .. j .. "_GUID", fx_info.fx_guid or "", true)
            r.SetExtState(SECTION, "FXPreset_" .. i .. "_FX_" .. j .. "_DisplayName", fx_info.display_name or fx_info.fx_name, true)
            r.SetExtState(SECTION, "FXPreset_" .. i .. "_FX_" .. j .. "_Position", tostring(fx_info.position or j), true)
        end
    end
end

-- FX Buttons management
function DataManager.loadFXButtons()
    local fx_buttons = {}
    local count = tonumber(r.GetExtState(SECTION, "FXButtonCount")) or 0
    for i = 1, count do
        local fx_name = r.GetExtState(SECTION, "FXButton_" .. i .. "_Name")
        local fx_guid = r.GetExtState(SECTION, "FXButton_" .. i .. "_GUID")
        local display_name = r.GetExtState(SECTION, "FXButton_" .. i .. "_DisplayName")
        if fx_name and fx_name ~= "" then
            table.insert(fx_buttons, {
                fx_name = fx_name,
                fx_guid = fx_guid ~= "" and fx_guid or nil,
                display_name = display_name ~= "" and display_name or fx_name
            })
        end
    end
    return fx_buttons
end

function DataManager.saveFXButtons(fx_buttons)
    r.SetExtState(SECTION, "FXButtonCount", tostring(#fx_buttons), true)
    for i, fx_info in ipairs(fx_buttons) do
        r.SetExtState(SECTION, "FXButton_" .. i .. "_Name", fx_info.fx_name, true)
        r.SetExtState(SECTION, "FXButton_" .. i .. "_GUID", fx_info.fx_guid or "", true)
        r.SetExtState(SECTION, "FXButton_" .. i .. "_DisplayName", fx_info.display_name or fx_info.fx_name, true)
    end
end

return DataManager

