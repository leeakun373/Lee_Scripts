--[[
  Item Function: Move Cursor to Item Start
  Description: 移动光标到选中item的头部
  - 将编辑光标移动到第一个选中item的开始位置
  - 自动滚动视图以显示目标位置
]]

local proj = 0

-- Execute function
local function execute()
    local item_cnt = reaper.CountSelectedMediaItems(proj)
    if item_cnt == 0 then
        return false, "Error: No item selected"
    end
    
    -- 获取第一个选中的item
    local item = reaper.GetSelectedMediaItem(proj, 0)
    if not item then
        return false, "Error: Failed to get selected item"
    end
    
    -- 获取item的开始位置
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    
    -- 移动光标到item头部，并滚动视图
    reaper.SetEditCurPos(item_pos, true, true)
    
    -- 更新界面
    reaper.UpdateArrange()
    
    return true, "Cursor moved to item start"
end

-- Return module
return {
    name = "Move Cursor to Item Start",
    description = "Move cursor to start of first selected item",
    execute = execute,
    buttonColor = {0x4CAF50FF, 0x66BB6AFF, 0x43A047FF}  -- Green
}

