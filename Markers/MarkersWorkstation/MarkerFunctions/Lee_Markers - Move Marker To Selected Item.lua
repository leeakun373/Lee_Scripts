--[[
  Marker Function: Move Nearest Marker to Selected Item Head (Batch Mode)
  Description: Moves the nearest marker to the head of each selected item
  - Batch operation: Each item matches its nearest marker (one-to-one mapping)
  - Uses greedy algorithm for optimal matching
]]

local proj = 0

-- Get all markers
local function getAllMarkers()
    local markers = {}
    local retval, numMarkers, numRegions = reaper.CountProjectMarkers(proj)
    
    for i = 0, numMarkers + numRegions - 1 do
        local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber = reaper.EnumProjectMarkers(i)
        
        if retval and not isRgn then
            table.insert(markers, {
                pos = pos,
                name = name,
                index = markrgnIndexNumber,
                enumIndex = i
            })
        end
    end
    
    return markers
end

-- Get marker color
local function getMarkerColor(enumIndex)
    local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber, color = reaper.EnumProjectMarkers3(proj, enumIndex)
    if retval and not isRgn then
        return color or 0
    end
    return 0
end

-- Execute function with batch matching
local function execute()
    local selCount = reaper.CountSelectedMediaItems(proj)
    
    if selCount == 0 then
        return false, "Error: No items selected"
    end
    
    -- Get all markers
    local markers = getAllMarkers()
    
    if #markers == 0 then
        return false, "Error: No project markers found"
    end
    
    -- Collect all selected items with their positions
    local selectedItems = {}
    for i = 0, selCount - 1 do
        local item = reaper.GetSelectedMediaItem(proj, i)
        if item then
            local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            table.insert(selectedItems, {
                item = item,
                pos = itemPos,
                itemIndex = i
            })
        end
    end
    
    if #selectedItems == 0 then
        return false, "Error: Could not get selected item information"
    end
    
    -- Calculate all item-marker pairs with distances
    local allPairs = {}
    for _, itemData in ipairs(selectedItems) do
        for _, marker in ipairs(markers) do
            local distance = math.abs(marker.pos - itemData.pos)
            table.insert(allPairs, {
                item = itemData,
                marker = marker,
                distance = distance
            })
        end
    end
    
    -- Sort by distance (shortest first)
    table.sort(allPairs, function(a, b)
        return a.distance < b.distance
    end)
    
    -- Greedy matching: match closest pairs first, ensuring one-to-one mapping
    local matchedItemIndices = {}
    local matchedMarkerIds = {}
    local matches = {}
    
    for _, pair in ipairs(allPairs) do
        local itemKey = pair.item.itemIndex
        local markerKey = pair.marker.index
        
        if not matchedItemIndices[itemKey] and not matchedMarkerIds[markerKey] then
            matchedItemIndices[itemKey] = true
            matchedMarkerIds[markerKey] = true
            
            local markerColor = getMarkerColor(pair.marker.enumIndex)
            table.insert(matches, {
                item = pair.item,
                marker = pair.marker,
                color = markerColor
            })
        end
    end
    
    if #matches == 0 then
        return false, "Error: Could not find suitable item-marker pairs"
    end
    
    -- Execute batch move operations
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    local successCount = 0
    for _, match in ipairs(matches) do
        local success = reaper.SetProjectMarker4(
            proj,
            match.marker.index,
            false,
            match.item.pos,
            0,
            match.marker.name,
            match.color,
            0
        )
        
        if success then
            successCount = successCount + 1
        end
    end
    
    -- Force re-sort and UI update after all changes
    if reaper.SetProjectMarkerByIndex2 then
        reaper.SetProjectMarkerByIndex2(proj, -1, false, 0, 0, -1, "", 0, 2)
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Move markers to selected item heads (batch)", -1)
    
    local message = string.format("Success: Moved %d marker(s) to item head(s)", successCount)
    if #matches < #selectedItems then
        message = message .. string.format(" (%d item(s) unmatched)", #selectedItems - #matches)
    end
    
    return true, message
end

-- Return module
return {
    name = "Move to Item Head",
    description = "Move nearest markers to selected item heads (batch mode: MA→ItemA, MB→ItemB, etc.)",
    execute = execute,
    buttonColor = {0x2196F3FF, 0x42A5F5FF, 0x1976D2FF}  -- Blue
}

