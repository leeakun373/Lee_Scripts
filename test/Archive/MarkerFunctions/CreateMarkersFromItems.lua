--[[
  Marker Function: Create Markers from Selected Items (Optimized)
  Description: Creates project markers at selected items positions
  - Uses item notes as marker name if available
  - Skips creating marker if one already exists at the same position
  - Prevents duplicate markers when multiple items share the same position
]]

local proj = 0

-- Check if marker exists at position (with tolerance)
local function markerExistsAtPosition(pos, tolerance)
    tolerance = tolerance or 0.001  -- Default tolerance: 1ms
    
    local retval, numMarkers, numRegions = reaper.CountProjectMarkers(proj)
    
    for i = 0, numMarkers + numRegions - 1 do
        local retval, isRgn, markerPos, rgnEnd, name, markrgnIndexNumber = reaper.EnumProjectMarkers(i)
        
        if retval and not isRgn then
            -- Check if marker is at the same position (within tolerance)
            if math.abs(markerPos - pos) < tolerance then
                return true, name
            end
        end
    end
    
    return false, nil
end

-- Get item notes
local function getItemNotes(item)
    -- Try ULT method first (if available)
    if reaper.ULT_GetMediaItemNote then
        return reaper.ULT_GetMediaItemNote(item)
    end
    
    -- Fallback to GetSetMediaItemInfo_String
    local retval, notes = reaper.GetSetMediaItemInfo_String(item, 'P_NOTES', '', false)
    if retval then
        return notes or ''
    end
    
    return ''
end

-- Execute function
local function execute()
    local selCount = reaper.CountSelectedMediaItems(proj)
    
    if selCount == 0 then
        return false, "Error: No items selected"
    end
    
    local markersCreated = 0
    local markersSkipped = 0
    local positionsProcessed = {}
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- Process each selected item
    for i = 0, selCount - 1 do
        local item = reaper.GetSelectedMediaItem(proj, i)
        if item then
            local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            
            -- Round position to avoid floating point precision issues
            local roundedPos = math.floor(itemPos * 1000) / 1000
            
            -- Check if we've already processed this position in this batch
            if not positionsProcessed[roundedPos] then
                -- Check if marker already exists at this position
                local exists, existingName = markerExistsAtPosition(roundedPos)
                
                if not exists then
                    -- Get item notes for marker name
                    local itemNotes = getItemNotes(item)
                    local markerName = itemNotes ~= '' and itemNotes or ''
                    
                    -- Create marker
                    reaper.AddProjectMarker2(proj, false, roundedPos, 0, markerName, -1, 0)
                    markersCreated = markersCreated + 1
                    positionsProcessed[roundedPos] = true
                else
                    markersSkipped = markersSkipped + 1
                    positionsProcessed[roundedPos] = true
                end
            else
                -- Position already processed in this batch, skip
                markersSkipped = markersSkipped + 1
            end
        end
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create markers from selected items (optimized)", -1)
    
    local message = string.format("Created %d marker(s)", markersCreated)
    if markersSkipped > 0 then
        message = message .. string.format(", skipped %d duplicate(s)", markersSkipped)
    end
    
    return true, message
end

-- Return module
return {
    name = "Create from Items",
    description = "Create markers at selected items positions (skips duplicates)",
    execute = execute,
    buttonColor = {0x4CAF50FF, 0x66BB6AFF, 0x43A047FF}  -- Green
}


