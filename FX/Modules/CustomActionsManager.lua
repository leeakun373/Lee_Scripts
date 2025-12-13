--[[
  Custom Actions Manager Module
  Handles custom REAPER actions management
]]

local CustomActionsManager = {}
local r = reaper

-- Validate and convert action ID
function CustomActionsManager.validateActionID(action_id_str)
    -- Try as number first
    local action_id = tonumber(action_id_str)
    if action_id then
        return action_id
    end
    
    -- Try as named command
    action_id = r.NamedCommandLookup(action_id_str)
    if action_id and action_id > 0 then
        return action_id
    end
    
    return nil
end

-- Add custom action
function CustomActionsManager.addAction(custom_actions, action_data)
    if action_data.name ~= "" and action_data.action_id ~= "" then
        local action_id = CustomActionsManager.validateActionID(action_data.action_id)
        if action_id then
            table.insert(custom_actions, {
                name = action_data.name,
                action_id = tostring(action_id),
                description = action_data.description or ""
            })
            return true, "Added custom action"
        else
            return false, "Error: Invalid Action ID"
        end
    else
        return false, "Error: Name and Action ID required"
    end
end

-- Update custom action
function CustomActionsManager.updateAction(custom_actions, index, action_data)
    if index > 0 and index <= #custom_actions then
        if action_data.name ~= "" and action_data.action_id ~= "" then
            local action_id = CustomActionsManager.validateActionID(action_data.action_id)
            if action_id then
                custom_actions[index].name = action_data.name
                custom_actions[index].action_id = tostring(action_id)
                custom_actions[index].description = action_data.description or ""
                return true, "Updated custom action"
            else
                return false, "Error: Invalid Action ID"
            end
        else
            return false, "Error: Name and Action ID required"
        end
    end
    return false, "Error: Invalid index"
end

-- Delete custom action
function CustomActionsManager.deleteAction(custom_actions, index)
    if index > 0 and index <= #custom_actions then
        table.remove(custom_actions, index)
        return true, "Deleted custom action"
    end
    return false, "Error: Invalid index"
end

-- Remove custom action from layout
function CustomActionsManager.removeFromLayout(layout, action_name)
    local func_id = "custom_" .. action_name
    -- Remove from active
    for i, active_id in ipairs(layout.active) do
        if active_id == func_id then
            table.remove(layout.active, i)
            break
        end
    end
    
    -- Remove from stash
    for i, stash_id in ipairs(layout.stash) do
        if stash_id == func_id then
            table.remove(layout.stash, i)
            break
        end
    end
end

-- Execute custom action
function CustomActionsManager.executeAction(action)
    if action and action.action_id then
        local action_id = tonumber(action.action_id)
        if action_id then
            r.Main_OnCommand(action_id, 0)
            return true, "Executed: " .. action.name
        end
    end
    return false, "Error: Invalid action"
end

return CustomActionsManager

