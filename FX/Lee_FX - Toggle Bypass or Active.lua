--[[
  REAPER Lua Script: Toggle Bypass or Active
  Description: Toggle Bypass/Active state for FX on selected tracks/items
  Author: Lee
]]

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

r.Undo_BeginBlock()

local items = getSelectedItems()
local tracks = getSelectedTracks()

-- Priority: Items first, then Tracks
if #items > 0 then
    -- Collect unique tracks from items (to avoid processing same track multiple times)
    local item_tracks = {}
    local track_set = {}  -- Use set to track unique tracks
    
    -- Process Take FX and collect tracks
    for _, item in ipairs(items) do
        local take = r.GetActiveTake(item)
        if take then
            -- Process Take FX
            local fx_count = r.TakeFX_GetCount(take)
            for i = 0, fx_count - 1 do
                local is_enabled = r.TakeFX_GetEnabled(take, i)
                -- Toggle bypass state
                r.TakeFX_SetEnabled(take, i, not is_enabled)
            end
        end
        
        -- Get track for this item
        local track = r.GetMediaItemTrack(item)
        if track and not track_set[track] then
            track_set[track] = true
            table.insert(item_tracks, track)
        end
    end
    
    -- Also process Track FX for tracks containing selected items
    for _, track in ipairs(item_tracks) do
        local fx_count = r.TrackFX_GetCount(track)
        for i = 0, fx_count - 1 do
            local is_enabled = r.TrackFX_GetEnabled(track, i)
            -- Toggle bypass state
            r.TrackFX_SetEnabled(track, i, not is_enabled)
        end
    end
elseif #tracks > 0 then
    -- Process Track FX
    for _, track in ipairs(tracks) do
        local fx_count = r.TrackFX_GetCount(track)
        for i = 0, fx_count - 1 do
            local is_enabled = r.TrackFX_GetEnabled(track, i)
            -- Toggle bypass state
            r.TrackFX_SetEnabled(track, i, not is_enabled)
        end
    end
else
    r.ShowMessageBox("请先选择轨道或媒体项", "FX Manager", 0)
    r.Undo_EndBlock("Toggle Bypass", -1)
    return
end

r.Undo_EndBlock("Toggle Bypass", -1)
r.UpdateArrange()

