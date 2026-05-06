-- Script: Jump to Previous Item on Selected Track
-- Version: 1.0
-- Author: Gemini
-- Purpose: Moves the edit cursor to the start of the previous media item on the currently selected track.

function JumpToPreviousItem()
  local r = reaper

  -- 1. 获取当前选中的轨道
  local selected_track_idx = r.GetSelectedTrack(0, 0) -- 获取第一个选中的轨道
  if not selected_track_idx then
    -- r.ShowConsoleMsg("没有选中任何轨道。\n")
    return
  end

  -- 2. 获取当前编辑光标位置
  local current_cursor_pos = r.GetCursorPosition()

  -- 3. 获取选中轨道上的所有媒体素材
  local num_items = r.CountTrackMediaItems(selected_track_idx)
  if num_items == 0 then
    -- r.ShowConsoleMsg("选中的轨道上没有媒体素材。\n")
    return
  end

  local prev_item = nil
  local prev_item_pos = -1 

  -- 4. 查找光标之前的第一个 item (最接近光标且在光标前的)
  for i = 0, num_items - 1 do
    local item = r.GetTrackMediaItem(selected_track_idx, i)
    if item then
      local item_start_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
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
    r.SetEditCurPos(prev_item_pos, true, true) -- 移动光标并滚动视图
    -- r.ShowConsoleMsg("已跳转到上一个 item 的起始位置。\n")
  else
    -- r.ShowConsoleMsg("当前光标之前没有更多 item。\n")
    -- 可选：如果没有上一个item，可以跳转到第一个item的开头或工程开头
  end
end

if reaper then
  JumpToPreviousItem()
end
