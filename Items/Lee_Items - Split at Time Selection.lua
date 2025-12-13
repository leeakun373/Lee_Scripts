--[[
  REAPER Lua脚本: 在时间选区两端进行分割
  
  功能说明:
  - 获取当前时间选区的开始和结束时间
  - 在时间选区的这两个位置进行分割
  - 不删除任何内容，仅进行分割操作
  - 如果有选中item:只处理选中的items
  - 如果没有选中item:处理所有轨道上与time selection重叠的items
  
  使用方法:
  1. 设置时间选区（鼠标拖拽或使用快捷键）
  2. （可选）选中要处理的items，如果不选中则处理所有重叠的items
  3. 运行此脚本
  4. 脚本会在时间选区的开始和结束位置自动分割
]]

local proj = 0

-- 获取时间选区
local timeSelStart, timeSelEnd = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)

-- 检查是否有时间选区
if not timeSelStart or not timeSelEnd or timeSelEnd <= timeSelStart then
  return
end

-- 开始撤销组
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- 收集要处理的items
local itemsToProcess = {}
local selCount = reaper.CountSelectedMediaItems(proj)
local hadSelectedItems = selCount > 0  -- 记录是否用户选中了items

if selCount > 0 then
  -- 有选中item:只处理选中的
  for i = 0, selCount - 1 do
    local item = reaper.GetSelectedMediaItem(proj, i)
    if item then
      local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      
      -- 只处理与time selection有重叠的items
      if itemEnd > timeSelStart and itemStart < timeSelEnd then
        table.insert(itemsToProcess, item)
      end
    end
  end
else
  -- 没有选中item:处理所有轨道上与time selection重叠的items
  local trackCount = reaper.CountTracks(proj)
  for trackIdx = 0, trackCount - 1 do
    local track = reaper.GetTrack(proj, trackIdx)
    if track then
      local itemCount = reaper.CountTrackMediaItems(track)
      
      for itemIdx = 0, itemCount - 1 do
        local item = reaper.GetTrackMediaItem(track, itemIdx)
        if item then
          local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          
          -- 只处理与time selection有重叠的items
          if itemEnd > timeSelStart and itemStart < timeSelEnd then
            table.insert(itemsToProcess, item)
          end
        end
      end
    end
  end
end

if #itemsToProcess == 0 then
  reaper.PreventUIRefresh(-1)
  return
end

-- 获取需要处理的轨道（使用集合去重）
local tracksToProcess = {}
if selCount > 0 then
  -- 有选中items时，只处理包含选中items的轨道
  for i = 0, selCount - 1 do
    local item = reaper.GetSelectedMediaItem(proj, i)
    if item then
      local track = reaper.GetMediaItemTrack(item)
      if track and reaper.ValidatePtr(track, "MediaTrack*") then
        -- 使用track指针作为key（Lua中指针可以直接作为table的key）
        tracksToProcess[track] = true
      end
    end
  end
else
  -- 没有选中items时，处理所有轨道
  local trackCount = reaper.CountTracks(proj)
  for trackIdx = 0, trackCount - 1 do
    local track = reaper.GetTrack(proj, trackIdx)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
      tracksToProcess[track] = true
    end
  end
end

-- 在时间选区两端进行分割
-- 从后往前分割（先分割结束位置，再分割开始位置），避免索引问题
-- 每次分割后都会重新获取items列表，这样可以处理分割后新产生的items
local splitTimes = {timeSelEnd, timeSelStart}

for _, splitTime in ipairs(splitTimes) do
  -- 遍历所有需要处理的轨道
  for track, _ in pairs(tracksToProcess) do
    if reaper.ValidatePtr(track, "MediaTrack*") then
      -- 重新获取当前轨道的items数量（因为分割会产生新items）
      local itemCount = reaper.CountTrackMediaItems(track)
      
      -- 从后往前遍历items（因为分割会产生新items，从后往前可以避免索引问题）
      for itemIdx = itemCount - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, itemIdx)
        if item and reaper.ValidatePtr(item, "MediaItem*") then
          local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local itemEnd = itemStart + itemLength
          
          -- 检查：item必须与time selection重叠，并且分割点在item内部（不包括边界）
          if itemEnd > timeSelStart and itemStart < timeSelEnd then
            if splitTime > itemStart and splitTime < itemEnd then
              -- 执行分割
              reaper.SplitMediaItem(item, splitTime)
            end
          end
        end
      end
    end
  end
end

-- 如果用户原来选中了items，分割后只选中时间选区范围内的片段
if hadSelectedItems then
  -- 先取消所有items的选中状态
  reaper.SelectAllMediaItems(proj, false)
  
  -- 遍历所有轨道，找到时间选区范围内的item片段
  for track, _ in pairs(tracksToProcess) do
    if reaper.ValidatePtr(track, "MediaTrack*") then
      local itemCount = reaper.CountTrackMediaItems(track)
      
      for itemIdx = 0, itemCount - 1 do
        local item = reaper.GetTrackMediaItem(track, itemIdx)
        if item and reaper.ValidatePtr(item, "MediaItem*") then
          local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local itemEnd = itemStart + itemLength
          
          -- 选中完全在时间选区范围内的item片段（即中间的B部分）
          -- item必须在时间选区范围内（允许边界重合）
          if itemStart >= timeSelStart and itemEnd <= timeSelEnd then
            reaper.SetMediaItemSelected(item, true)
          end
        end
      end
    end
  end
end

-- 更新项目
reaper.UpdateArrange()

-- 结束撤销组
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Split Items at Time Selection", -1)




