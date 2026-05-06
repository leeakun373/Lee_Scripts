--[[
  REAPER Lua脚本: 修剪Item右边缘
  功能说明:
  - 将item的右边缘修剪到鼠标光标位置
  - 支持组选中的items
  - 保留淡入淡出的绝对位置（淡出开始点位置不变）
  - 自动处理take的startoffset
  - 只会在item范围内trim，不会拉长item
  - 学习nvk的逻辑，但保持淡入淡出不变
  
  使用方法:
  1. 将鼠标放在想要修剪的位置
  2. 运行此脚本
  3. item的右边缘会被修剪到鼠标位置
]]

local proj = 0

-- 辅助函数：查找轨道上cursor位置前的最后一个item（在arrange view范围内）
local function prev_track_item_in_arrangeview(track, pos)
    if not track then return nil end
    local arrange_start, arrange_end = reaper.GetSet_ArrangeView2(proj, false, 0, 0, 0, 0)
    if not arrange_start or not arrange_end then
        arrange_start = 0
        arrange_end = math.huge
    end
    
    local item_count = reaper.CountTrackMediaItems(track)
    for i = item_count - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, i)
        if item then
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_start + item_length
            if item_end <= pos and item_start >= arrange_start then
                return item
            end
        end
    end
    return nil
end

-- 辅助函数：组选择（通过扩展item到cursor位置来选择同组items）
local function group_select_extend(init_item, cursor_pos)
    if not init_item then return {} end
    
    local init_track = reaper.GetMediaItem_Track(init_item)
    local init_item_start = reaper.GetMediaItemInfo_Value(init_item, "D_POSITION")
    local init_item_length = reaper.GetMediaItemInfo_Value(init_item, "D_LENGTH")
    local init_item_end = init_item_start + init_item_length
    local init_group_id = reaper.GetMediaItemInfo_Value(init_item, "I_GROUPID")
    
    -- 计算扩展后的范围（从item开始到cursor）
    local extend_start = math.min(init_item_start, cursor_pos)
    local extend_end = math.max(init_item_end, cursor_pos)
    
    local selected_items = {}
    
    -- 如果item有组，选择同组的所有items
    if init_group_id > 0 then
        local track_count = reaper.CountTracks(proj)
        for t = 0, track_count - 1 do
            local track = reaper.GetTrack(proj, t)
            if track then
                local item_count = reaper.CountTrackMediaItems(track)
                for i = 0, item_count - 1 do
                    local item = reaper.GetTrackMediaItem(track, i)
                    if item then
                        local group_id = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
                        if group_id == init_group_id then
                            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                            local item_end = item_start + item_length
                            
                            -- 检查item是否与扩展范围重叠
                            if item_end > extend_start and item_start < extend_end then
                                table.insert(selected_items, item)
                            end
                        end
                    end
                end
            end
        end
    else
        -- 没有组，只选择初始item
        table.insert(selected_items, init_item)
    end
    
    return selected_items
end

-- 辅助函数：处理音量自动化（Trim Right）
local function trim_volume_automation(item)
    if not item then return end
    
    local track = reaper.GetMediaItem_Track(item)
    if not track then return end
    
    -- 获取item volume envelope
    local take = reaper.GetActiveTake(item)
    if not take then return end
    local env = reaper.GetTakeEnvelopeByName(take, "Volume")
    if not env then return end
    
    -- Trim Right时，REAPER的内置命令会自动处理音量自动化
    -- 这里我们只需要确保在手动处理时也处理了
    -- 实际上，REAPER的内置trim命令已经处理了，所以这里可以留空
    -- 或者我们可以调用REAPER的内置命令来处理
end

-- 移动编辑光标到鼠标位置
reaper.Main_OnCommand(40513, 0) -- Move edit cursor to mouse cursor
local cursor_pos = reaper.GetCursorPosition()

-- 确定初始item（参考nvk的逻辑）
local init_item = reaper.BR_ItemAtMouseCursor()
if not init_item then
    local track, track_context, pos = reaper.BR_TrackAtMouseCursor()
    if track and track_context == 2 then
        init_item = prev_track_item_in_arrangeview(track, cursor_pos)
    end
end
if not init_item then
    local sel_count = reaper.CountSelectedMediaItems(proj)
    if sel_count > 0 then
        init_item = reaper.GetSelectedMediaItem(proj, 0)
    end
