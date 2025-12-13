--[[
  Item Function: Jump to Previous Item
  Description: 跳转到选中轨道上的上一个媒体项
  - 将编辑光标移动到上一个媒体项的起始位置
  - 查找光标之前最接近的item
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

    local prev_item = nil
    local prev_item_pos = -1 

    -- 4. 查找光标之前的第一个 item (最接近光标且在光标前的)
    for i = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(selected_track, i)
        if item then
            local item_start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            -- 我们要找的是严格在当前光标之前的 item (item的起始位置 < 光标位置)
            -- 并且是这些 item 中最靠右 (起始位置最大) 的一个
            -- 同时，为了避免光标在item开头时重复跳转到自身，我们加一个小的偏移量
            if item_start_pos < current_cursor_pos - 0.00001 then 
                if prev_item == nil or item_start_pos > prev_item_pos then
                    prev_item = item
                    prev_item_pos = item_start_pos
                end
            end
        end
    end

    -- 5. 移动光标
    if prev_item then
        reaper.SetEditCurPos(prev_item_pos, true, true) -- 移动光标并滚动视图
        return true, "Jumped to previous item"
    else
        return false, "No previous item found"
    end
end

-- Return module
return {
    name = "Jump to Previous",
    description = "Jump to previous item on selected track",
    execute = execute,
    buttonColor = {0x9C27B0FF, 0xBA68C8FF, 0x7B1FA2FF}  -- Purple
}

