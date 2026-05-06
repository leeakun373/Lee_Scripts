-- Count and display the number of selected items
-- Author: Hongkun helper
-- Version: 1.0

-- 获取选中 item 的数量
local count = reaper.CountSelectedMediaItems(0)

-- 显示弹窗
if count == 0 then
  reaper.MB("当前没有选中任何 item。", "Item 统计", 0)
else
  reaper.MB("当前选中 " .. count .. " 个 item。", "Item 统计", 0)
end

