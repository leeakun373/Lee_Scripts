--[[
  Item Function: Select All Items on Current Track
  Description: 全选当前轨道上的所有item
  - 获取当前轨道（优先选中的轨道，否则最后触摸的轨道）
  - 取消所有item的选择
  - 选中该轨道上的所有item
]]

local proj = 0

-- Execute function
local function execute()
    -- 获取当前轨道：优先选中的轨道，否则最后触摸的轨道
    local track = reaper.GetSelectedTrack(proj, 0)
    if not track then
        track = reaper.GetLastTouchedTrack()
    end
    
    if not track then
        return false, "Error: No track selected or touched"
    end
    
    -- 取消所有item的选择
    reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items
    
    -- 获取轨道上的item数量
    local item_count = reaper.CountTrackMediaItems(track)
    if item_count == 0 then
        return false, "No items on current track"
    end
    
    local selected_count = 0
    
    -- 遍历轨道上的所有item并选中
    for i = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        if item then
            reaper.SetMediaItemSelected(item, true)
            selected_count = selected_count + 1
        end
    end
    
    -- 更新界面
    reaper.UpdateArrange()
    
    if selected_count > 0 then
        return true, string.format("Selected %d item(s) on current track", selected_count)
    else
        return false, "No items found on current track"
    end
end

-- Return module
return {
    name = "Select All Items on Track",
    description = "Select all items on current track",
    execute = execute,
    buttonColor = {0x4CAF50FF, 0x66BB6AFF, 0x43A047FF}  -- Green
}

