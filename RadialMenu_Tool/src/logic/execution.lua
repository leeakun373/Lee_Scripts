-- @description RadialMenu Tool - Execution Engine (Final Fix)
-- @author Lee

local M = {}

local function log(msg)
    -- 静默模式：不输出到控制台
    -- reaper.ShowConsoleMsg("[Exec] " .. tostring(msg) .. "\n")
end

-- 添加 FX 到 Track
function M.add_fx_to_track(track, fx_name, show_window)
    log("Adding FX to Track: " .. tostring(fx_name))
    if not track then log("  -> Error: Track is nil"); return false end
    
    local idx = reaper.TrackFX_AddByName(track, fx_name, false, -1)
    if idx >= 0 then
        if show_window then reaper.TrackFX_Show(track, idx, 3) end
        log("  -> Success (Index: " .. idx .. ")")
        return true
    else
        log("  -> Failed to add FX (TrackFX_AddByName returned -1)")
        return false
    end
end

-- 添加 FX 到 Item (Take FX)
function M.add_fx_to_item(item, fx_name, show_window)
    log("Adding FX to Item: " .. tostring(fx_name))
    if not item then log("  -> Error: Item is nil"); return false end
    
    local take = reaper.GetActiveTake(item)
    if not take then log("  -> No active take"); return false end
    
    local idx = reaper.TakeFX_AddByName(take, fx_name, -1)
    if idx >= 0 then
        if show_window then reaper.TakeFX_Show(take, idx, 3) end
        log("  -> Success")
        return true
    else
        log("  -> Failed")
        return false
    end
end

-- 添加 Chain 到 Track
function M.add_chain_to_track(track, chain_path, show_window)
    -- Reaper TrackFX_AddByName 可以直接加载 RfxChain 文件
    return M.add_fx_to_track(track, chain_path, show_window)
end

-- 添加 Chain 到 Item
function M.add_chain_to_item(item, chain_path, show_window)
    -- Reaper TakeFX_AddByName 也可以直接加载 RfxChain 文件
    return M.add_fx_to_item(item, chain_path, show_window)
end

-- 智能上下文检测 (用于点击执行)
function M.detect_context()
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then return "item", item end
    local track = reaper.GetSelectedTrack(0, 0)
    if track then return "track", track end
    return nil, nil
end

-- 触发逻辑 (点击)
function M.trigger_slot(slot)
    if not slot then return end
    log("Triggering Slot: " .. tostring(slot.name))
    
    -- 1. Action
    if slot.type == "action" then
        local cmd_id = (slot.data and slot.data.command_id) or slot.command_id
        if cmd_id then
            if type(cmd_id) == "string" then
                local int_id = reaper.NamedCommandLookup(cmd_id)
                if int_id and int_id > 0 then 
                    reaper.Main_OnCommand(int_id, 0)
                    log("  -> Action executed (Named: " .. cmd_id .. " -> " .. int_id .. ")")
                else
                    log("  -> Error: Named command not found: " .. cmd_id)
                end
            else
                local cmd_num = tonumber(cmd_id)
                if cmd_num and cmd_num > 0 then
                    reaper.Main_OnCommand(cmd_num, 0)
                    log("  -> Action executed (ID: " .. cmd_num .. ")")
                else
                    log("  -> Error: Invalid command_id: " .. tostring(cmd_id))
                end
            end
        else
            log("  -> Error: No Command ID found")
        end
        return
    end
    
    -- 2. FX / Chain
    local fx_name = nil
    if slot.type == "fx" then fx_name = (slot.data and slot.data.fx_name) or slot.fx_name end
    if slot.type == "chain" then fx_name = (slot.data and slot.data.path) or slot.path end
    
    if fx_name then
        local context_type, context_obj = M.detect_context()
        log("  -> Executing FX/Chain: " .. fx_name .. " (Context: " .. tostring(context_type) .. ")")
        
        if context_type == "item" then
            M.add_fx_to_item(context_obj, fx_name, true)
        elseif context_type == "track" then
            M.add_fx_to_track(context_obj, fx_name, true)
        else
            -- 没选中任何东西，新建轨道
            log("  -> No context, creating new track")
            reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
            local tr = reaper.GetTrack(0, reaper.CountTracks(0)-1)
            if tr then
                M.add_fx_to_track(tr, fx_name, true)
            else
                log("  -> Error: Failed to create new track")
            end
        end
    else
        if slot.type == "fx" then
            log("  -> Error: FX slot missing fx_name")
        elseif slot.type == "chain" then
            log("  -> Error: Chain slot missing path")
        end
    end
    
    -- 3. Template
    if slot.type == "template" then
        local path = (slot.data and slot.data.path) or slot.path
        if path then 
            log("  -> Opening template: template:" .. path)
            reaper.Main_openProject("template:" .. path) 
        else
            log("  -> Error: Template slot missing path")
        end
    end
end

-- [CORE FIX] 拖拽逻辑 (参考 Pie3000：优先检测 Item)
function M.handle_drop(slot, screen_x, screen_y)
    log("Drop Event at: " .. screen_x .. ", " .. screen_y)
    if not slot then 
        log("  -> Slot is nil")
        return 
    end
    
    log("  -> Slot Type: " .. tostring(slot.type) .. ", Name: " .. tostring(slot.name))
    
    local fx_name = nil
    if slot.type == "fx" then fx_name = (slot.data and slot.data.fx_name) or slot.fx_name end
    if slot.type == "chain" then fx_name = (slot.data and slot.data.path) or slot.path end
    
    if fx_name then
        log("  -> FX/Chain Name: " .. tostring(fx_name))
        
        -- 1. 优先检测 Item (GetItemFromPoint 是最准确的)
        local item, take = reaper.GetItemFromPoint(screen_x, screen_y, true)
        
        if item then
            log("  -> Dropped on Item!")
            if slot.type == "chain" then
                M.add_chain_to_item(item, fx_name, true)
            else
                M.add_fx_to_item(item, fx_name, true)
            end
            return
        end
        
        -- 2. 如果不是 Item，检测 Track
        local track, info = reaper.GetTrackFromPoint(screen_x, screen_y)
        
        if track then
            log("  -> Dropped on Track (Info: " .. tostring(info) .. ")")
            if slot.type == "chain" then
                M.add_chain_to_track(track, fx_name, true)
            else
                M.add_fx_to_track(track, fx_name, true)
            end
            return
        end
        
        -- 3. 如果都不是，新建轨道
        log("  -> Dropped on empty space, creating new track")
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local tr = reaper.GetTrack(0, reaper.CountTracks(0)-1)
        if tr then
            if slot.type == "chain" then
                M.add_chain_to_track(tr, fx_name, true)
            else
                M.add_fx_to_track(tr, fx_name, true)
            end
        else
            log("  -> Error: Failed to create new track")
        end
    end
    
    -- Template 处理
    if slot.type == "template" then
        local path = (slot.data and slot.data.path) or slot.path
        if path then 
            log("  -> Opening template: template:" .. path)
            reaper.Main_openProject("template:" .. path) 
        else
            log("  -> Error: Template slot missing path")
        end
    end
end

return M
