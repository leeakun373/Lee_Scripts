--[[
  Marker Function: Copy Nearest Marker to Cursor
  Returns function module for Marker Workstation
]]

local proj = 0

-- Find nearest marker
local function findNearestMarker(cursorPos)
    local retval, numMarkers, numRegions = reaper.CountProjectMarkers(proj)
    
    if numMarkers == 0 then
        return nil, nil, -1
    end
    
    local nearestMarker = nil
    local nearestDistance = math.huge
    local nearestIndex = -1
    
    for i = 0, numMarkers + numRegions - 1 do
        local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber = reaper.EnumProjectMarkers(i)
        
        if retval and not isRgn then
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
    
    return nearestMarker, nearestDistance, nearestIndex
end

-- Get marker color
local function getMarkerColor(index)
    local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber, color = reaper.EnumProjectMarkers3(proj, index)
    if retval and not isRgn then
        return color or 0
    end
    return 0
end

-- Execute function
local function execute()
    local cursorPos = reaper.GetCursorPosition()
    local nearestMarker, distance, nearestIndex = findNearestMarker(cursorPos)
    
    if not nearestMarker then
        return false, "Error: No project marker found"
    end
    
    local markerColor = getMarkerColor(nearestIndex)
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    reaper.AddProjectMarker2(proj, false, cursorPos, 0, nearestMarker.name, -1, markerColor)
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Copy nearest marker to cursor", -1)
    
    return true, string.format("Success: Copied marker '%s' to cursor (distance: %.2fs)", nearestMarker.name, distance)
end

-- Return module
return {
    name = "Copy to Cursor",
    description = "Copy nearest marker to cursor position",
    execute = execute,
    buttonColor = nil  -- Default color
}




