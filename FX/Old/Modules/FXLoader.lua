--[[
  FX Loader Module
  Handles FX loading, insertion, and button management
]]

local FXLoader = {}
local r = reaper

-- Helper: Get selected tracks
local function getSelectedTracks()
    local tracks = {}
    local count = r.CountSelectedTracks(0)
    for i = 0, count - 1 do
        table.insert(tracks, r.GetSelectedTrack(0, i))
    end
    return tracks
end

-- Helper: Get selected items
local function getSelectedItems()
    local items = {}
    local count = r.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
        table.insert(items, r.GetSelectedMediaItem(0, i))
    end
    return items
end

-- Add FX by name (with validation)
function FXLoader.addFXByName(fx_name)
    if not fx_name or fx_name == "" then
        return false, "FX name is empty"
    end
    
    -- Try to validate by adding to a temporary track (we'll remove it)
    -- Actually, we can't easily validate without adding, so we'll just return the name
    return true, fx_name
end

-- Insert FX to selected objects
function FXLoader.insertFX(fx_name, fx_guid)
    r.Undo_BeginBlock()
    
    local items = getSelectedItems()
    local tracks = getSelectedTracks()
    local inserted_count = 0
    
    -- Smart detection: In REAPER, selecting items automatically selects their tracks.
    -- Strategy: 
    -- 1. If a track has NO selected items but IS selected -> explicitly selected by user -> use Track FX
    -- 2. If selected tracks count > unique item tracks count -> user selected extra tracks -> use Track FX
    -- 3. Otherwise -> tracks are auto-selected from items -> use Take FX
    
    local item_tracks = {}  -- Set of tracks that have selected items
    local unique_item_track_count = 0
    
    -- Collect unique tracks that have selected items
    for _, item in ipairs(items) do
        local track = r.GetMediaItemTrack(item)
        if track and not item_tracks[track] then
            item_tracks[track] = true
            unique_item_track_count = unique_item_track_count + 1
        end
    end
    
    -- Check if there are tracks selected that don't have selected items (explicitly selected)
    local has_explicitly_selected_tracks = false
    for _, track in ipairs(tracks) do
        if not item_tracks[track] then
            has_explicitly_selected_tracks = true
            break
        end
    end
    
    -- Also check if selected tracks count > item tracks count (user selected extra tracks)
    local user_selected_extra_tracks = (#tracks > unique_item_track_count)
    
    -- Decision logic:
    if has_explicitly_selected_tracks or user_selected_extra_tracks then
        -- User explicitly selected tracks (with or without items) -> use Track FX
        for _, track in ipairs(tracks) do
            local fx_index = r.TrackFX_AddByName(track, fx_name, false, -1)
            if fx_index >= 0 then
                inserted_count = inserted_count + 1
            end
        end
    elseif #items > 0 then
        -- Only items selected (tracks are auto-selected) -> use Take FX
        for _, item in ipairs(items) do
            local take = r.GetActiveTake(item)
            if take then
                local fx_index = r.TakeFX_AddByName(take, fx_name, -1)
                if fx_index >= 0 then
                    inserted_count = inserted_count + 1
                end
            end
        end
    elseif #tracks > 0 then
        -- Only tracks selected (no items) -> use Track FX
        for _, track in ipairs(tracks) do
            local fx_index = r.TrackFX_AddByName(track, fx_name, false, -1)
            if fx_index >= 0 then
                inserted_count = inserted_count + 1
            end
        end
    else
        r.Undo_EndBlock("Insert FX", -1)
        return false, "请先选择轨道或媒体项"
    end
    
    r.Undo_EndBlock("Insert FX: " .. fx_name, -1)
    r.UpdateArrange()
    
    if inserted_count > 0 then
        return true, string.format("已插入 %s 到 %d 个对象", fx_name, inserted_count)
    else
        return false, "插入失败：无法找到FX或FX已存在"
    end
end

-- Add FX button (from browser or manual input)
function FXLoader.addFXButton(fx_buttons, fx_info)
    if not fx_info or not fx_info.fx_name or fx_info.fx_name == "" then
        return false, "FX名称不能为空"
    end
    
    -- Check for duplicates
    for _, btn in ipairs(fx_buttons) do
        if btn.fx_name == fx_info.fx_name then
            return false, "FX已存在于列表中"
        end
    end
    
    table.insert(fx_buttons, {
        fx_name = fx_info.fx_name,
        fx_guid = fx_info.fx_guid or nil,
        display_name = fx_info.display_name or fx_info.fx_name
    })
    
    return true, "已添加FX按钮"
end

-- Update FX button
function FXLoader.updateFXButton(fx_buttons, index, fx_info)
    if index > 0 and index <= #fx_buttons then
        if fx_info and fx_info.fx_name and fx_info.fx_name ~= "" then
            -- Check for duplicates (excluding current index)
            for i, btn in ipairs(fx_buttons) do
                if i ~= index and btn.fx_name == fx_info.fx_name then
                    return false, "FX名称已存在"
                end
            end
            
            fx_buttons[index].fx_name = fx_info.fx_name
            fx_buttons[index].fx_guid = fx_info.fx_guid or nil
            fx_buttons[index].display_name = fx_info.display_name or fx_info.fx_name
            return true, "已更新FX按钮"
        else
            return false, "FX名称不能为空"
        end
    end
    return false, "无效的索引"
end

-- Delete FX button
function FXLoader.deleteFXButton(fx_buttons, index)
    if index > 0 and index <= #fx_buttons then
        table.remove(fx_buttons, index)
        return true, "已删除FX按钮"
    end
    return false, "无效的索引"
end

-- Open FX browser and wait for FX to be added
function FXLoader.openFXBrowser()
    -- Open FX browser
    r.Main_OnCommand(40271, 0)  -- FX: Show/hide FX browser
    
    -- Note: This is a simplified version. In a real implementation,
    -- you would need to monitor FX count changes to detect when an FX is added.
    -- For now, we'll return a flag indicating the browser was opened.
    return true, "FX浏览器已打开，请选择FX"
end

-- Get FX name from browser (this would need to be called after FX is added)
-- This is a placeholder - actual implementation would monitor FX additions
function FXLoader.getLastAddedFX(track_or_take)
    -- This would need to track FX count before/after browser usage
    -- For now, return nil as this requires more complex state tracking
    return nil
end

-- Get last added FX from selected track/item
function FXLoader.getLastAddedFXFromSelection()
    local items = getSelectedItems()
    local tracks = getSelectedTracks()
    
    -- Priority: Items first, then Tracks
    if #items > 0 then
        -- Get from Take FX
        for _, item in ipairs(items) do
            local take = r.GetActiveTake(item)
            if take then
                local fx_count = r.TakeFX_GetCount(take)
                if fx_count > 0 then
                    -- Get the last FX (most recently added)
                    -- TakeFX_GetFXName returns (retval, fx_name)
                    local retval, fx_name = r.TakeFX_GetFXName(take, fx_count - 1, "")
                    if retval and fx_name and fx_name ~= "" then
                        return fx_name
                    end
                end
            end
        end
    elseif #tracks > 0 then
        -- Get from Track FX
        for _, track in ipairs(tracks) do
            local fx_count = r.TrackFX_GetCount(track)
            if fx_count > 0 then
                -- Get the last FX (most recently added)
                -- TrackFX_GetFXName returns (retval, fx_name)
                local retval, fx_name = r.TrackFX_GetFXName(track, fx_count - 1, "")
                if retval and fx_name and fx_name ~= "" then
                    return fx_name
                end
            end
        end
    end
    
    return nil
end

-- Apply FX preset
function FXLoader.applyFXPreset(fx_preset, fx_buttons)
    if not fx_preset or not fx_preset.fx_list then
        return false, "无效的预设"
    end
    
    -- Clear current buttons
    for i = #fx_buttons, 1, -1 do
        table.remove(fx_buttons, i)
    end
    
    -- Add FX from preset (sorted by position)
    local sorted_fx = {}
    for _, fx_info in ipairs(fx_preset.fx_list) do
        table.insert(sorted_fx, fx_info)
    end
    table.sort(sorted_fx, function(a, b) return (a.position or 0) < (b.position or 0) end)
    
    for _, fx_info in ipairs(sorted_fx) do
        table.insert(fx_buttons, {
            fx_name = fx_info.fx_name,
            fx_guid = fx_info.fx_guid,
            display_name = fx_info.display_name or fx_info.fx_name
        })
    end
    
    return true, "已加载预设"
end

-- Save current FX buttons as preset
function FXLoader.saveAsFXPreset(fx_buttons, buttons_per_row, preset_name)
    if not preset_name or preset_name == "" then
        return false, "预设名称不能为空"
    end
    
    local fx_list = {}
    for i, btn in ipairs(fx_buttons) do
        table.insert(fx_list, {
            fx_name = btn.fx_name,
            fx_guid = btn.fx_guid,
            display_name = btn.display_name or btn.fx_name,
            position = i
        })
    end
    
    local preset = {
        fx_list = fx_list,
        buttons_per_row = buttons_per_row or 2
    }
    
    return preset
end

return FXLoader

