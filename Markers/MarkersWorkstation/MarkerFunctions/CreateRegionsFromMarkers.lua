--[[
  Marker Function: Create Regions from Markers (Optimized)
  Description: 为每个marker附近的item创建region
  - 找到marker附近的items（允许容差）
  - 只处理激活的音频items（排除empty items和MIDI items）
  - 只处理未mute的items（item本身未mute且所在轨道也未mute）
  - 如果垂直方向有重叠，选择最长的item
  - 使用marker的名字作为region的名字
  - 避免重复创建region
  - 优化匹配逻辑和性能
]]

local proj = 0

-- Maximum distance between marker and item start (in seconds)
-- Marker can be slightly before the item
local MARKER_ITEM_TOLERANCE = 1.0  -- 1 second tolerance

-- Maximum position difference for considering items as "vertically overlapping" (in seconds)
local VERTICAL_OVERLAP_TOLERANCE = 0.01  -- 10ms tolerance for vertical overlap

-- Execute function
local function execute()
    -- Get all markers
    local retval, numMarkers, numRegions = reaper.CountProjectMarkers(proj)
    
    if numMarkers == 0 then
        return false, "Error: No markers found in project"
    end
    
    -- Collect all markers
    local markers = {}
    for i = 0, numMarkers + numRegions - 1 do
        local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber, color = reaper.EnumProjectMarkers3(proj, i)
        
        if retval and not isRgn then
            table.insert(markers, {
                pos = pos,
                name = name or "",
                color = color or 0
            })
        end
    end
    
    if #markers == 0 then
        return false, "Error: No markers found"
    end
    
    -- Collect all existing regions for update/duplicate checking
    -- Key: marker name or position-based key, Value: {enumIndex, pos, rgnEnd, name, color}
    local existingRegions = {}
    local existingRegionsByPos = {}  -- For duplicate checking by position
    
    for i = 0, numMarkers + numRegions - 1 do
        local retval, isRgn, pos, rgnEnd, name, markrgnIndexNumber, color = reaper.EnumProjectMarkers3(proj, i)
        if retval and isRgn then
            -- Store by position for duplicate checking
            local posKey = string.format("%.6f", pos)
            existingRegionsByPos[posKey] = {
                enumIndex = i,
                pos = pos,
                rgnEnd = rgnEnd,
                name = name or "",
                color = color or 0
            }
            
            -- Also store by name for matching
            if name and name ~= "" then
                existingRegions[name] = {
                    enumIndex = i,
                    pos = pos,
                    rgnEnd = rgnEnd,
                    name = name,
                    color = color or 0
                }
            end
        end
    end
    
    -- Collect all active (non-muted) audio items in project
    -- Only include items that:
    -- 1. Are not muted AND on tracks that are not muted
    -- 2. Are not empty items (have a take)
    -- 3. Are not MIDI items (only audio items)
    local allItems = {}
    local itemCount = reaper.CountMediaItems(proj)
    
    for i = 0, itemCount - 1 do
        local item = reaper.GetMediaItem(proj, i)
        if item then
            -- Check if item is empty (no take)
            local activeTake = reaper.GetActiveTake(item)
            if activeTake then
                -- Check if item is MIDI
                if not reaper.TakeIsMIDI(activeTake) then
                    -- Check if item itself is muted
                    local itemMuted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
                    
                    -- Check if item's track is muted
                    local track = reaper.GetMediaItemTrack(item)
                    local trackMuted = 0
                    if track then
                        trackMuted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
                    end
                    
                    -- Only include items that are not muted AND on tracks that are not muted
                    if itemMuted == 0 and trackMuted == 0 then  -- 0 means not muted, 1 means muted
                        local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                        local itemEnd = itemPos + itemLen
                        
                        table.insert(allItems, {
                            item = item,
                            pos = itemPos,
                            len = itemLen,
                            endPos = itemEnd
                        })
                    end
                end
            end
        end
    end
    
    if #allItems == 0 then
        return false, "Error: No items found in project"
    end
    
    -- For each marker, find nearby items and create/update region from the longest one
    local regionsCreated = 0
    local regionsUpdated = 0
    local markersMatched = 0
    local markersUnmatched = 0
    local regionsSkipped = 0
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    for _, marker in ipairs(markers) do
        -- Find items near this marker
        -- Marker can be slightly before the item (within tolerance) or at item start
        local nearbyItems = {}
        
        for _, itemData in ipairs(allItems) do
            -- Check if marker is near the item start
            local distance = itemData.pos - marker.pos
            
            -- Marker should be at or slightly before item start (within tolerance)
            if distance >= 0 and distance <= MARKER_ITEM_TOLERANCE then
                table.insert(nearbyItems, itemData)
            end
        end
        
        if #nearbyItems > 0 then
            -- Group items by position to find truly overlapping items
            local positionGroups = {}
            
            for _, itemData in ipairs(nearbyItems) do
                -- Round position to group items that are at the same position (vertically overlapping)
                local roundedPos = math.floor(itemData.pos * 100) / 100  -- Round to 10ms
                
                if not positionGroups[roundedPos] then
                    positionGroups[roundedPos] = {}
                end
                table.insert(positionGroups[roundedPos], itemData)
            end
            
            -- Find the group with the longest item
            local targetItem = nil
            local maxLength = 0
            
            for _, group in pairs(positionGroups) do
                -- Check if items in this group are truly overlapping (same position)
                if #group > 1 then
                    -- Multiple items at similar position - find longest
                    for _, itemData in ipairs(group) do
                        if itemData.len > maxLength then
                            maxLength = itemData.len
                            targetItem = itemData
                        end
                    end
                else
                    -- Single item at this position
                    if group[1].len > maxLength then
                        maxLength = group[1].len
                        targetItem = group[1]
                    end
                end
            end
            
            if targetItem then
                local regionName = marker.name ~= "" and marker.name or "Region"
                local posKey = string.format("%.6f", targetItem.pos)
                
                -- Check if region already exists (by name or by position)
                local existingRegion = nil
                
                -- First try to find by marker name
                if marker.name ~= "" and existingRegions[marker.name] then
                    existingRegion = existingRegions[marker.name]
                -- Then try to find by position (within tolerance)
                elseif existingRegionsByPos[posKey] then
                    local posRegion = existingRegionsByPos[posKey]
                    -- Check if position is close enough (within 10ms)
                    if math.abs(posRegion.pos - targetItem.pos) < 0.01 then
                        existingRegion = posRegion
                    end
                end
                
                if existingRegion then
                    -- Update existing region: only update end position if it changed
                    if math.abs(existingRegion.rgnEnd - targetItem.endPos) > 0.001 then
                        local success = reaper.SetProjectMarkerByIndex(
                            proj,
                            existingRegion.enumIndex,  -- markrgnidx: enum index
                            true,                       -- isrgn: true for region
                            existingRegion.pos,         -- pos: keep original start position
                            targetItem.endPos,          -- rgnend: update to new end position
                            -1,                         -- IDnumber: keep original ID
                            regionName,                 -- name: keep marker name
                            existingRegion.color         -- color: keep original color
                        )
                        
                        if success then
                            regionsUpdated = regionsUpdated + 1
                            markersMatched = markersMatched + 1
                        end
                    else
                        -- Region already exists and end position is the same
                        regionsSkipped = regionsSkipped + 1
                        markersMatched = markersMatched + 1
                    end
                else
                    -- Create new region from the target item
                    local success = reaper.AddProjectMarker2(
                        proj,
                        true,              -- isrgn: true for region
                        targetItem.pos,    -- pos: item start position
                        targetItem.endPos, -- rgnend: item end position
                        regionName,        -- name: use marker name
                        -1,                -- wantidx: auto-assign ID
                        marker.color       -- color: use marker color
                    )
                    
                    if success then
                        regionsCreated = regionsCreated + 1
                        markersMatched = markersMatched + 1
                    end
                end
            end
        else
            markersUnmatched = markersUnmatched + 1
        end
    end
    
    -- Force re-sort and UI update
    if reaper.SetProjectMarkerByIndex2 then
        reaper.SetProjectMarkerByIndex2(proj, -1, false, 0, 0, -1, "", 0, 2)
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Create regions from markers", -1)
    
    -- Build detailed message
    local messageParts = {}
    
    if regionsCreated > 0 then
        table.insert(messageParts, string.format("Created %d region(s)", regionsCreated))
    end
    
    if regionsUpdated > 0 then
        table.insert(messageParts, string.format("Updated %d region(s)", regionsUpdated))
    end
    
    if markersMatched > 0 then
        table.insert(messageParts, string.format("matched %d marker(s)", markersMatched))
    end
    
    if regionsSkipped > 0 then
        table.insert(messageParts, string.format("skipped %d unchanged", regionsSkipped))
    end
    
    if markersUnmatched > 0 then
        table.insert(messageParts, string.format("%d marker(s) unmatched", markersUnmatched))
    end
    
    local message = table.concat(messageParts, ", ")
    
    if regionsCreated > 0 or regionsUpdated > 0 then
        return true, message
    else
        if markersUnmatched > 0 then
            return false, string.format("No regions created/updated: %d marker(s) found no nearby items", markersUnmatched)
        else
            return false, "No regions created/updated (all regions already exist and unchanged)"
        end
    end
end

-- Return module
return {
    name = "Create Regions from Markers",
    description = "Create regions from active audio items near markers (excludes empty/MIDI items, item and track must not be muted, longest item if overlapping)",
    execute = execute,
    buttonColor = {0x9C27B0FF, 0xBA68C8FF, 0x7B1FA2FF},  -- Purple
    type = "region"  -- Function type: "marker" or "region"
}

