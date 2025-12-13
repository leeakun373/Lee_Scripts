--[[
  Parameter Manager Module
  Handles copying and pasting item/take parameters
]]

local ParameterManager = {}

-- Copy parameters from item
function ParameterManager.copyItemParameters(item, selected_params)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then
        return nil
    end
    
    local take = reaper.GetActiveTake(item)
    if not take then
        return nil
    end
    
    local data = {
        item = {},
        take = {},
        envelopes = {}
    }
    
    -- Copy Take parameters
    if selected_params.take then
        for _, param in ipairs(selected_params.take) do
            local value = reaper.GetMediaItemTakeInfo_Value(take, param.key)
            data.take[param.key] = value
        end
    end
    
    -- Copy Item parameters
    if selected_params.item then
        for _, param in ipairs(selected_params.item) do
            local value = reaper.GetMediaItemInfo_Value(item, param.key)
            data.item[param.key] = value
        end
    end
    
    -- Copy Take envelopes
    if selected_params.envelopes then
        for _, env_name in ipairs(selected_params.envelopes) do
            local env = reaper.GetTakeEnvelopeByName(take, env_name)
            if env then
                local retval, env_chunk = reaper.GetEnvelopeStateChunk(env, "", true)
                if retval and env_chunk then
                    data.envelopes[env_name] = env_chunk
                end
            end
        end
    end
    
    return data
end

-- Paste parameters to item
function ParameterManager.pasteItemParameters(item, copied_data, selected_params)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then
        return false
    end
    
    if not copied_data then
        return false
    end
    
    if not selected_params then
        return false
    end
    
    local take = reaper.GetActiveTake(item)
    if not take then
        return false
    end
    
    -- Paste Take parameters
    if selected_params.take and #selected_params.take > 0 and copied_data.take then
        for _, param in ipairs(selected_params.take) do
            if copied_data.take[param.key] ~= nil then
                reaper.SetMediaItemTakeInfo_Value(take, param.key, copied_data.take[param.key])
            end
        end
    end
    
    -- Paste Item parameters
    if selected_params.item and #selected_params.item > 0 and copied_data.item then
        for _, param in ipairs(selected_params.item) do
            if copied_data.item[param.key] ~= nil then
                reaper.SetMediaItemInfo_Value(item, param.key, copied_data.item[param.key])
            end
        end
    end
    
    -- Paste Take envelopes
    if selected_params.envelopes and #selected_params.envelopes > 0 and copied_data.envelopes then
        for _, env_name in ipairs(selected_params.envelopes) do
            if copied_data.envelopes[env_name] then
                -- Get or create envelope
                local env = reaper.GetTakeEnvelopeByName(take, env_name)
                
                -- If envelope doesn't exist, create it using SWS actions
                if not env then
                    if env_name == "Volume" then
                        reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENV1"), 0)
                    elseif env_name == "Pan" then
                        reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENV2"), 0)
                    elseif env_name == "Mute" then
                        reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENV3"), 0)
                    elseif env_name == "Pitch" then
                        reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENV10"), 0)
                    end
                    -- Refresh item to ensure envelope is available
                    reaper.UpdateItemInProject(item)
                    -- Re-get take after update (take pointer might have changed)
                    take = reaper.GetActiveTake(item)
                    if take then
                        env = reaper.GetTakeEnvelopeByName(take, env_name)
                    end
                end
                
                -- Paste envelope state chunk
                if env then
                    reaper.SetEnvelopeStateChunk(env, copied_data.envelopes[env_name], true)
                end
            end
        end
    end
    
    -- Update item to ensure all changes are applied and visible
    reaper.UpdateItemInProject(item)
    
    return true
end

-- Convert selected params from checkbox state to structured format
function ParameterManager.getSelectedParams(Constants, param_checkboxes)
    local selected = {
        take = {},
        item = {},
        envelopes = {}
    }
    
    -- Check take parameters
    for _, param in ipairs(Constants.TAKE_PARAMS) do
        if param_checkboxes["take_" .. param.key] then
            table.insert(selected.take, param)
        end
    end
    
    -- Check item parameters
    for _, param in ipairs(Constants.ITEM_PARAMS) do
        if param_checkboxes["item_" .. param.key] then
            table.insert(selected.item, param)
        end
    end
    
    -- Check envelopes
    for _, env in ipairs(Constants.ENVELOPES) do
        if param_checkboxes["env_" .. env.name] then
            table.insert(selected.envelopes, env.name)
        end
    end
    
    return selected
end

-- Serialize copied data for storage (convert to string)
function ParameterManager.serializeCopiedData(copied_data)
    -- Convert tables to JSON-like string
    -- Simple serialization for ExtState storage
    local serialized = {}
    
    -- Serialize take params
    if copied_data.take then
        serialized.take = {}
        for key, value in pairs(copied_data.take) do
            serialized.take[key] = tostring(value)
        end
    end
    
    -- Serialize item params
    if copied_data.item then
        serialized.item = {}
        for key, value in pairs(copied_data.item) do
            serialized.item[key] = tostring(value)
        end
    end
    
    -- Envelopes are already strings (chunks)
    serialized.envelopes = copied_data.envelopes
    
    return serialized
end

-- Deserialize copied data from storage
function ParameterManager.deserializeCopiedData(serialized_data)
    local data = {
        item = {},
        take = {},
        envelopes = {}
    }
    
    -- Deserialize take params
    if serialized_data.take then
        for key, value_str in pairs(serialized_data.take) do
            local value = tonumber(value_str)
            if value then
                data.take[key] = value
            end
        end
    end
    
    -- Deserialize item params
    if serialized_data.item then
        for key, value_str in pairs(serialized_data.item) do
            local value = tonumber(value_str)
            if value then
                data.item[key] = value
            end
        end
    end
    
    -- Envelopes are already strings
    data.envelopes = serialized_data.envelopes or {}
    
    return data
end

return ParameterManager

