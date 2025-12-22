--[[
  Marker Function: Create Markers from Selected Items (Optimized)
  Description: Creates project markers at selected items positions
  - Uses item notes as marker name if available
  - Skips creating marker if one already exists at the same position
  - Prevents duplicate markers when multiple items share the same position
  - Skips muted items and items on muted tracks
  - Skips items with zero length or invalid takes
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

-- Check if any parent track is muted (recursive)
local function isAnyParentTrackMuted(track)
    if not track then
        return false
    end
    
    -- Check current track
    local trackMuted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
    if trackMuted == 1 then
        return true
    end
    
    -- Recursively check parent track
    local parentTrack = reaper.GetParentTrack(track)
    if parentTrack then
        return isAnyParentTrackMuted(parentTrack)
    end
    
    return false
end

-- Check if item should be skipped
local function shouldSkipItem(item)
    if not item then
        return true, "Invalid item"
    end
    
    -- Check if item is muted
    local itemMuted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
    if itemMuted == 1 then
        return true, "Item is muted"
    end
    
    -- Get item's track
    local track = reaper.GetMediaItem_Track(item)
    if not track then
        return true, "Item has no track"
    end
    
    -- Check if track is muted
    local trackMuted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
    if trackMuted == 1 then
        return true, "Track is muted"
    end
    
    -- Check if any parent track (folder) is muted
    if isAnyParentTrackMuted(track) then
        return true, "Parent track is muted"
    end
    
    -- Check if item has zero length
    local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if itemLen <= 0 then
        return true, "Item has zero length"
    end
    
    -- Check if item has a valid take
    local take = reaper.GetActiveTake(item)
    if not take then
        return true, "Item has no active take"
    end
    
    -- Check if item is locked (optional - you may want to skip locked items)
    local itemLocked = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
    if itemLocked and (itemLocked & 1) == 1 then
        -- Item is locked, but we'll still process it (you can change this if needed)
        -- return true, "Item is locked"
    end
    
    return false, nil
end

-- Execute function
local function execute()
    local selCount = reaper.CountSelectedMediaItems(proj)
    
    if selCount == 0 then
        return false, "Error: No items selected"
    end
    
    local markersCreated = 0
    local markersSkipped = 0
    local mutedSkipped = 0
    local positionsProcessed = {}
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- Process each selected item
    for i = 0, selCount - 1 do
        local item = reaper.GetSelectedMediaItem(proj, i)
        if item then
            -- Check if item should be skipped (muted, zero length, etc.)
            local skip, reason = shouldSkipItem(item)
            if not skip then
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
            else
                -- Item is muted or invalid, skip
                mutedSkipped = mutedSkipped + 1
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
    if mutedSkipped > 0 then
        message = message .. string.format(", skipped %d muted/invalid item(s)", mutedSkipped)
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




