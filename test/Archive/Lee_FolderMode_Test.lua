--[[
 * ReaScript Name: Folder Mode Test - Track Organization Tool
 * About: Automatically organize selected tracks into folder structure
 * Author: Lee Custom Script
 * Version: 1.0
 * 
 * Usage:
 * 1. Select tracks in order: first = parent folder, others = children
 * 2. Run script to create folder structure
 * 3. New folder will be moved to top level
--]]

-- 脚本信息
SCRIPT_TITLE = "Folder Mode Test v1.0"
SCRIPT_VERSION = "1.0"

-- 检查ReaImGui是否可用
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("此脚本需要ReaImGui扩展。\n请安装ReaPack并下载ReaImGui扩展。", "缺少依赖", 0)
    return
end

-- 全局变量
local r = reaper
local ImGui = {}

-- 动态加载ImGui函数
for name, func in pairs(reaper) do
    if name:match('^ImGui_') then
        ImGui[name:sub(7)] = func
    end
end

-- GUI 相关变量
local ctx = ImGui.CreateContext(SCRIPT_TITLE)
local window_flags = ImGui.WindowFlags_NoCollapse()
local window_open = true

-- 界面状态
local selected_tracks_info = {}
local preview_structure = {}
local enable_console_output = false

---------------------------------------------------------------------
-- 辅助函数
---------------------------------------------------------------------

function LogMessage(message, is_error)
    if not enable_console_output then return end
    local prefix = is_error and "[Folder Script] Error: " or "[Folder Script] Info: "
    local full_message = prefix .. message
    if r.ShowConsoleMsg then
        r.ShowConsoleMsg(full_message .. "\n")
    end
end

