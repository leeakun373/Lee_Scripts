--[[
  REAPER Lua Script: Toggle FX Chain Window
  Description: Toggle FX Chain window for selected tracks/items (auto-detect Item/Track)
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
    -- Process Take FX Chain
    for _, item in ipairs(items) do
        local take = r.GetActiveTake(item)
        if take then
            local chain_visible = r.TakeFX_GetChainVisible(take)
            if chain_visible ~= -1 then
                -- Chain is visible, close it
                r.TakeFX_Show(take, 0, 0)  -- 0, 0 = close chain window
            else
                -- Chain is not visible, open it
                r.TakeFX_Show(take, 0, 1)  -- 1 = show in chain
            end
        end
    end
elseif #tracks > 0 then
    -- Process Track FX Chain
    for _, track in ipairs(tracks) do
        local chain_visible = r.TrackFX_GetChainVisible(track)
        if chain_visible ~= -1 then
            -- Chain is visible, close it
            r.TrackFX_Show(track, 0, 0)  -- 0, 0 = close chain window
        else
            -- Chain is not visible, open it
            r.TrackFX_Show(track, 0, 1)  -- 1 = show in chain
        end
    end
else
    r.ShowMessageBox("请先选择轨道或媒体项", "FX Manager", 0)
    r.Undo_EndBlock("Toggle FX Chain", -1)
    return
end

r.Undo_EndBlock("Toggle FX Chain", -1)
r.UpdateArrange()

