-- Script: Jump to Next Item on Selected Track
-- Version: 1.0
-- Author: Gemini
-- Purpose: Moves the edit cursor to the start of the next media item on the currently selected track.

function JumpToNextItem()
  local r = reaper

  -- 1. 获取当前选中的轨道
  local selected_track_idx = r.GetSelectedTrack(0, 0) -- 获取第一个选中的轨道
  if not selected_track_idx then
    -- r.ShowConsoleMsg("没有选中任何轨道。\n") -- 可以选择不显示控制台消息以保持简洁
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

  local next_item = nil
  local next_item_pos = -1 

  -- 4. 查找光标之后的第一个 item
  for i = 0, num_items - 1 do
    local item = r.GetTrackMediaItem(selected_track_idx, i)
    if item then
      local item_start_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      -- 需要严格大于当前光标位置，并且不能太接近以至于几乎是同一个位置 (避免重复跳转到当前item的开头)
      -- 为此，我们可以要求 item_start_pos 至少比 current_cursor_pos 大一点点
      -- 或者，如果光标正好在item开头，我们找下一个
      local item_end_pos = item_start_pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")

      if item_start_pos > current_cursor_pos or (current_cursor_pos >= item_start_pos and current_cursor_pos < item_end_pos and item_start_pos + 0.0001 > current_cursor_pos) then
         -- 如果光标在当前item内，但不是严格在开头，我们还是找严格在光标后的
         if item_start_pos <= current_cursor_pos and item_end_pos > current_cursor_pos then
             -- 光标在当前item内，跳过这个item，找下一个
         else
            if next_item == nil or item_start_pos < next_item_pos then
              next_item = item
              next_item_pos = item_start_pos
            end
         end
      end
    end
  end
  
  -- 如果上面的逻辑找不到（比如光标在最后一个item的中间），尝试找严格在光标后的第一个item
  if not next_item then
      for i = 0, num_items - 1 do
        local item = r.GetTrackMediaItem(selected_track_idx, i)
        if item then
          local item_start_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          if item_start_pos > current_cursor_pos + 0.00001 then -- 确保是严格在之后
            if next_item == nil or item_start_pos < next_item_pos then
              next_item = item
              next_item_pos = item_start_pos
            end
          end
        end
      end
  end


  -- 5. 移动光标
  if next_item then
    r.SetEditCurPos(next_item_pos, true, true) -- 移动光标并滚动视图
    -- r.ShowConsoleMsg("已跳转到下一个 item 的起始位置。\n")
  else
    -- r.ShowConsoleMsg("当前光标之后没有更多 item。\n")
    -- 可选：如果没有下一个item，可以跳转到最后一个item的末尾或工程末尾
  end
end

if reaper then
  JumpToNextItem()
end