function GetSelectedTracksInOrder()
    local tracks = {}
    local sel_count = r.CountSelectedTracks(0)
    
    if sel_count == 0 then
        LogMessage("No tracks selected")
        return tracks
    end
    
    for i = 0, sel_count - 1 do
        local track = r.GetSelectedTrack(0, i)
        if r.ValidatePtr(track, "MediaTrack*") then
            local retval, track_name = r.GetTrackName(track, "")
            local display_name = ""
            if retval and track_name and track_name ~= "" then
                display_name = track_name
            else
                display_name = "Unnamed Track #" .. (r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
            end
            
            table.insert(tracks, {
                track = track,
                name = display_name,
                original_pos = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1, -- 0-based
                original_depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            })
        end
    end
    
    LogMessage("Found " .. #tracks .. " selected tracks")
    return tracks
end

function UpdateTrackInfo()
    selected_tracks_info = GetSelectedTracksInOrder()
    UpdatePreviewStructure()
end

function UpdatePreviewStructure()
    preview_structure = {}
    
    if #selected_tracks_info == 0 then
        table.insert(preview_structure, "Please select tracks...")
        return
    end
    
    if #selected_tracks_info == 1 then
        table.insert(preview_structure, "Need at least 2 tracks (1 parent + 1 or more children)")
        return
    end
    
    -- Show preview structure
    local parent = selected_tracks_info[1]
    table.insert(preview_structure, "📁 " .. parent.name .. " (Parent Folder)")
    
    for i = 2, #selected_tracks_info do
        local child = selected_tracks_info[i]
        table.insert(preview_structure, "   ├── " .. child.name)
    end
    
    table.insert(preview_structure, "")
    table.insert(preview_structure, "Action: Move to top level as independent folder")
end

function CalculateInsertPosition()
    -- Calculate best position to insert at top of track list
    -- Simply return position 0 (top)
    return 0
end

function CreateFolderStructure()
    if #selected_tracks_info < 2 then
        r.ShowMessageBox("Need at least 2 tracks (1 parent + 1 or more children)", SCRIPT_TITLE, 0)
        return false
    end
    
    r.ClearConsole()
    LogMessage("Starting folder structure creation...")
    
    r.Undo_BeginBlock()
    
    local parent_track = selected_tracks_info[1].track
    local child_tracks = {}
    for i = 2, #selected_tracks_info do
        table.insert(child_tracks, selected_tracks_info[i].track)
    end
    
    LogMessage("Parent track: " .. selected_tracks_info[1].name)
    LogMessage("Child tracks count: " .. #child_tracks)
    
    -- Step 1: Calculate target position (top level)
    local target_position = CalculateInsertPosition()
    LogMessage("Target position: " .. target_position)
    
    -- Step 2: Move parent track to target position
    local parent_current_pos = r.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
    if parent_current_pos ~= target_position then
        r.SetOnlyTrackSelected(parent_track)
        r.ReorderSelectedTracks(target_position, 0) -- Move to position 0
        LogMessage("Parent track moved to position " .. target_position)
    end
    
    -- Step 3: Move all child tracks below parent track
    for i, child_track in ipairs(child_tracks) do
        local target_child_pos = target_position + i -- Consecutive positions below parent
        r.SetOnlyTrackSelected(child_track)
        r.ReorderSelectedTracks(target_child_pos, 0)
        LogMessage("Child track " .. i .. " moved to position " .. target_child_pos)
    end
    
    -- Step 4: Set folder depth
    -- Set parent track as folder start (depth = 1)
    r.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
    LogMessage("Parent track set as folder start")
    
    -- Set all child tracks depth to 0 (belong to parent folder)
    for i, child_track in ipairs(child_tracks) do
        r.SetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH", 0)
    end
    
    -- Set last child track as folder end (depth = -1)
    if #child_tracks > 0 then
        local last_child = child_tracks[#child_tracks]
        r.SetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH", -1)
        LogMessage("Last child track set as folder end")
    end
    
    -- Step 5: Restore selection state
    r.SetOnlyTrackSelected(parent_track)
    for _, child_track in ipairs(child_tracks) do
        r.SetTrackSelected(child_track, true)
    end
    
    r.Undo_EndBlock("Create Folder Structure", -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    
    LogMessage("Folder structure creation completed!")
    return true
end

---------------------------------------------------------------------
-- GUI 绘制函数
---------------------------------------------------------------------

function DrawGUI()
    ImGui.SetNextWindowSize(ctx, 600, 500, ImGui.Cond_FirstUseEver())
    
    local visible, open = ImGui.Begin(ctx, SCRIPT_TITLE, window_open, window_flags)
    
    if visible then
        -- 标题和版本信息
        ImGui.TextColored(ctx, 0x4CAF50FF, "Folder Mode Test Tool")
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, 0x757575FF, "Version " .. SCRIPT_VERSION)
        
        ImGui.Separator(ctx)
        
        -- Instructions
        ImGui.TextColored(ctx, 0x2196F3FF, "Instructions:")
        ImGui.Text(ctx, "1. Select tracks in REAPER: First = Parent Folder, Others = Child Tracks")
        ImGui.Text(ctx, "2. Click 'Refresh Selection' button to update preview")
        ImGui.Text(ctx, "3. Confirm structure, then click 'Create Folder Structure'")
        ImGui.Text(ctx, "4. New folder will be moved to top level of track list")
        
        ImGui.Separator(ctx)
        
        -- Control buttons
        if ImGui.Button(ctx, "Refresh Selection", 120, 30) then
            UpdateTrackInfo()
        end
        
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Create Folder Structure", 140, 30) then
            if CreateFolderStructure() then
                r.ShowMessageBox("Folder structure created successfully!", SCRIPT_TITLE, 0)
                UpdateTrackInfo() -- Update display
            end
        end
        
        ImGui.SameLine(ctx)
        ImGui.Checkbox(ctx, "Enable Console Output", enable_console_output)
        if ImGui.IsItemHovered(ctx) then
            ImGui.SetTooltip(ctx, "Show detailed operation info in REAPER console")
        end
        
        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        
        -- Current selection info
        ImGui.TextColored(ctx, 0xFF9800FF, "Current Selection Preview:")
        ImGui.Spacing(ctx)
        
        -- 预览区域
        if ImGui.BeginChild(ctx, "PreviewArea", 0, 200) then
            for _, line in ipairs(preview_structure) do
                if line:match("^📁") then
                    ImGui.TextColored(ctx, 0x4CAF50FF, line) -- 绿色显示父文件夹
                elseif line:match("^   ├──") then
                    ImGui.TextColored(ctx, 0x757575FF, line) -- 灰色显示子轨道
                elseif line:match("^Action:") then
                    ImGui.TextColored(ctx, 0x2196F3FF, line) -- Blue for action description
                else
                    ImGui.Text(ctx, line)
                end
            end
            ImGui.EndChild(ctx)
        end
        
        ImGui.Separator(ctx)
        
        -- Status info
        local sel_count = #selected_tracks_info
        ImGui.TextColored(ctx, 0x757575FF, "Selected Tracks: " .. sel_count)
        if sel_count > 0 then
            ImGui.SameLine(ctx)
            ImGui.TextColored(ctx, 0x757575FF, "| Parent: " .. (sel_count > 0 and selected_tracks_info[1].name or "None"))
            ImGui.SameLine(ctx) 
            ImGui.TextColored(ctx, 0x757575FF, "| Children: " .. math.max(0, sel_count - 1))
        end
        
        ImGui.Spacing(ctx)
        
        -- Close button
        if ImGui.Button(ctx, "Close", 80, 30) then
            window_open = false
        end
        
        ImGui.End(ctx)
    end
    
    return open and window_open
end

---------------------------------------------------------------------
-- 主函数
---------------------------------------------------------------------

function Main()
    if not r then
        print("Error: Cannot access Reaper API")
        return
    end
    
    -- Initialize
    UpdateTrackInfo()
    
    -- Main loop
    function loop()
        window_open = DrawGUI()
        
        if window_open then
            r.defer(loop)
        else
            if ImGui.DestroyContext then
                ImGui.DestroyContext(ctx)
            end
            LogMessage("GUI closed.")
        end
    end
    
    -- Start main loop
    r.defer(loop)
end

-- Execute main function
local status, err = pcall(Main)
if not status then
    local err_msg = "Script execution error: " .. tostring(err)
    if r.ShowMessageBox then
        r.ShowMessageBox(err_msg, SCRIPT_TITLE .. " - Error", 0)
    end
    LogMessage(err_msg, true)
    if ctx and ImGui.DestroyContext then
        ImGui.DestroyContext(ctx)
    end
end
