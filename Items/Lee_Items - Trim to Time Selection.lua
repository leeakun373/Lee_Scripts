-- Trim items to Time Selection
-- 如果有选中item:只处理选中的items
-- 如果没有选中item:处理所有轨道上与time selection重叠的items

local proj = 0

-- 获取 Time Selection
local ts_start, ts_end = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
if not ts_start or not ts_end or ts_end <= ts_start then
  reaper.ShowMessageBox("请先设置一个有效的 Time Selection。", "提示", 0)
  return
end

-- 裁剪单个item到指定范围
local function trim_item_to_range(item, range_start, range_end)
  if not reaper.ValidatePtr(item, "MediaItem*") then
    return false
  end
  
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_start + item_length
  
  -- 计算交集
  local new_start = math.max(item_start, range_start)
  local new_end = math.min(item_end, range_end)
  
  -- 如果没有交集,删除item
  if new_end <= new_start then
    local track = reaper.GetMediaItem_Track(item)
    reaper.DeleteTrackMediaItem(track, item)
    return false
  end
  
  -- 计算左侧裁剪的偏移量
  local left_trim = new_start - item_start
  local new_length = new_end - new_start
  
  -- 更新item位置和长度
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_start)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_length)
  
  -- 更新所有take的起始偏移
  local take_count = reaper.CountTakes(item)
  for i = 0, take_count - 1 do
    local take = reaper.GetTake(item, i)
    if take then
      local start_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
      local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      -- 根据playrate调整offset
      reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", start_offset + left_trim * playrate)
    end
  end
  
  return true
end

-- 收集要处理的items
local items_to_process = {}
local sel_count = reaper.CountSelectedMediaItems(proj)

if sel_count > 0 then
  -- 有选中item:只处理选中的
  for i = 0, sel_count - 1 do
    local item = reaper.GetSelectedMediaItem(proj, i)
    if item then
      table.insert(items_to_process, item)
    end
  end
else
  -- 没有选中item:处理所有轨道上与time selection重叠的items
  local track_count = reaper.CountTracks(proj)
  for t = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, t)
    local item_count = reaper.CountTrackMediaItems(track)
    
    for i = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      if item then
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        
        -- 只处理与time selection有重叠的items
        if item_end > ts_start and item_start < ts_end then
          table.insert(items_to_process, item)
        end
      end
    end
  end
end

if #items_to_process == 0 then
  reaper.ShowMessageBox("没有找到需要处理的 item。", "提示", 0)
  return
end

-- 执行裁剪
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for _, item in ipairs(items_to_process) do
  trim_item_to_range(item, ts_start, ts_end)
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Trim items to Time Selection", -1)




