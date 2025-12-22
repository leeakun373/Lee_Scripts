--[[
  Item Function: Move Cursor to Item End
  Description: 移动光标到选中item的尾部
  - 将编辑光标移动到第一个选中item的结束位置
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
    
    -- 获取item的开始位置和长度
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    
    -- 计算item的结束位置
    local item_end = item_pos + item_length
    
    -- 移动光标到item尾部，并滚动视图
    reaper.SetEditCurPos(item_end, true, true)
    
    -- 更新界面
    reaper.UpdateArrange()
    
    return true, "Cursor moved to item end"
end

-- Return module
return {
    name = "Move Cursor to Item End",
    description = "Move cursor to end of first selected item",
    execute = execute,
    buttonColor = {0xFF9800FF, 0xFFB74DFF, 0xF57C00FF}  -- Orange
}

