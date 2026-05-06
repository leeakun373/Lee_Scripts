--[[
  Marker Function: Renumber Markers by Timeline Order
  Description: 重新给marker按照工程时间顺序编号（1, 2, 3...）
  - 收集所有markers
  - 按照时间位置排序
  - 重新编号为1, 2, 3...
]]

local proj = 0

-- Execute function
local function execute()
    -- 获取所有markers
    local retval, numMarkers, numRegions = reaper.CountProjectMarkers(proj)
    
    if numMarkers == 0 then
        return false, "Error: No markers found in project"
    end
    
    -- 收集所有markers信息
    local markers = {}
    for i = 0, numMarkers + numRegions - 1 do
        local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber, color = reaper.EnumProjectMarkers3(proj, i)
        
        if retval and not isRgn then
            table.insert(markers, {
                enumIndex = i,
                pos = pos,
                name = name,
                currentId = markrgnIndexNumber,
                color = color or 0
            })
        end
    end
    
    if #markers == 0 then
        return false, "Error: No markers found"
    end
    
    -- 按照时间位置排序
    table.sort(markers, function(a, b)
        return a.pos < b.pos
    end)
    
    -- 开始批量更新
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- 第一步：先给所有markers设置临时ID（从1000开始，避免冲突）
    local tempIdStart = 1000
    for i, marker in ipairs(markers) do
        reaper.SetProjectMarkerByIndex(
            proj,
            marker.enumIndex,
            false,
            marker.pos,
            0,
            tempIdStart + i - 1,  -- 临时ID：1000, 1001, 1002...
            marker.name,
            marker.color
        )
    end
    
    -- 强制重新排序（使用flags&2来避免自动排序）
    if reaper.SetProjectMarkerByIndex2 then
        reaper.SetProjectMarkerByIndex2(proj, -1, false, 0, 0, -1, "", 0, 2)
    end
    
    -- 重新枚举markers（因为ID已经改变，需要重新获取enumIndex）
    local sortedMarkers = {}
    local retval, numMarkers2, numRegions2 = reaper.CountProjectMarkers(proj)
    for i = 0, numMarkers2 + numRegions2 - 1 do
        local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber, color = reaper.EnumProjectMarkers3(proj, i)
        if retval and not isRgn and markrgnIndexNumber >= tempIdStart then
            table.insert(sortedMarkers, {
                enumIndex = i,
                pos = pos,
                name = name,
                color = color or 0
            })
        end
    end
    
    -- 按位置排序（虽然应该已经排序了，但为了确保）
    table.sort(sortedMarkers, function(a, b)
        return a.pos < b.pos
    end)
    
    -- 第二步：重新编号为1, 2, 3...
    local successCount = 0
    for newId, marker in ipairs(sortedMarkers) do
        local success = reaper.SetProjectMarkerByIndex(
            proj,
            marker.enumIndex,
            false,
            marker.pos,
            0,
            newId,  -- 新的编号：1, 2, 3...
            marker.name,
            marker.color
        )
        
        if success then
            successCount = successCount + 1
        end
    end
    
    -- 强制重新排序和UI更新
    if reaper.SetProjectMarkerByIndex2 then
        reaper.SetProjectMarkerByIndex2(proj, -1, false, 0, 0, -1, "", 0, 2)
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Renumber markers by timeline order", -1)
    
    if successCount > 0 then
        return true, string.format("Success: Renumbered %d marker(s) (1, 2, 3...)", successCount)
    else
        return false, "Error: Failed to renumber markers"
    end
end

-- Return module
return {
    name = "Renumber Markers",
    description = "Renumber all markers by timeline order (1, 2, 3...)",
    execute = execute,
    buttonColor = {0xFF9800FF, 0xFFB74DFF, 0xF57C00FF}  -- Orange
}