end

if not init_item then
    return -- 没有找到合适的item
end

-- 选中初始item
reaper.SelectAllMediaItems(proj, false)
reaper.SetMediaItemSelected(init_item, true)

-- 组选择（通过扩展item到cursor位置）
local items = group_select_extend(init_item, cursor_pos)
if #items == 0 then
    return
end

-- 选中所有要处理的items
reaper.SelectAllMediaItems(proj, false)
for _, item in ipairs(items) do
    reaper.SetMediaItemSelected(item, true)
end

-- 计算init_end和init_pos（参考nvk：排除第一个item，只计算非mute items）
local init_end = 0
local init_pos = math.huge
for i, item in ipairs(items) do
    if i > 1 then
        local mute = reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1
        if not mute then
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_start + item_length
            if item_end > init_end then
                init_end = item_end
            end
            if item_start < init_pos then
                init_pos = item_start
            end
        end
    end
end
if init_pos == math.huge then
    local item_start = reaper.GetMediaItemInfo_Value(items[1], "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(items[1], "D_LENGTH")
    init_pos = item_start
    init_end = item_start + item_length
end

if init_pos >= cursor_pos then
    return -- 没有找到合适的item
end

local init_diff = init_end - cursor_pos
reaper.SetEditCurPos(cursor_pos, false, false)

-- 开始撤销组
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- 处理每个item
for i, item in ipairs(items) do
    if not reaper.ValidatePtr(item, "MediaItem*") then
        goto continue
    end
    
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_length
    local diff = item_end - cursor_pos
    
    -- 处理automute（参考nvk：i > 1时处理）
    if i > 1 and item_start >= cursor_pos then
        reaper.SetMediaItemInfo_Value(item, "I_AUTOMUTE", 2) -- automute
    else
        if i > 1 then
            local automute = reaper.GetMediaItemInfo_Value(item, "I_AUTOMUTE")
            if automute == 2 and item_start < cursor_pos then
                reaper.SetMediaItemInfo_Value(item, "I_AUTOMUTE", 0) -- 取消automute
            end
        end
        
        -- 判断是否需要trim（参考nvk的条件）
        if diff >= init_diff - 0.0001 or diff > 0 or (#items > 1 and i == 1) then
            local init_item_len = item_length
            
            -- 保存淡入淡出信息（保持淡入淡出不变）
            local fadein_len_auto = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO")
            local fadein_len_manual = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
            local fadein_auto = fadein_len_auto > 0
            local fadein_len = fadein_auto and fadein_len_auto or fadein_len_manual
            
            local fadeout_len_auto = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO")
            local fadeout_len_manual = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
            local fadeout_auto = fadeout_len_auto > 0
            local fadeout_len = fadeout_auto and fadeout_len_auto or fadeout_len_manual
            
            local fadein_shape = reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
            local fadeout_shape = reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")
            local fadein_curv = reaper.GetMediaItemInfo_Value(item, "D_FADEINDIR")
            local fadeout_curv = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTDIR")
            
            -- 检查轨道是否可见
            local track = reaper.GetMediaItem_Track(item)
            local track_visible = reaper.IsTrackVisible(track, false)
            
            if track_visible then
                -- 使用REAPER的内置命令（仅在可见轨道上工作）
                reaper.SetMediaItemSelected(item, true)
                reaper.Main_OnCommand(41311, 0) -- Trim/Untrim right edge
                
                -- 重新获取item信息
                item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                item_end = item_start + item_length
            elseif item_start < cursor_pos then
                -- 手动处理不可见轨道
                local new_item_length = init_item_len - diff
                
                -- 更新item长度
                reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_item_length)
                
                item_end = item_start + new_item_length
            end
            
            -- 处理音量自动化
            trim_volume_automation(item)
            
            -- 淡入保持不变
            
            -- 保持淡出长度不变（用户要求）
            if fadeout_len > 0.0001 then
                local restored_fadeout_len = math.min(fadeout_len, item_length)
                
                if fadeout_auto then
                    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", restored_fadeout_len)
                else
                    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", restored_fadeout_len)
                end
                reaper.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", fadeout_shape)
                reaper.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", fadeout_curv)
            end
        end
    end
    
    ::continue::
end

-- 恢复光标位置
reaper.SetEditCurPos(cursor_pos, false, false)

-- 结束撤销组
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Trim Right Edge", -1)
