--[[
  REAPER Lua脚本: 给选中的items添加默认fade in和fade out
  
  功能说明:
  - 给所有选中的items添加0.2秒的fade in
  - 给所有选中的items添加0.2秒的fade out
  - 如果item长度小于0.4秒，则按比例分配
  
  使用方法:
  1. 选中要处理的items
  2. 运行此脚本
]]

local proj = 0
local fadeInLength = 0.2  -- 0.2秒fade in
local fadeOutLength = 0.2  -- 0.2秒fade out

-- 获取选中的items数量
local selCount = reaper.CountSelectedMediaItems(proj)

if selCount == 0 then
  return
end

-- 开始撤销组
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

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
  end
end

-- 更新项目
reaper.UpdateArrange()

-- 结束撤销组
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Add 0.2s fade in/out to selected items", -1)




