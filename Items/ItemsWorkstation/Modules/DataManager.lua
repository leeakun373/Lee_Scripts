--[[
  Data Manager Module
  Handles all ExtState read/write operations
]]

local DataManager = {}
local SECTION = "ItemWorkstation"  -- ExtState section name (compatible with original script)
local SCRIPT_ID = "ItemWorkstation_Running"
local CLOSE_REQUEST = "ItemWorkstation_CloseRequest"

-- Window state management
function DataManager.loadWindowState()
    local state = {
        x = nil,
        y = nil,
        width = 500,  -- Default width
        height = 500  -- Default height
    }
    
    local saved_x = reaper.GetExtState(SECTION, "WindowX")
    local saved_y = reaper.GetExtState(SECTION, "WindowY")
    local saved_width = reaper.GetExtState(SECTION, "WindowWidth")
    local saved_height = reaper.GetExtState(SECTION, "WindowHeight")
    
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
        reaper.SetExtState(SECTION, "WindowX", tostring(state.x), true)
        reaper.SetExtState(SECTION, "WindowY", tostring(state.y), true)
    end
    reaper.SetExtState(SECTION, "WindowWidth", tostring(state.width), true)
    reaper.SetExtState(SECTION, "WindowHeight", tostring(state.height), true)
end

-- Layout management
function DataManager.loadLayout()
    local layout = {
        active = {},
        stash = {}
    }
    
    local active_count = tonumber(reaper.GetExtState(SECTION, "ActiveFunctionCount")) or 0
    for i = 1, active_count do
        local func_id = reaper.GetExtState(SECTION, "ActiveFunction_" .. i)
        if func_id and func_id ~= "" then
            table.insert(layout.active, func_id)
        end
    end
    
    local stash_count = tonumber(reaper.GetExtState(SECTION, "StashFunctionCount")) or 0
    for i = 1, stash_count do
        local func_id = reaper.GetExtState(SECTION, "StashFunction_" .. i)
        if func_id and func_id ~= "" then
            table.insert(layout.stash, func_id)
        end
    end
    
    return layout
end

function DataManager.saveLayout(layout)
    reaper.SetExtState(SECTION, "ActiveFunctionCount", tostring(#layout.active), true)
    for i, func_id in ipairs(layout.active) do
        reaper.SetExtState(SECTION, "ActiveFunction_" .. i, func_id, true)
    end
    
    reaper.SetExtState(SECTION, "StashFunctionCount", tostring(#layout.stash), true)
    for i, func_id in ipairs(layout.stash) do
        reaper.SetExtState(SECTION, "StashFunction_" .. i, func_id, true)
    end
end

-- Layout presets management
function DataManager.loadLayoutPresets()
    local layout_presets = {}
    local preset_count = tonumber(reaper.GetExtState(SECTION, "LayoutPresetCount")) or 0
    for i = 1, preset_count do
        local name = reaper.GetExtState(SECTION, "LayoutPreset_" .. i .. "_Name")
        if name and name ~= "" then
            local active_count = tonumber(reaper.GetExtState(SECTION, "LayoutPreset_" .. i .. "_ActiveCount")) or 0
            local stash_count = tonumber(reaper.GetExtState(SECTION, "LayoutPreset_" .. i .. "_StashCount")) or 0
            local active = {}
            local stash = {}
            for j = 1, active_count do
                local func_id = reaper.GetExtState(SECTION, "LayoutPreset_" .. i .. "_Active_" .. j)
                if func_id and func_id ~= "" then
                    table.insert(active, func_id)
                end
            end
            for j = 1, stash_count do
                local func_id = reaper.GetExtState(SECTION, "LayoutPreset_" .. i .. "_Stash_" .. j)
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
    
    reaper.SetExtState(SECTION, "LayoutPresetCount", tostring(#preset_names), true)
    for i, name in ipairs(preset_names) do
        local preset = layout_presets[name]
        reaper.SetExtState(SECTION, "LayoutPreset_" .. i .. "_Name", name, true)
        reaper.SetExtState(SECTION, "LayoutPreset_" .. i .. "_ActiveCount", tostring(#preset.active), true)
        reaper.SetExtState(SECTION, "LayoutPreset_" .. i .. "_StashCount", tostring(#preset.stash), true)
        for j, func_id in ipairs(preset.active) do
            reaper.SetExtState(SECTION, "LayoutPreset_" .. i .. "_Active_" .. j, func_id, true)
        end
        for j, func_id in ipairs(preset.stash) do
            reaper.SetExtState(SECTION, "LayoutPreset_" .. i .. "_Stash_" .. j, func_id, true)
        end
    end
end

-- Custom actions management
function DataManager.loadCustomActions()
    local custom_actions = {}
    local count = tonumber(reaper.GetExtState(SECTION, "CustomActionCount")) or 0
    for i = 1, count do
        local name = reaper.GetExtState(SECTION, "CustomAction_" .. i .. "_Name")
        local action_id = reaper.GetExtState(SECTION, "CustomAction_" .. i .. "_ID")
        local description = reaper.GetExtState(SECTION, "CustomAction_" .. i .. "_Description")
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
    reaper.SetExtState(SECTION, "CustomActionCount", tostring(#custom_actions), true)
    for i, action in ipairs(custom_actions) do
        reaper.SetExtState(SECTION, "CustomAction_" .. i .. "_Name", action.name, true)
        reaper.SetExtState(SECTION, "CustomAction_" .. i .. "_ID", action.action_id, true)
        reaper.SetExtState(SECTION, "CustomAction_" .. i .. "_Description", action.description or "", true)
    end
end

-- Script state management (for toggle functionality)
function DataManager.isScriptRunning()
    return reaper.GetExtState(SECTION, SCRIPT_ID) == "1"
end

function DataManager.setScriptRunning(running)
    reaper.SetExtState(SECTION, SCRIPT_ID, running and "1" or "0", false)
end

function DataManager.isCloseRequested()
    return reaper.GetExtState(SECTION, CLOSE_REQUEST) == "1"
end

function DataManager.setCloseRequest(requested)
    reaper.SetExtState(SECTION, CLOSE_REQUEST, requested and "1" or "0", false)
end

return DataManager

