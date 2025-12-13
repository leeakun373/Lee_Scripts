-- @description RadialMenu Tool - FX 引擎模块
-- @author Lee
-- @about
--   智能 FX 挂载引擎
--   根据上下文自动判断挂载到 Track 还是 Item

local M = {}

-- ============================================================================
-- Phase 3 - 智能添加 FX
-- ============================================================================

-- 智能添加 FX（自动检测上下文）
function M.smart_add_fx(fx_name)
    if not fx_name or fx_name == "" then
        -- reaper.ShowConsoleMsg("错误: FX 名称为空\n")
        return false, "FX 名称为空"
    end
    
    -- 判断目标
    local target_type, target = M.determine_target()
    
    if target_type == "item" then
        local success, fx_index = M.add_fx_to_item(target, fx_name)
        if success then
            return true, "已添加 FX 到 Item: " .. fx_name
        else
            return false, "添加 FX 到 Item 失败"
        end
        
    elseif target_type == "track" then
        local success, fx_index = M.add_fx_to_track(target, fx_name)
        if success then
            return true, "已添加 FX 到 Track: " .. fx_name
        else
            return false, "添加 FX 到 Track 失败"
        end
        
    else
        local msg = "请先选择 Track 或 Item"
        reaper.ShowMessageBox(msg, "提示", 0)
        return false, msg
    end
end

-- ============================================================================
-- Phase 3 - 判断挂载目标
-- ============================================================================

-- 判断 FX 应该挂载到哪里
-- 优先级：选中的 Item > 选中的 Track > 无
function M.determine_target()
    -- 检查是否有选中的 Item
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count > 0 then
        local item = reaper.GetSelectedMediaItem(0, 0)
        if item then
            -- 检查 Item 是否有有效的 Take
            local take = reaper.GetActiveTake(item)
            if take then
                return "item", item
            end
        end
    end
    
    -- 检查是否有选中的 Track
    local track_count = reaper.CountSelectedTracks(0)
    if track_count > 0 then
        local track = reaper.GetSelectedTrack(0, 0)
        if track then
            return "track", track
        end
    end
    
    return "none", nil
end

-- ============================================================================
-- Phase 3 - 添加 FX 到 Track
-- ============================================================================

-- 添加 FX 到指定轨道
function M.add_fx_to_track(track, fx_name)
    if not track then
        return false, -1
    end
    
    -- 添加 FX
    local fx_index = reaper.TrackFX_AddByName(track, fx_name, false, -1)
    
    if fx_index < 0 then
        -- reaper.ShowConsoleMsg("错误: 找不到 FX: " .. fx_name .. "\n")
        return false, -1
    end
    
    -- 获取轨道名称
    local _, track_name = reaper.GetTrackName(track)
    
    -- reaper.ShowConsoleMsg("✓ 已添加 FX 到轨道 \"" .. track_name .. "\": " .. fx_name .. "\n")
    
    -- 打开 FX 窗口
    reaper.TrackFX_Show(track, fx_index, 3)  -- 3 = 显示浮动窗口
    
    return true, fx_index
end

-- ============================================================================
-- Phase 3 - 添加 FX 到 Item
-- ============================================================================

-- 添加 FX 到指定 Item 的 Take
function M.add_fx_to_item(item, fx_name)
    if not item then
        return false, -1
    end
    
    -- 获取活动 Take
    local take = reaper.GetActiveTake(item)
    if not take then
        -- reaper.ShowConsoleMsg("错误: Item 没有有效的 Take\n")
        return false, -1
    end
    
    -- 添加 FX
    local fx_index = reaper.TakeFX_AddByName(take, fx_name, -1)
    
    if fx_index < 0 then
        -- reaper.ShowConsoleMsg("错误: 找不到 FX: " .. fx_name .. "\n")
        return false, -1
    end
    
    -- 获取 Take 名称
    local take_name = reaper.GetTakeName(take)
    
    -- reaper.ShowConsoleMsg("✓ 已添加 FX 到 Item Take \"" .. take_name .. "\": " .. fx_name .. "\n")
    
    -- 打开 FX 窗口
    reaper.TakeFX_Show(take, fx_index, 3)  -- 3 = 显示浮动窗口
    
    return true, fx_index
end

-- ============================================================================
-- Phase 3 - 辅助函数
-- ============================================================================

-- 检查 FX 是否可用（简单验证）
function M.is_fx_available(fx_name)
    if not fx_name or fx_name == "" then
        return false
    end
    
    -- 简单验证：检查 FX 名称格式
    return true
end

-- 获取目标名称（用于日志）
function M.get_target_name(target_type, target)
    if target_type == "track" then
        local _, track_name = reaper.GetTrackName(target)
        return track_name or "Unknown Track"
    elseif target_type == "item" then
        local take = reaper.GetActiveTake(target)
        if take then
            return reaper.GetTakeName(take) or "Unknown Take"
        end
        return "Unknown Item"
    else
        return "None"
    end
end

return M
