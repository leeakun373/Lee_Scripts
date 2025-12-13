--[[
  Marker Function: Delete Markers in Time Selection
  Description: Deletes all project markers within the time selection range
  - Only deletes markers, not regions
  - Requires a valid time selection
]]

local proj = 0

-- Execute function
local function execute()
    -- Get time selection
    local timeSelStart, timeSelEnd = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
    
    if not timeSelStart or not timeSelEnd or timeSelEnd <= timeSelStart then
        return false, "Error: Please set a valid time selection first"
    end
    
    local retval, numMarkers, numRegions = reaper.CountProjectMarkers(proj)
    
    if numMarkers == 0 then
        return false, "No project markers found"
    end
    
    -- Collect markers to delete (must iterate backwards to avoid index issues)
    local markersToDelete = {}
    
    for i = numMarkers + numRegions - 1, 0, -1 do
        local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber = reaper.EnumProjectMarkers(i)
        
        if retval and not isRgn then
            -- Check if marker is within time selection
            if pos >= timeSelStart and pos <= timeSelEnd then
                table.insert(markersToDelete, markrgnIndexNumber)
            end
        end
    end
    
    if #markersToDelete == 0 then
        return false, "No markers found in time selection"
    end
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- Delete markers
    for _, markerIndex in ipairs(markersToDelete) do
        reaper.DeleteProjectMarker(proj, markerIndex, false)
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Delete markers in time selection", -1)
    
    return true, string.format("Success: Deleted %d marker(s) in time selection", #markersToDelete)
end

-- Return module
return {
    name = "Delete in Time Selection",
    description = "Delete all markers within time selection",
    execute = execute,
    buttonColor = {0xFF0000FF, 0xFF3333FF, 0xCC0000FF}  -- Red (destructive action)
}




