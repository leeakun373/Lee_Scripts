--Nzd Workflow:Project backup and Clean
--Back up the project step by step, and the cleanup function can still be used separately;

local reaper = reaper
local ctx = reaper.ImGui_CreateContext("Backup Helper")  -- 创建 ImGui 上下文
local is_running = true   -- 控制 UI 主循环

-----------------------------------------------------------------------------------------------------------------
-- Here is the function module
-----------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------
-- 另存工程
-- Save As Project
----------------------------------------------------------------------------------
function save_backup_project()
    reaper.Main_OnCommand(40022, 0)  -- "File: Save project as..."
end


----------------------------------------------------------------------------------
-- 清理所有 MediaItem 中被静音的项
-- Clear Muted items from all MediaItems
----------------------------------------------------------------------------------
function clean_muted_items()
    reaper.Undo_BeginBlock()
    local count = reaper.CountMediaItems(0)
    for i = count - 1, 0, -1 do
        local item = reaper.GetMediaItem(0, i)
        if reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1 then
            reaper.DeleteTrackMediaItem(reaper.GetMediaItemTrack(item), item)
        end
    end
    reaper.Undo_EndBlock("Clean Muted Items", -1)
end


----------------------------------------------------------------------------------
-- 清理所有空轨道：删除被静音的文件夹及其所有子轨道，删除单独的空轨道
-- Clean all empty tracks: Delete muted folders and all their subtracks, delete individual empty tracks
----------------------------------------------------------------------------------
function clean_empty_tracks()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    -- 取消所有轨道的选中状态
    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
    -- 先清理静音的文件夹轨道及其所有子轨道
    local num_tracks = reaper.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetTrackDepth(track)
        local isMuted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
        local has_children = false
        -- 先检查该轨道是否是文件夹，并且是否有子轨道
        if depth >= 0 and isMuted then
            for j = i + 1, num_tracks - 1 do
                local child_track = reaper.GetTrack(0, j)
                local child_depth = reaper.GetTrackDepth(child_track)
                if child_depth <= depth then
                    break -- 遇到同级或更上级的轨道，停止检查
                end
                has_children = true
            end
            -- 只有确实是一个有子轨道的文件夹轨道才进行选中
            if has_children then
                reaper.SetTrackSelected(track, true) -- 选中文件夹轨道
                -- 选中它的所有子轨道
                for j = i + 1, num_tracks - 1 do
                    local child_track = reaper.GetTrack(0, j)
                    local child_depth = reaper.GetTrackDepth(child_track)
                    if child_depth <= depth then
                        break -- 遇到下一个文件夹或根轨道，停止
                    end
                    reaper.SetTrackSelected(child_track, true) -- 选中子轨道
                end
            end
        end
    end
    -- 将所有选中的轨道移动到第一轨之上
    local first_track = reaper.GetTrack(0, 0)  -- 获取第一轨
    -- 获取所有选中的轨道并将它们移动到第一轨之前
    local selected_tracks = {}
    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.IsTrackSelected(track) then
            table.insert(selected_tracks, track)
        end
    end
    -- 将选中的轨道移动到第一个轨道之前
    for _, track in ipairs(selected_tracks) do
        local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        reaper.ReorderSelectedTracks(track_index, 0) -- 将轨道移动到第 1 轨之前
    end
    -- 删除选中的轨道
    for _, track in ipairs(selected_tracks) do
        reaper.DeleteTrack(track)
    end
    -- -------------------------------
    -- 清理单独的空轨道（直接删除，无需提示）
    -- -------------------------------
    function get_all_tracks()
        local tracks = {}
        local track_count = reaper.CountTracks(0)
        for i = 0, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            if track then
                table.insert(tracks, { track = track, depth = depth })
            end
        end
        return tracks
    end
    function is_empty_track(track)
        if not track then return false end
        local fx_count   = reaper.TrackFX_GetCount(track)
        local item_count = reaper.CountTrackMediaItems(track)
        local env_count  = reaper.CountTrackEnvelopes(track)
        local is_armed   = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
        local is_muted   = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
        local routing    = reaper.GetTrackNumSends(track, -1) +
                           reaper.GetTrackNumSends(track,  0) +
                           reaper.GetTrackNumSends(track,  1)
        return fx_count == 0 and item_count == 0 and env_count == 0 and routing == 0 and is_armed == 0
    end
    function delete_empty_tracks()
        reaper.PreventUIRefresh(1)
        reaper.Undo_BeginBlock()
        local deleted_any = true
        while deleted_any do
            deleted_any = false
            local all_tracks = get_all_tracks()
            for i = #all_tracks, 1, -1 do
                local track, depth = all_tracks[i].track, all_tracks[i].depth
                -- 只删除非文件夹轨道
                if track and depth <= 0 and is_empty_track(track) then
                    if reaper.ValidatePtr(track, "MediaTrack*") then
                        reaper.DeleteTrack(track)
                        deleted_any = true
                    end
                end
            end
        end
        reaper.Undo_EndBlock("Delete Empty Tracks", -1)
        reaper.PreventUIRefresh(-1)
        reaper.UpdateArrange()
    end
    delete_empty_tracks()
    
        reaper.Undo_EndBlock("Clean Empty Tracks", -1)
        reaper.PreventUIRefresh(-1)
        reaper.UpdateArrange()
    end
    


----------------------------------------------------------------------------------
-- 清理未使用的音频资源
-- Clean up unused audio resources
----------------------------------------------------------------------------------
function clean_unused_assets()
    reaper.Undo_BeginBlock()
    reaper.Main_OnCommand(40098, 0)
    reaper.Undo_EndBlock("Clean Unused Assets", -1)
end

----------------------------------------------------------------------------------
-- 设置渲染格式：Wav 96khz 24bitPCM Mono
-- Set the rendering format: Wav 96khz 24bitPCM Mono
----------------------------------------------------------------------------------
function set_render_format()
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxgBAA==", true)
    reaper.GetSetProjectInfo(0, "RENDER_SRATE", 96000, true)
    reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 1, true)
    reaper.Main_OnCommand(40015, 0)
end

-- 退出 UI
function quit_ui()
    is_running = false
end

-----------------------------------------------------------------------------------------------------------------
-- Here is the UI module
-----------------------------------------------------------------------------------------------------------------
function show_ui()
    if reaper.ImGui_Begin(ctx, "Backup Helper", true) then
        if reaper.ImGui_Button(ctx, "Save As", 170, 40) then
            save_backup_project()
        end
        reaper.ImGui_Separator(ctx)
        
        if reaper.ImGui_Button(ctx, "Clean items", 170, 40) then
            clean_muted_items()
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Undo it", 90, 40) then
            undo_last_action()
        end
        
        if reaper.ImGui_Button(ctx, "Clean tracks", 170, 40) then
            clean_empty_tracks()
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Undo it", 90, 40) then
            undo_last_action()
        end
        
        if reaper.ImGui_Button(ctx, "Clean assets", 170, 40) then
            clean_unused_assets()
        end
        
        if reaper.ImGui_Button(ctx, "Render:96k 24Bit Mono", 170, 40) then
            set_render_format()
        end
        
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_Button(ctx, "Quit", 170, 40) then
            quit_ui()
        end
        
        reaper.ImGui_End(ctx)
    end
end

function main_loop()
    if is_running then
        show_ui()
        reaper.defer(main_loop)
    end
end

reaper.defer(main_loop)
reaper.UpdateArrange()
