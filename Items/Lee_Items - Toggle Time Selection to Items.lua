--[[
  REAPER Lua脚本: 切换时间选择到选中items（Toggle）
  
  功能说明:
  - 第一次执行：将时间选择设置为选中items的范围（调用 "Time selection: Set time selection to items"）
  - 再次执行：移除时间选择和循环点（调用 "Time selection: Remove (unselect) time selection and loop points"）
  
  使用方法:
  1. 选中要处理的items
  2. 运行此脚本设置时间选择
  3. 再次运行此脚本移除时间选择
]]

local proj = 0

-- 获取当前时间选择
local ts_start, ts_end = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
local has_time_selection = ts_start and ts_end and ts_end > ts_start

-- 开始撤销组
reaper.Undo_BeginBlock()

if has_time_selection then
  -- 如果有时间选择，则移除时间选择和循环点
  -- 查找命令：Time selection: Remove (unselect) time selection and loop points
  -- 尝试查找命名命令（适用于SWS扩展或自定义动作）
  local cmd_id = reaper.NamedCommandLookup("_SWS_AWREMTSEL")  -- SWS命令
  if cmd_id == 0 then
    cmd_id = reaper.NamedCommandLookup("_XENAKIOS_REMOVETIMESELLOOP")  -- Xenakios命令
  end
  if cmd_id == 0 then
    -- 如果找不到单一命令，使用REAPER内置命令组合
    reaper.Main_OnCommand(40020, 0)  -- Remove loop points
    reaper.Main_OnCommand(40635, 0)  -- Remove time selection
  else
    reaper.Main_OnCommand(cmd_id, 0)  -- 使用找到的命令（同时移除时间选择和循环点）
  end
  reaper.Undo_EndBlock("Remove time selection and loop points", -1)
else
  -- 如果没有时间选择，则设置时间选择到选中items的范围
  local sel_count = reaper.CountSelectedMediaItems(proj)
  
  if sel_count == 0 then
    reaper.Undo_EndBlock("Set time selection to items", -1)
    return
  end
  
  -- 使用REAPER内置命令：Time selection: Set time selection to items
  -- 40290: Set time selection to selected items
  reaper.Main_OnCommand(40290, 0)
  reaper.Undo_EndBlock("Set time selection to items", -1)
  reaper.UpdateArrange()
end

