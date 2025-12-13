--[[
  Item Function: Jump to Next Item
  Description: 跳转到选中轨道上的下一个媒体项
  - 将编辑光标移动到下一个媒体项的起始位置
  - 如果光标在item内，会跳过当前item，跳转到下一个
  - 自动滚动视图以显示目标位置
]]

local proj = 0

-- Execute function
local function execute()
    -- 1. 获取当前选中的轨道
    local selected_track = reaper.GetSelectedTrack(proj, 0) -- 获取第一个选中的轨道
    if not selected_track then
        return false, "Error: No track selected"
    end

    -- 2. 获取当前编辑光标位置
    local current_cursor_pos = reaper.GetCursorPosition()

    -- 3. 获取选中轨道上的所有媒体素材
    local num_items = reaper.CountTrackMediaItems(selected_track)
    if num_items == 0 then
        return false, "Error: No items on selected track"
    end

    local next_item = nil
    local next_item_pos = -1 

    -- 4. 查找光标之后的第一个 item
    for i = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(selected_track, i)
        if item then
            local item_start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end_pos = item_start_pos + item_length

            -- 如果光标在当前item内，跳过这个item，找下一个
            if item_start_pos <= current_cursor_pos and item_end_pos > current_cursor_pos then
                -- 光标在当前item内，跳过这个item
            elseif item_start_pos > current_cursor_pos then
                -- 找到光标后的item
                if next_item == nil or item_start_pos < next_item_pos then
                    next_item = item
                    next_item_pos = item_start_pos
                end
            end
        end
    end
    
    -- 如果上面的逻辑找不到，尝试找严格在光标后的第一个item
    if not next_item then
        for i = 0, num_items - 1 do
            local item = reaper.GetTrackMediaItem(selected_track, i)
            if item then
                local item_start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                if item_start_pos > current_cursor_pos + 0.00001 then -- 确保是严格在之后
                    if next_item == nil or item_start_pos < next_item_pos then
                        next_item = item
                        next_item_pos = item_start_pos
                    end
                end
            end
        end
    end

    -- 5. 移动光标
    if next_item then
        reaper.SetEditCurPos(next_item_pos, true, true) -- 移动光标并滚动视图
        return true, "Jumped to next item"
    else
        return false, "No next item found"
    end
end

-- Return module
return {
    name = "Jump to Next",
    description = "Jump to next item on selected track",
    execute = execute,
    buttonColor = {0x2196F3FF, 0x42A5F5FF, 0x1976D2FF}  -- Blue
}

