--[[
  FX Functions Module
  Contains all FX-related functionality
]]

local FXFunctions = {}
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

-- Function 1: Open all FX windows for selected tracks and arrange them
function FXFunctions.OpenAllTrackFXWindows()
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
end

-- Function 2: Close all FX windows and FX Chain windows
function FXFunctions.CloseAllFXWindows()
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
end

-- Function 3: Toggle Bypass (Item/Track detection)
function FXFunctions.ToggleBypassOrActive()
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
end

-- Function 4: Toggle FX Chain window (auto-detect Item/Track)
function FXFunctions.ToggleFXChainWindow()
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
end

return FXFunctions

