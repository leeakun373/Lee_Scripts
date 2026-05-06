--[[
  Layout Manager Module
  Handles layout management (active/stash functions, presets)
]]

local LayoutManager = {}

-- Get function ID for built-in functions
local function getBuiltinFunctionID(func_name)
    if func_name then
        return "builtin_" .. func_name
    end
    return nil
end

-- Get function ID for custom actions
local function getCustomActionID(action_name)
    if action_name then
        return "custom_" .. action_name
    end
    return nil
end

-- Initialize layout (first time setup and add new functions)
function LayoutManager.initializeLayout(layout, builtin_functions, custom_actions)
    local was_empty = (#layout.active == 0)
    local added_new = false
    
    -- Add all built-in functions to active (if first time, or if new functions exist)
    for _, func in ipairs(builtin_functions) do
        if func and func.name then
            local func_id = getBuiltinFunctionID(func.name)
            if func_id then
                local already_added = false
                -- Check if in active
                for _, active_id in ipairs(layout.active) do
                    if active_id == func_id then
                        already_added = true
                        break
                    end
                end
                -- Check if in stash
                if not already_added then
                    for _, stash_id in ipairs(layout.stash) do
                        if stash_id == func_id then
                            already_added = true
                            break
                        end
                    end
                end
                -- Add to active if not found anywhere
                if not already_added then
                    table.insert(layout.active, func_id)
                    added_new = true
                end
            end
        end
    end
    
    -- Add custom actions
    for _, action in ipairs(custom_actions) do
        if action and action.name and action.action_id then
            local action_id = tonumber(action.action_id)
            if action_id then
                local func_id = getCustomActionID(action.name)
                local already_added = false
                -- Check if in active
                for _, active_id in ipairs(layout.active) do
                    if active_id == func_id then
                        already_added = true
                        break
                    end
                end
                -- Check if in stash
                if not already_added then
                    for _, stash_id in ipairs(layout.stash) do
                        if stash_id == func_id then
                            already_added = true
                            break
                        end
                    end
                end
                -- Add to active if not found anywhere
                if not already_added then
                    table.insert(layout.active, func_id)
                    added_new = true
                end
            end
        end
    end
    
    -- Return true if layout was empty (first time) or if new functions were added
    return was_empty or added_new
end

-- Apply a layout preset
function LayoutManager.applyLayoutPreset(layout_presets, preset_name)
    if layout_presets[preset_name] then
        local preset = layout_presets[preset_name]
        local new_layout = {
            active = {},
            stash = {}
        }
        for _, func_id in ipairs(preset.active) do
            table.insert(new_layout.active, func_id)
        end
        for _, func_id in ipairs(preset.stash) do
            table.insert(new_layout.stash, func_id)
        end
        return new_layout
    end
    return nil
end

-- Save current layout as preset
function LayoutManager.saveCurrentLayoutAsPreset(layout, layout_presets, preset_name)
    if preset_name and preset_name ~= "" then
        local active_copy = {}
        local stash_copy = {}
        for _, func_id in ipairs(layout.active) do
            table.insert(active_copy, func_id)
        end
        for _, func_id in ipairs(layout.stash) do
            table.insert(stash_copy, func_id)
        end
        layout_presets[preset_name] = {active = active_copy, stash = stash_copy}
        return true
    end
    return false
end

-- Delete a layout preset
function LayoutManager.deleteLayoutPreset(layout_presets, preset_name)
    if layout_presets[preset_name] then
        layout_presets[preset_name] = nil
        return true
    end
    return false
end

-- Move function from active to stash
function LayoutManager.moveToStash(layout, func_id)
    for i, active_id in ipairs(layout.active) do
        if active_id == func_id then
            table.remove(layout.active, i)
            table.insert(layout.stash, func_id)
            return true
        end
    end
    return false
end

-- Move function from stash to active
function LayoutManager.moveToActive(layout, func_id, position)
    -- Remove from stash
    for i, stash_id in ipairs(layout.stash) do
        if stash_id == func_id then
            table.remove(layout.stash, i)
            break
        end
    end
    
    -- Add to active
    local already_added = false
    for _, active_id in ipairs(layout.active) do
        if active_id == func_id then
            already_added = true
            break
        end
    end
    
    if not already_added then
        if position and position > 0 and position <= #layout.active then
            table.insert(layout.active, position, func_id)
        else
            table.insert(layout.active, func_id)
        end
        return true
    end
    return false
end

-- Reorder functions in active list
function LayoutManager.reorderFunctions(layout, src_id, dst_id)
    if src_id == dst_id then
        return false
    end
    
    -- Find indices
    local src_idx = nil
    local dst_idx = nil
    for i, active_id in ipairs(layout.active) do
        if active_id == src_id then
            src_idx = i
        end
        if active_id == dst_id then
            dst_idx = i
        end
        if src_idx and dst_idx then break end
    end
    
    if src_idx and dst_idx and src_idx ~= dst_idx then
        -- Remove source first
        table.remove(layout.active, src_idx)
        -- Adjust destination index
        local adjusted_dst = dst_idx
        if dst_idx > src_idx then
            adjusted_dst = dst_idx - 1
        end
        -- Insert at adjusted position
        table.insert(layout.active, adjusted_dst, src_id)
        return true
    end
    return false
end

-- Clean up invalid function IDs
function LayoutManager.cleanupLayout(layout, getFunctionByID)
    local valid_active = {}
    for _, func_id in ipairs(layout.active) do
        if func_id and func_id ~= "" then
            local func = getFunctionByID(func_id)
            if func and func.name then
                table.insert(valid_active, func_id)
            end
        end
    end
    
    local valid_stash = {}
    for _, func_id in ipairs(layout.stash) do
        if func_id and func_id ~= "" then
            local func = getFunctionByID(func_id)
            if func and func.name then
                table.insert(valid_stash, func_id)
            end
        end
    end
    
    layout.active = valid_active
    layout.stash = valid_stash
end

return LayoutManager

