--[[
  Item Function: Select Unmuted Items
  Description: 选中所有未mute的item
  - 取消当前所有item的选择
  - 遍历项目中所有item
  - 选中所有未mute的item
]]

local proj = 0

-- Execute function
local function execute()
    -- 取消所有item的选择
    reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items
    
    -- 获取项目中所有item的数量
    local item_count = reaper.CountMediaItems(proj)
    if item_count == 0 then
        return false, "No items in project"
    end
    
    local selected_count = 0
    
    -- 遍历所有item
    for i = 0, item_count - 1 do
        local item = reaper.GetMediaItem(proj, i)
        if item then
            -- 检查item的mute状态（B_MUTE == 0 表示未mute）
            local is_muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
            if is_muted == 0 then
                -- 选中未mute的item
                reaper.SetMediaItemSelected(item, true)
                selected_count = selected_count + 1
            end
        end
    end
    
    -- 更新界面
    reaper.UpdateArrange()
    
    if selected_count > 0 then
        return true, string.format("Selected %d unmuted item(s)", selected_count)
    else
        return false, "No unmuted items found"
    end
end

-- Return module
return {
    name = "Select Unmuted Items",
    description = "Select all unmuted items in project",
    execute = execute,
    buttonColor = {0x2196F3FF, 0x42A5F5FF, 0x1976D2FF}  -- Blue
}

