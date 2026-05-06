--[[
  Item Function: Add Fade In/Out
  Description: 给选中的items添加fade in和fade out
  - 可以自定义fade in和fade out的时长
  - 如果item长度小于fade in + fade out的总长度，则按比例分配
  - 默认值：0.2秒
]]

local proj = 0

-- Execute function
local function execute()
    -- 获取选中的items数量
    local selCount = reaper.CountSelectedMediaItems(proj)
    if selCount == 0 then
        return false, "No items selected"
    end
    
    -- 获取用户输入的fade时长
    local defaultFadeIn = "0.2"
    local defaultFadeOut = "0.2"
    
    local retval, userInput = reaper.GetUserInputs(
        "Add Fade In/Out",
        2,
        "Fade In (seconds):,Fade Out (seconds):,extrawidth=200",
        defaultFadeIn .. "," .. defaultFadeOut
    )
    
    if not retval then
        return false, "Cancelled"
    end
    
    -- 解析用户输入
    local fadeInStr, fadeOutStr = userInput:match("([^,]+),([^,]+)")
    if not fadeInStr or not fadeOutStr then
        return false, "Invalid input format"
    end
    
    local fadeInLength = tonumber(fadeInStr)
    local fadeOutLength = tonumber(fadeOutStr)
    
    if not fadeInLength or not fadeOutLength then
        return false, "Invalid number format"
    end
    
    if fadeInLength < 0 or fadeOutLength < 0 then
        return false, "Fade length cannot be negative"
    end
    
    -- 开始撤销组
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    local processed_count = 0
    
    -- 遍历所有选中的items
    for i = 0, selCount - 1 do
        local item = reaper.GetSelectedMediaItem(proj, i)
        if item then
            local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            
            -- 计算实际的fade in和fade out长度
            local actualFadeIn = fadeInLength
            local actualFadeOut = fadeOutLength
            
            -- 如果item长度小于fade in + fade out的总长度，按比例分配
            if itemLength < (fadeInLength + fadeOutLength) then
                -- 按比例分配，fade in和fade out各占一半
                actualFadeIn = itemLength * 0.5
                actualFadeOut = itemLength * 0.5
            else
                -- 确保fade in和fade out都不超过item长度
                actualFadeIn = math.min(fadeInLength, itemLength)
                actualFadeOut = math.min(fadeOutLength, itemLength)
            end
            
            -- 设置fade in
            reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", actualFadeIn)
            
            -- 设置fade out
            reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", actualFadeOut)
            
            processed_count = processed_count + 1
        end
    end
    
    -- 更新项目
    reaper.UpdateArrange()
    
    -- 结束撤销组
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(string.format("Add %.2fs fade in/%.2fs fade out to selected items", fadeInLength, fadeOutLength), -1)
    
    return true, string.format("Added fade in/out to %d item(s)", processed_count)
end

-- Return module
return {
    name = "Add Fade In Out",
    description = "Add fade in and fade out to selected items with custom duration",
    execute = execute,
    buttonColor = {0x607D8BFF, 0x78909CFF, 0x455A64FF}  -- Blue Grey
}

