--[[
  REAPER Lua脚本: 将最近的project marker复制到光标处
  
  功能说明:
  - 查找光标位置最近的project marker
  - 复制该marker的名称和颜色
  - 在光标位置创建新的marker
  
  使用方法:
  1. 将光标移动到目标位置
  2. 运行此脚本
  3. 脚本会在光标位置创建最近的marker的副本
]]

local proj = 0

-- 获取光标位置
local cursorPos = reaper.GetCursorPosition()

-- 获取所有project markers
local retval, numMarkers, numRegions = reaper.CountProjectMarkers(proj)

if numMarkers == 0 then
  return
end

-- 查找最近的marker
local nearestMarker = nil
local nearestDistance = math.huge
local nearestIndex = -1

for i = 0, numMarkers + numRegions - 1 do
  local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber = reaper.EnumProjectMarkers(i)
  
  if retval and not isRgn then
    -- 只处理markers，不处理regions
    local distance = math.abs(pos - cursorPos)
    
    if distance < nearestDistance then
      nearestDistance = distance
      nearestMarker = {
        pos = pos,
        name = name,
        index = markrgnIndexNumber
      }
      nearestIndex = i
    end
  end
end

if not nearestMarker then
  return
end

-- 获取marker的颜色（需要EnumProjectMarkers3）
local markerColor = 0
local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber, color = reaper.EnumProjectMarkers3(proj, nearestIndex)
if retval and not isRgn then
  markerColor = color or 0
end

-- 开始撤销组
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- 在光标位置创建新的marker，使用原marker的名称和颜色
reaper.AddProjectMarker2(proj, false, cursorPos, 0, nearestMarker.name, -1, markerColor)

-- 更新项目
reaper.UpdateArrange()

-- 结束撤销组
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Copy nearest marker to cursor", -1)




