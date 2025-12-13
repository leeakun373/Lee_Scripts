--[[
  REAPER Lua Script: Close All FX Windows
  Description: Close all FX windows and FX Chain windows
  Author: Lee
]]

local r = reaper

r.Undo_BeginBlock()

local closed_count = 0

-- Close all Track FX windows and Chain windows
local track_count = r.CountTracks(0)
for i = 0, track_count - 1 do
    local track = r.GetTrack(0, i)
    -- Close floating FX windows
    local fx_count = r.TrackFX_GetCount(track)
    for j = 0, fx_count - 1 do
        local hwnd = r.TrackFX_GetFloatingWindow(track, j)
        if hwnd then
            r.TrackFX_Show(track, j, 2)  -- 2 = close floating window
            closed_count = closed_count + 1
        end
    end
    -- Close FX Chain window if open (use 0 as second parameter and 0 as third parameter)
    local chain_visible = r.TrackFX_GetChainVisible(track)
    if chain_visible ~= -1 then
        r.TrackFX_Show(track, 0, 0)  -- 0, 0 = close chain window
        closed_count = closed_count + 1
    end
    -- Also check and close Rec Chain window
    local rec_chain_visible = r.TrackFX_GetRecChainVisible(track)
    if rec_chain_visible ~= -1 then
        r.TrackFX_Show(track, 0x1000000, 0)  -- 0x1000000 = rec chain, 0 = close
        closed_count = closed_count + 1
    end
end

-- Close Master Track FX windows and Chain window
local master_track = r.GetMasterTrack(0)
if master_track then
    -- Close floating FX windows
    local fx_count = r.TrackFX_GetCount(master_track)
    for j = 0, fx_count - 1 do
        local hwnd = r.TrackFX_GetFloatingWindow(master_track, j)
        if hwnd then
            r.TrackFX_Show(master_track, j, 2)
            closed_count = closed_count + 1
        end
    end
    -- Close FX Chain window if open
    local chain_visible = r.TrackFX_GetChainVisible(master_track)
    if chain_visible ~= -1 then
        r.TrackFX_Show(master_track, 0, 0)  -- 0, 0 = close chain window
        closed_count = closed_count + 1
    end
end

-- Close all Take FX windows and Chain windows
local item_count = r.CountMediaItems(0)
for i = 0, item_count - 1 do
    local item = r.GetMediaItem(0, i)
    local take_count = r.GetMediaItemNumTakes(item)
    for j = 0, take_count - 1 do
        local take = r.GetMediaItemTake(item, j)
        if take then
            -- Close floating FX windows
            local fx_count = r.TakeFX_GetCount(take)
            for k = 0, fx_count - 1 do
                local hwnd = r.TakeFX_GetFloatingWindow(take, k)
                if hwnd then
                    r.TakeFX_Show(take, k, 2)
                    closed_count = closed_count + 1
                end
            end
            -- Close FX Chain window if open
            local chain_visible = r.TakeFX_GetChainVisible(take)
            if chain_visible ~= -1 then
                r.TakeFX_Show(take, 0, 0)  -- 0, 0 = close chain window
                closed_count = closed_count + 1
            end
        end
    end
end

r.Undo_EndBlock("Close All FX Windows", -1)
r.UpdateArrange()

