-- Take Marker Manager - GUI Tool
-- Functions: Copy Take Markers, Clear Take Markers, etc.

-- Check for ImGui
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("This script requires ReaImGui extension.\nPlease install 'ReaImGui' from Extensions > ReaPack > Browse packages", "Missing Dependency", 0)
    return
end

-- GUI variables
local ctx = reaper.ImGui_CreateContext('Take Marker Manager')
local gui = {
    visible = true,
    width = 420,
    height = 350
}

-- Status variables
local status_message = "Ready"
local source_item_info = ""

-- Copy Take Markers to Project Markers function
function copy_to_project_markers()
    local num_selected = reaper.CountSelectedMediaItems(0)
    
    if num_selected == 0 then
        status_message = "Error: Please select source item with take markers"
        return
    end
    
    -- Use first selected item as source
    local source_item = reaper.GetSelectedMediaItem(0, 0)
    local source_take = reaper.GetActiveTake(source_item)
    
    if not source_take then
        status_message = "Error: Source item has no active take"
        return
    end
    
    local num_source_markers = reaper.GetNumTakeMarkers(source_take)
    if num_source_markers == 0 then
        status_message = "Error: Source item has no take markers"
        return
    end
    
    local markers_created = 0
    
    -- Begin undo block
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- Convert take markers to project markers using X-Raym's exact formula
    for j = 0, num_source_markers - 1 do
        -- Use X-Raym's exact GetTakeMarker call (no retval!)
        local pos, name, color = reaper.GetTakeMarker(source_take, j)
        
        -- X-Raym's exact calculation
        local item_pos = reaper.GetMediaItemInfo_Value(source_item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(source_item, "D_LENGTH")
        local take_rate = reaper.GetMediaItemTakeInfo_Value(source_take, "D_PLAYRATE")
        local take_offset = reaper.GetMediaItemTakeInfo_Value(source_take, "D_STARTOFFS")
        
        -- X-Raym's formula
        local proj_pos = item_pos - take_offset + pos / take_rate
        
        -- X-Raym's boundary check
        if proj_pos >= item_pos and proj_pos <= item_pos + item_len then
            -- Create project marker (X-Raym style)
            local marker_name = name or ("TakeMarker_" .. j)
            local marker_color = color or 0
            reaper.AddProjectMarker2(0, false, proj_pos, 0, marker_name, -1, marker_color)
            markers_created = markers_created + 1
        end
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Copy Take Markers to Project", -1)
    
    status_message = string.format("Success: Created %d project markers", markers_created)
end

-- Paste Project Markers to Take Markers function
function paste_from_project_markers()
    local num_selected = reaper.CountSelectedMediaItems(0)
    
    if num_selected == 0 then
        status_message = "Error: Please select target items"
        return
    end
    
    -- Get all project markers
    local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
    
    if num_markers == 0 then
        status_message = "Error: No project markers found"
        return
    end
    
    local markers_added = 0
    local items_processed = 0
    
    -- Begin undo block
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- Process each selected item
    for i = 0, num_selected - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_start + item_length
            
            -- Check each project marker
            for m = 0, num_markers + num_regions - 1 do
                local m_retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(m)
                
                -- Only process markers (not regions)
                if m_retval and not isrgn then
                    -- Check if marker is within item range
                    if pos >= item_start and pos <= item_end then
                        -- Calculate position in take using your proven formula
                        local take_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                        local take_pos = pos - item_start + take_offset
                        
                        -- Add take marker
                        local take_marker_name = name ~= "" and name or ("Marker_" .. markrgnindexnumber)
                        reaper.SetTakeMarker(take, -1, take_marker_name, take_pos)
                        markers_added = markers_added + 1
                    end
                end
            end
            items_processed = items_processed + 1
        end
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Paste Project Markers to Takes", -1)
    
    status_message = string.format("Success: Added %d take markers to %d items", markers_added, items_processed)
end

-- Clear Take Markers function
function clear_take_markers()
    local num_selected = reaper.CountSelectedMediaItems(0)
    
    if num_selected == 0 then
        status_message = "Error: Please select items to clear markers from"
        return
    end
    
    local total_cleared = 0
    local items_processed = 0
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    for i = 0, num_selected - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            local num_markers = reaper.GetNumTakeMarkers(take)
            if num_markers > 0 then
                -- Delete from back to front to avoid index issues
                for j = num_markers - 1, 0, -1 do
                    reaper.DeleteTakeMarker(take, j)
                    total_cleared = total_cleared + 1
                end
                items_processed = items_processed + 1
            end
        end
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Clear Take Markers", -1)
    
    status_message = string.format("Success: Cleared %d markers from %d items", total_cleared, items_processed)
end

-- Clear Project Markers in Time Selection function
function clear_project_markers()
    -- Get time selection
    local timeSelStart, timeSelEnd = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    
    if not timeSelStart or not timeSelEnd or timeSelEnd <= timeSelStart then
        status_message = "Error: Please set a valid time selection first"
        return
    end
    
    local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
    
    if num_markers == 0 then
        status_message = "No project markers found"
        return
    end
    
    -- Collect markers to delete (must iterate backwards to avoid index issues)
    local markersToDelete = {}
    
    for i = num_markers + num_regions - 1, 0, -1 do
        local m_retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        
        if m_retval and not isrgn then
            -- Check if marker is within time selection
            if pos >= timeSelStart and pos <= timeSelEnd then
                table.insert(markersToDelete, markrgnindexnumber)
            end
        end
    end
    
    if #markersToDelete == 0 then
        status_message = "No markers found in time selection"
        return
    end
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- Delete markers
    for _, markerIndex in ipairs(markersToDelete) do
        reaper.DeleteProjectMarker(0, markerIndex, false)
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Clear Project Markers in Time Selection", -1)
    
    status_message = string.format("Success: Deleted %d marker(s) in time selection", #markersToDelete)
end

-- Update source item info
function update_source_info()
    local num_selected = reaper.CountSelectedMediaItems(0)
    if num_selected > 0 then
        local source_item = reaper.GetSelectedMediaItem(0, 0)
        local source_take = reaper.GetActiveTake(source_item)
        if source_take then
            local num_markers = reaper.GetNumTakeMarkers(source_take)
            local take_name = reaper.GetTakeName(source_take)
            source_item_info = string.format("Source: %s (%d markers)", take_name, num_markers)
        else
            source_item_info = "Source: No active take"
        end
    else
        source_item_info = "Source: No item selected"
    end
end

-- GUI main loop
function main_loop()
    reaper.ImGui_SetNextWindowSize(ctx, gui.width, gui.height, reaper.ImGui_Cond_FirstUseEver())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Take Marker Manager', true)
    if visible then
        -- Update source item info
        update_source_info()
        
        -- Display source item info
        reaper.ImGui_Text(ctx, source_item_info)
        reaper.ImGui_Separator(ctx)
        
        -- Instructions
        reaper.ImGui_Text(ctx, "Instructions:")
        reaper.ImGui_Text(ctx, "1. Copy to Project: Select source item with take markers")
        reaper.ImGui_Text(ctx, "2. Paste from Project: Select target items")
        reaper.ImGui_Text(ctx, "3. Clear Take: Select items to clear take markers")
        reaper.ImGui_Text(ctx, "4. Clear Proj (TS): Set time selection first")
        reaper.ImGui_Separator(ctx)
        
        -- Main function buttons
        if reaper.ImGui_Button(ctx, "Copy to Project", 120, 30) then
            copy_to_project_markers()
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Paste from Project", 120, 30) then
            paste_from_project_markers()
        end
        
        -- Second row of buttons (Orange-Yellow for clear buttons)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF8800FF)  -- Orange-Yellow
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF9933FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF6600FF)
        
        if reaper.ImGui_Button(ctx, "Clear Take Markers", 120, 30) then
            clear_take_markers()
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Clear Proj (TS)", 120, 30) then
            clear_project_markers()
        end
        
        reaper.ImGui_PopStyleColor(ctx, 3)  -- Pop yellow colors
        
        reaper.ImGui_Separator(ctx)
        
        -- Status info
        reaper.ImGui_Text(ctx, "Status:")
        reaper.ImGui_TextWrapped(ctx, status_message)
        
        reaper.ImGui_Separator(ctx)
        
        -- Close button (Red)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)  -- Red
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xCC0000FF)
        
        if reaper.ImGui_Button(ctx, "Close", 100, 25) then
            gui.visible = false
        end
        
        reaper.ImGui_PopStyleColor(ctx, 3)  -- Pop red colors
        
        reaper.ImGui_End(ctx)
    end
    
    if open and gui.visible then
        reaper.defer(main_loop)
    else
        -- Don't destroy context, just return
        return
    end
end

-- Launch GUI
main_loop()


