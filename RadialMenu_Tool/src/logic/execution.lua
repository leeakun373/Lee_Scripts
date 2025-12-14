-- @description RadialMenu Tool - Execution Engine (Final Fix)
-- @author Lee

local M = {}

-- [Context Tracking] 从 main_runtime 接收的最后有效 Context
local last_valid_context = -1

function M.set_last_valid_context(ctx)
    last_valid_context = ctx
end

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
-- 返回: context_type, context_objects (table), show_window (bool)
function M.detect_context()
    -- 1. 获取所有选中的 items
    local all_items = {}
    local item_count = reaper.CountSelectedMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local take = reaper.GetActiveTake(item)
            if take then
                table.insert(all_items, item)
            end
        end
    end

    -- 2. 获取所有选中的 tracks
    local selected_tracks = {}
    local track_count = reaper.CountSelectedTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
            table.insert(selected_tracks, track)
        end
    end
    
    -- 3. 如果没有任何选中，返回 nil (将导致新建轨道)
    if #all_items == 0 and #selected_tracks == 0 then
        return nil, nil, false
    end

    -- 4. 只有 Items 被选中
    if #all_items > 0 and #selected_tracks == 0 then
        return "item", all_items, (#all_items == 1)
    end

    -- 5. 只有 Tracks 被选中
    if #selected_tracks > 0 and #all_items == 0 then
        return "track", selected_tracks, (#selected_tracks == 1)
    end

    -- 6. 混合选中 (Items 和 Tracks 都有)
    
    -- 优先使用 last_valid_context (从 main_runtime 持续追踪的值)
    -- 这能准确反映用户打开菜单前最后操作的是 TCP (0) 还是 Arrange View (1)
    if last_valid_context == 0 then
        -- 上一步操作在 Track Panel
        return "track", selected_tracks, (#selected_tracks == 1)
    elseif last_valid_context == 1 then
        -- 上一步操作在 Items
        return "item", all_items, (#all_items == 1)
    end
    
    -- 如果 last_valid_context 也不明确，回退到实时 GetCursorContext
    local cursor_context = reaper.GetCursorContext()
    
    if cursor_context == 0 then
        return "track", selected_tracks, (#selected_tracks == 1)
    elseif cursor_context == 1 then
        return "item", all_items, (#all_items == 1)
    end
    
    -- 7. 焦点完全不明确，使用 LastTouchedTrack 和 Item 分布进行推断
    local last_touched_track = reaper.GetLastTouchedTrack()
    local last_touched_is_selected = false
    
    if last_touched_track then
        for _, track in ipairs(selected_tracks) do
            if track == last_touched_track then
                last_touched_is_selected = true
                break
            end
        end
    end
    
    if last_touched_is_selected then
        -- 检查所有选中的 Item 是否都位于 LastTouchedTrack 上
        local all_items_on_last_track = true
        for _, item in ipairs(all_items) do
            if reaper.GetMediaItem_Track(item) ~= last_touched_track then
                all_items_on_last_track = false
                break
            end
        end
        
        if all_items_on_last_track then
            -- 所有选中 Item 都在 LastTouchedTrack 上
            -- 这种情况通常是：
            -- 1. 用户框选了该轨道上的 Items (导致轨道被 Touch) -> 意图是 Item
            -- 2. 用户先选了 Items，然后点击了该轨道 (意图是 Track?) -> 这种情况较少见，且难以区分
            -- 我们倾向于判定为 Item 操作，因为操作 Item 更具体
            return "item", all_items, (#all_items == 1)
        else
            -- 选中的 Item 分布在其他轨道上，或者 LastTouchedTrack 上根本没有选中 Item
            -- 这说明 LastTouchedTrack 只是被“点击”选中了，而不是因为框选 Item 而被 Touch
            -- 判定为 Track 操作
            return "track", selected_tracks, (#selected_tracks == 1)
        end
    else
        -- LastTouchedTrack 未被选中，或者没有 LastTouchedTrack
        -- 默认优先处理 Item
        return "item", all_items, (#all_items == 1)
    end
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
        local context_type, context_objs, show_window = M.detect_context()
        log("  -> Executing FX/Chain: " .. fx_name .. " (Context: " .. tostring(context_type) .. ", Count: " .. (context_objs and #context_objs or 0) .. ")")
        
        if context_type == "item" then
            -- 批量添加 FX/Chain 到所有选中的 Items
            local success_count = 0
            local total_count = context_objs and #context_objs or 0
            log("  -> Processing " .. total_count .. " item(s)")
            
            if total_count > 0 then
                for i, item in ipairs(context_objs) do
                    -- 只在最后一个 item 上显示 FX 窗口
                    local should_show = show_window and (i == total_count)
                    local success = false
                    if slot.type == "chain" then
                        success = M.add_chain_to_item(item, fx_name, should_show)
                    else
                        success = M.add_fx_to_item(item, fx_name, should_show)
                    end
                    if success then
                        success_count = success_count + 1
                    else
                        log("  -> Failed to add to item " .. i)
                    end
                end
            else
                log("  -> Error: No items to process")
            end
            log("  -> Added " .. (slot.type == "chain" and "Chain" or "FX") .. " to " .. success_count .. " of " .. total_count .. " item(s)")
            
        elseif context_type == "track" then
            -- 批量添加 FX/Chain 到所有选中的 Tracks
            local success_count = 0
            for i, track in ipairs(context_objs) do
                -- 只在最后一个 track 上显示 FX 窗口
                local should_show = show_window and (i == #context_objs)
                local success = false
                if slot.type == "chain" then
                    success = M.add_chain_to_track(track, fx_name, should_show)
                else
                    success = M.add_fx_to_track(track, fx_name, should_show)
                end
                if success then
                    success_count = success_count + 1
                end
            end
            log("  -> Added " .. (slot.type == "chain" and "Chain" or "FX") .. " to " .. success_count .. " track(s)")
            
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
