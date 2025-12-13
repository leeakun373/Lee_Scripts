--[[
  REAPER Lua Script: Open All Track FX Windows
  Description: Open all FX windows for selected tracks/items and arrange them in grid
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

-- Helper: Check if JS_ReaScriptAPI is available
local function isJSAvailable()
    return r.APIExists("JS_Window_GetRect") and r.APIExists("JS_Window_Move")
end

-- Helper: Calculate grid position for FX window
local function calculateGridPosition(index, cols, spacing, window_width, window_height)
    local col = index % cols
    local row = math.floor(index / cols)
    local x = col * (window_width + spacing)
    local y = row * (window_height + spacing)
    return x, y
end

-- Main function: Open all FX windows for selected tracks and arrange them
r.Undo_BeginBlock()

local items = getSelectedItems()
local tracks = getSelectedTracks()

-- Priority: Items first, then Tracks (similar to Toggle Bypass)
if #items > 0 then
    -- Collect unique tracks from items (to avoid processing same track multiple times)
    local item_tracks = {}
    local track_set = {}  -- Use set to track unique tracks
    
    for _, item in ipairs(items) do
        local track = r.GetMediaItemTrack(item)
        if track and not track_set[track] then
            track_set[track] = true
            table.insert(item_tracks, track)
        end
    end
    
    tracks = item_tracks  -- Use tracks from items
end

if #tracks == 0 then
    r.ShowMessageBox("请先选择至少一个轨道或媒体项", "FX Manager", 0)
    r.Undo_EndBlock("Open All Track FX Windows", -1)
    return
end

-- Collect all FX windows to open
local fx_windows = {}
for _, track in ipairs(tracks) do
    local fx_count = r.TrackFX_GetCount(track)
    for i = 0, fx_count - 1 do
        table.insert(fx_windows, {track = track, fx_index = i})
    end
end

if #fx_windows == 0 then
    r.ShowMessageBox("所选轨道没有FX效果器", "FX Manager", 0)
    r.Undo_EndBlock("Open All Track FX Windows", -1)
    return
end

-- Open all FX windows
for _, fx_info in ipairs(fx_windows) do
    r.TrackFX_Show(fx_info.track, fx_info.fx_index, 3)  -- 3 = floating window
end

-- Arrange windows in grid layout (if JS_ReaScriptAPI is available)
if isJSAvailable() and #fx_windows > 0 then
    -- Use a deferred function to wait for windows to open
    local arrange_attempts = 0
    local max_attempts = 10
    
    local function arrangeWindows()
        arrange_attempts = arrange_attempts + 1
        
        local spacing = 20
        local window_width = 400  -- Estimate
        local window_height = 500  -- Estimate
        local max_cols = 3
        local cols = math.min(#fx_windows, max_cols)
        
        -- Get screen dimensions
        local screen_width, screen_height = 1920, 1080  -- Default
        local hwnd = r.JS_Window_Find("REAPER", true)
        if hwnd then
            local ret, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
            if ret then
                screen_width = right - left
                screen_height = bottom - top
            end
        end
        
        -- Count how many windows are actually open
        local open_count = 0
        for i, fx_info in ipairs(fx_windows) do
            local hwnd = r.TrackFX_GetFloatingWindow(fx_info.track, fx_info.fx_index)
            if hwnd then
                open_count = open_count + 1
            end
        end
        
        -- If not all windows are open yet, try again
        if open_count < #fx_windows and arrange_attempts < max_attempts then
            r.defer(arrangeWindows)
            return
        end
        
        -- Arrange windows
        for i, fx_info in ipairs(fx_windows) do
            local hwnd = r.TrackFX_GetFloatingWindow(fx_info.track, fx_info.fx_index)
            if hwnd then
                local x, y = calculateGridPosition(i - 1, cols, spacing, window_width, window_height)
                -- Center on screen
                x = x + (screen_width - cols * (window_width + spacing)) / 2
                y = y + 50  -- Offset from top
                
                -- Ensure windows don't go off screen
                if x + window_width > screen_width then
                    x = screen_width - window_width - 20
                end
                if y + window_height > screen_height then
                    y = screen_height - window_height - 20
                end
                
                r.JS_Window_Move(hwnd, x, y)
            end
        end
    end
    
    -- Start arranging after a short delay
    r.defer(arrangeWindows)
end

r.Undo_EndBlock("Open All Track FX Windows", -1)
r.UpdateArrange()

