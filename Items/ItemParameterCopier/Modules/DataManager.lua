--[[
  Data Manager Module
  Handles all ExtState read/write operations
]]

local DataManager = {}
local SECTION = "ItemParameterCopier"
local SCRIPT_ID = "ItemParameterCopier_Running"
local CLOSE_REQUEST = "ItemParameterCopier_CloseRequest"

-- Window state management
function DataManager.loadWindowState()
    local state = {
        x = nil,
        y = nil,
        width = 380,
        height = 600
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

-- Copy stored data management
-- Store copied data (simplified - store in ExtState with base64 encoding for chunks)
function DataManager.saveCopiedData(copied_data, selected_params)
    if not copied_data then
        return
    end
    
    -- Store which parameters were selected
    local selected_keys = {}
    if selected_params.take then
        for _, param in ipairs(selected_params.take) do
            table.insert(selected_keys, "take_" .. param.key)
        end
    end
    if selected_params.item then
        for _, param in ipairs(selected_params.item) do
            table.insert(selected_keys, "item_" .. param.key)
        end
    end
    if selected_params.envelopes then
        for _, env_name in ipairs(selected_params.envelopes) do
            table.insert(selected_keys, "env_" .. env_name)
        end
    end
    
    reaper.SetExtState(SECTION, "SelectedParams", table.concat(selected_keys, ","), false)
    
    -- Store take parameters
    if copied_data.take then
        local take_params = {}
        for key, value in pairs(copied_data.take) do
            table.insert(take_params, key .. "=" .. tostring(value))
        end
        reaper.SetExtState(SECTION, "CopiedTakeParams", table.concat(take_params, ";"), false)
    end
    
    -- Store item parameters
    if copied_data.item then
        local item_params = {}
        for key, value in pairs(copied_data.item) do
            table.insert(item_params, key .. "=" .. tostring(value))
        end
        reaper.SetExtState(SECTION, "CopiedItemParams", table.concat(item_params, ";"), false)
    end
    
    -- Store envelopes (use chunk storage - may need to split if too large)
    if copied_data.envelopes then
        local env_count = 0
        for env_name, env_chunk in pairs(copied_data.envelopes) do
            env_count = env_count + 1
            -- Store envelope name
            reaper.SetExtState(SECTION, "EnvName_" .. env_count, env_name, false)
            -- Store envelope chunk (may need to split into multiple ExtState entries if too large)
            -- ExtState can hold ~64KB per entry, so we'll split if needed
            local max_len = 60000  -- Safe limit
            if #env_chunk <= max_len then
                reaper.SetExtState(SECTION, "EnvChunk_" .. env_count, env_chunk, false)
            else
                -- Split into chunks
                local parts = math.ceil(#env_chunk / max_len)
                for part = 1, parts do
                    local start_idx = (part - 1) * max_len + 1
                    local end_idx = math.min(part * max_len, #env_chunk)
                    local chunk_part = env_chunk:sub(start_idx, end_idx)
                    reaper.SetExtState(SECTION, "EnvChunk_" .. env_count .. "_" .. part, chunk_part, false)
                end
                reaper.SetExtState(SECTION, "EnvChunk_" .. env_count .. "_Parts", tostring(parts), false)
            end
        end
        reaper.SetExtState(SECTION, "EnvCount", tostring(env_count), false)
    else
        reaper.SetExtState(SECTION, "EnvCount", "0", false)
    end
    
    -- Mark that we have copied data
    reaper.SetExtState(SECTION, "HasCopiedData", "1", false)
end

-- Load copied data
function DataManager.loadCopiedData()
    if reaper.GetExtState(SECTION, "HasCopiedData") ~= "1" then
        return nil, nil
    end
    
    local copied_data = {
        take = {},
        item = {},
        envelopes = {}
    }
    
    -- Load selected params
    local selected_params_str = reaper.GetExtState(SECTION, "SelectedParams")
    local selected_keys = {}
    if selected_params_str ~= "" then
        for key in selected_params_str:gmatch("[^,]+") do
            table.insert(selected_keys, key)
        end
    end
    
    -- Load take parameters
    local take_params_str = reaper.GetExtState(SECTION, "CopiedTakeParams")
    if take_params_str ~= "" then
        for param_str in take_params_str:gmatch("[^;]+") do
            local key, value = param_str:match("([^=]+)=(.+)")
            if key and value then
                local num_value = tonumber(value)
                if num_value then
                    copied_data.take[key] = num_value
                end
            end
        end
    end
    
    -- Load item parameters
    local item_params_str = reaper.GetExtState(SECTION, "CopiedItemParams")
    if item_params_str ~= "" then
        for param_str in item_params_str:gmatch("[^;]+") do
            local key, value = param_str:match("([^=]+)=(.+)")
            if key and value then
                local num_value = tonumber(value)
                if num_value then
                    copied_data.item[key] = num_value
                end
            end
        end
    end
    
    -- Load envelopes
    local env_count = tonumber(reaper.GetExtState(SECTION, "EnvCount")) or 0
    for i = 1, env_count do
        local env_name = reaper.GetExtState(SECTION, "EnvName_" .. i)
        if env_name ~= "" then
            -- Check if chunk was split
            local parts = tonumber(reaper.GetExtState(SECTION, "EnvChunk_" .. i .. "_Parts"))
            if parts and parts > 1 then
                -- Reconstruct from parts
                local chunks = {}
                for part = 1, parts do
                    local chunk_part = reaper.GetExtState(SECTION, "EnvChunk_" .. i .. "_" .. part)
                    table.insert(chunks, chunk_part)
                end
                copied_data.envelopes[env_name] = table.concat(chunks, "")
            else
                -- Single chunk
                local env_chunk = reaper.GetExtState(SECTION, "EnvChunk_" .. i)
                if env_chunk ~= "" then
                    copied_data.envelopes[env_name] = env_chunk
                end
            end
        end
    end
    
    -- Reconstruct selected_params structure from keys
    local selected_params = {
        take = {},
        item = {},
        envelopes = {}
    }
    
    -- This will be populated by GUI based on stored keys
    -- For now, we'll return the keys separately
    return copied_data, selected_keys
end

-- Clear copied data
function DataManager.clearCopiedData()
    reaper.DeleteExtState(SECTION, "HasCopiedData", false)
    reaper.DeleteExtState(SECTION, "SelectedParams", false)
    reaper.DeleteExtState(SECTION, "CopiedTakeParams", false)
    reaper.DeleteExtState(SECTION, "CopiedItemParams", false)
    
    local env_count = tonumber(reaper.GetExtState(SECTION, "EnvCount")) or 0
    for i = 1, env_count do
        reaper.DeleteExtState(SECTION, "EnvName_" .. i, false)
        
        -- Clear chunk parts
        local parts = tonumber(reaper.GetExtState(SECTION, "EnvChunk_" .. i .. "_Parts"))
        if parts and parts > 1 then
            for part = 1, parts do
                reaper.DeleteExtState(SECTION, "EnvChunk_" .. i .. "_" .. part, false)
            end
        end
        reaper.DeleteExtState(SECTION, "EnvChunk_" .. i .. "_Parts", false)
        reaper.DeleteExtState(SECTION, "EnvChunk_" .. i, false)
    end
    reaper.DeleteExtState(SECTION, "EnvCount", false)
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

