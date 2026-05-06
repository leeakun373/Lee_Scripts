--[[
  Reaper Track Content Transfer Script (Lua) - ReaImGui VERSION
  版本: v0.6.0 - 使用ReaImGui实现现代化图形界面
  功能:
  - 使用ReaImGui创建现代化界面
  - 8个源轨道到目标轨道的映射选择
  - 支持移动或复制模式
  - 实时轨道列表更新
--]]

-- 脚本信息
SCRIPT_TITLE = "Track Content Transfer Tool v0.6.0 (ReaImGui)"
SCRIPT_VERSION = "0.6.0"

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
local source_tracks = {} -- 所有可选择的源轨道名称
local dest_tracks = {} -- 所有目标轨道名称  
local source_selection = {} -- 源轨道选择的索引
local dest_selection = {} -- 目标轨道选择的索引
local transfer_mode = 0 -- 0=移动, 1=复制
local enable_console_output = false -- 关闭调试输出

-- 动态List数量
local max_list_count = 8 -- 默认8个，可增加

-- Target Track默认映射设置 (使用Lua模式转义特殊字符)
local default_target_mappings = {
    [3] = "CO%-100K",  -- 转义-字符
    [4] = "CS%-3e",    -- 转义-字符
    [5] = "MKH8040A",
    [6] = "MKH8040B", 
    [7] = "Geofon"
}

-- 设置界面状态
local show_settings = false

-- 轨道数据
local all_track_ptrs = {} -- 轨道名称 -> 轨道指针的映射
local need_refresh = true

---------------------------------------------------------------------
-- 辅助函数
---------------------------------------------------------------------

-- 检查SWS扩展是否可用
function IsSWSAvailable()
  return reaper.SNM_GetSetObjectState ~= nil
end

function IsMicrophoneTrack(track_pointer)
  -- 尝试使用SWS扩展
  if reaper.NF_GetSWSTrackNotes then
    local notes = reaper.NF_GetSWSTrackNotes(track_pointer)
    if notes and notes:match("TYPE=MIC") then
      return true
    end
  -- 备用方法：使用REAPER原生API
  elseif reaper.GetSetMediaTrackInfo_String then
    local retval, notes = reaper.GetSetMediaTrackInfo_String(track_pointer, "P_EXT:notes", "", false)
    if retval and notes and notes:match("TYPE=MIC") then
      return true
    end
  end
  return false
end

function GetTrackNotes(track_pointer)
  -- 尝试使用SWS扩展
  if reaper.NF_GetSWSTrackNotes then
    return reaper.NF_GetSWSTrackNotes(track_pointer) or ""
  -- 备用方法：使用REAPER原生API
  elseif reaper.GetSetMediaTrackInfo_String then
    local retval, notes = reaper.GetSetMediaTrackInfo_String(track_pointer, "P_EXT:notes", "", false)
    return (retval and notes) and notes or ""
  end
  return ""
end

function LogMessage(message, is_error)
    if not enable_console_output then return end
    local prefix = is_error and "[轨道转移脚本] 错误: " or "[轨道转移脚本] 信息: "
    local full_message = prefix .. message
    if r.ShowConsoleMsg then
        r.ShowConsoleMsg(full_message .. "\n")
    end
end

function GetProjectTracks()
    all_track_ptrs = {}
    source_tracks = {}
    dest_tracks = {}
    
    local num_tracks = r.CountTracks(0)
    if num_tracks == 0 then
        LogMessage("当前工程中没有轨道。")
        return false
    end

    for i = 0, num_tracks - 1 do
        local track = r.GetTrack(0, i)
        if r.ValidatePtr(track, "MediaTrack*") then
            local retval, track_name_str = r.GetTrackName(track, "")
            local display_name = ""
            if retval and track_name_str and track_name_str ~= "" then
                display_name = track_name_str
            else
                display_name = "Unnamed Track #" .. (i + 1)
            end
            
            -- 获取Track Notes信息 (使用SWS扩展)
            local track_notes = GetTrackNotes(track)
            
            all_track_ptrs[display_name] = track
            
            -- 源轨道过滤：仅显示Track Notes为空的轨道
            if track_notes == "" then
                table.insert(source_tracks, display_name)
                LogMessage("源轨道: " .. display_name .. " (Notes: 空)")
            else
                LogMessage("跳过源轨道: " .. display_name .. " (Notes: " .. track_notes .. ")")
            end
            
            -- 目标轨道过滤：仅显示Track Notes包含TYPE=MIC的轨道
            if IsMicrophoneTrack(track) then
                table.insert(dest_tracks, display_name)
                LogMessage("目标轨道: " .. display_name .. " (Notes: " .. track_notes .. ")")
            else
                LogMessage("跳过目标轨道: " .. display_name .. " (Notes: " .. track_notes .. ")")
            end
        end
    end
    
    LogMessage("已扫描工程中的 " .. num_tracks .. " 个轨道。源轨道: " .. #source_tracks .. " 个, 目标轨道: " .. #dest_tracks .. " 个")
    return true
end

function InitializeSelections()
    -- 初始化源轨道和目标轨道的选择索引 (ImGui使用0-based索引)
    source_selection = {}
    dest_selection = {}
    for i = 1, max_list_count do
        source_selection[i] = -1 -- -1表示未选择
        dest_selection[i] = -1
    end
    
    -- 自动匹配Source Track ([chan X]格式)
    AutoSelectSourceTracks()
    
    -- 自动匹配Target Track (根据默认映射)
    AutoSelectTargetTracks()
end

function AutoSelectSourceTracks()
    -- 寻找匹配[chan X]格式的轨道
    for i = 1, max_list_count do
        local pattern = "%[chan " .. i .. "%]"
        for j, track_name in ipairs(source_tracks) do
            if track_name:match(pattern) then
                source_selection[i] = j - 1 -- 转换为0-based索引
                LogMessage("自动选择源轨道 " .. i .. ": " .. track_name)
                break
            end
        end
    end
end

function AutoSelectTargetTracks()
    -- 根据默认映射自动选择目标轨道
    for list_num, target_pattern in pairs(default_target_mappings) do
        if list_num <= max_list_count then -- 只处理当前List范围内的
            for j, track_name in ipairs(dest_tracks) do
                if track_name:match(target_pattern) then -- 使用match进行模式匹配
                    dest_selection[list_num] = j - 1 -- 转换为0-based索引
                    LogMessage("自动选择目标轨道 " .. list_num .. ": " .. track_name .. " (匹配: " .. target_pattern .. ")")
                    break
                end
            end
        end
    end
end

function FindTrackByName(name)
    return all_track_ptrs[name]
end

function TransferItemsOnly(source_track_ptr, dest_track_ptr, should_copy)
    local retval_src, src_name = r.GetTrackName(source_track_ptr, "")
    local retval_dest, dest_name = r.GetTrackName(dest_track_ptr, "")
    src_name = src_name or "未知源轨道"
    dest_name = dest_name or "未知目标轨道"

    local num_items = r.CountTrackMediaItems(source_track_ptr)
    if num_items == 0 then
        LogMessage("源轨道 '" .. src_name .. "' 上没有媒体素材。")
        return true
    end

    local action_desc = should_copy and "复制" or "移动"
    local items_transferred = 0

    for i = num_items - 1, 0, -1 do
        local item = r.GetTrackMediaItem(source_track_ptr, i)
        if r.ValidatePtr(item, "MediaItem*") then
            if should_copy then
                local new_item = r.AddMediaItemToTrack(dest_track_ptr)
                if new_item then
                    local chunk_retval, chunk_str = r.GetItemStateChunk(item, "", false)
                    if chunk_retval then
                        r.SetItemStateChunk(new_item, chunk_str, false)
                        local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                        r.SetMediaItemInfo_Value(new_item, "D_POSITION", item_pos)
                        items_transferred = items_transferred + 1
                    end
                end
            else
                if r.MoveMediaItemToTrack(item, dest_track_ptr) then
                    items_transferred = items_transferred + 1
                end
            end
        end
    end

    LogMessage("成功 " .. action_desc .. " " .. items_transferred .. " 个素材从 '" .. src_name .. "' 到 '" .. dest_name .. "'。")
    return items_transferred > 0
end

function ExecuteTransfer()
    r.ClearConsole()
    LogMessage("Starting track content transfer...")
    LogMessage("转移模式: " .. (transfer_mode == 0 and "移动素材" or "复制素材"))
    
    local transfers_count = 0
    local valid_mappings = 0
    
    r.Undo_BeginBlock()
    
    for i = 1, max_list_count do
        if source_selection[i] >= 0 and dest_selection[i] >= 0 then
            local source_name = source_tracks[source_selection[i] + 1] -- ImGui索引转换为Lua索引
            local dest_name = dest_tracks[dest_selection[i] + 1]
            
            if source_name and dest_name then
                local source_ptr = FindTrackByName(source_name)
                local dest_ptr = FindTrackByName(dest_name)
                
                if source_ptr and dest_ptr then
                    if source_ptr ~= dest_ptr then
                        valid_mappings = valid_mappings + 1
                        LogMessage("处理映射 " .. i .. ": '" .. source_name .. "' -> '" .. dest_name .. "'")
                        if TransferItemsOnly(source_ptr, dest_ptr, transfer_mode == 1) then
                            transfers_count = transfers_count + 1
                        end
                    else
                        LogMessage("警告: 映射 " .. i .. " 的源轨道和目标轨道相同，跳过。", true)
                    end
                end
            end
        end
    end
    
    local undo_msg = "轨道内容批量转移: " .. transfers_count .. " 次转移操作"
    r.Undo_EndBlock(undo_msg, -1)
    r.UpdateArrange()
    
    LogMessage("转移完成，共处理 " .. valid_mappings .. " 个有效映射，执行 " .. transfers_count .. " 次转移操作。")
    
    if transfers_count > 0 then
        r.ShowMessageBox("转移完成！\n\n共执行了 " .. transfers_count .. " 次转移操作。\n\n请查看控制台获取详细信息。", SCRIPT_TITLE, 0)
    else
        r.ShowMessageBox("没有执行任何转移操作。\n\n请检查您的映射设置：\n- 确保选择了有效的源轨道和目标轨道\n- 确保源轨道包含媒体素材\n- 确保源轨道和目标轨道不是同一个", SCRIPT_TITLE, 0)
    end
end

---------------------------------------------------------------------
-- GUI 绘制函数
---------------------------------------------------------------------

function DrawGUI()
    ImGui.SetNextWindowSize(ctx, 800, 650, ImGui.Cond_FirstUseEver())
    
    local visible, open = ImGui.Begin(ctx, SCRIPT_TITLE, window_open, window_flags)
    
    if visible then
        -- 检查是否需要刷新轨道列表
        if need_refresh then
            GetProjectTracks()
            need_refresh = false
        end
        
        -- 标题和版本信息
        ImGui.TextColored(ctx, 0x4CAF50FF, "Track Content Transfer Tool")
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, 0x757575FF, "Version " .. SCRIPT_VERSION)
        
        ImGui.Separator(ctx)
        
        -- 转移模式选择
        ImGui.Text(ctx, "Transfer Mode:")
        ImGui.SameLine(ctx)
        
        if ImGui.RadioButton(ctx, "Move Items", transfer_mode == 0) then
            transfer_mode = 0
        end
        ImGui.SameLine(ctx)
        if ImGui.RadioButton(ctx, "Copy Items", transfer_mode == 1) then
            transfer_mode = 1
        end
        
        ImGui.Separator(ctx)
        
        -- 映射设置区域
        ImGui.TextColored(ctx, 0x2196F3FF, "Mapping Settings")
        ImGui.Text(ctx, "Tip: Auto-selected tracks based on [chan X] format and target mappings. You can override manually.")
        
        ImGui.Spacing(ctx)
        
        -- 控制按钮行
        if ImGui.Button(ctx, "Settings", 80, 25) then
            show_settings = not show_settings
        end
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, "Configure target mappings")
        ImGui.SameLine(ctx, 300)
        
        -- List数量控制
        ImGui.Text(ctx, "List Count:")
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 60)
        local changed, new_count = ImGui.InputInt(ctx, "##listcount", max_list_count)
        if changed and new_count >= 1 and new_count <= 32 then
            max_list_count = new_count
            InitializeSelections() -- 重新初始化选择
        end
        ImGui.PopItemWidth(ctx)
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "+1", 30, 25) then
            if max_list_count < 32 then
                max_list_count = max_list_count + 1
                InitializeSelections()
            end
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "-1", 30, 25) then
            if max_list_count > 1 then
                max_list_count = max_list_count - 1
                InitializeSelections()
            end
        end
        
        ImGui.Spacing(ctx)
        
        -- 表格标题
        if ImGui.BeginTable(ctx, "MappingTable", 3, ImGui.TableFlags_Borders() | ImGui.TableFlags_RowBg()) then
            ImGui.TableSetupColumn(ctx, "List", ImGui.TableColumnFlags_WidthFixed(), 50)
            ImGui.TableSetupColumn(ctx, "Source Track", ImGui.TableColumnFlags_WidthStretch())
            ImGui.TableSetupColumn(ctx, "Target Track", ImGui.TableColumnFlags_WidthStretch())
            ImGui.TableHeadersRow(ctx)
            
            -- 绘制动态数量的映射行
            for i = 1, max_list_count do
                ImGui.TableNextRow(ctx)
                
                -- 映射编号
                ImGui.TableSetColumnIndex(ctx, 0)
                ImGui.Text(ctx, tostring(i))
                
                -- 源轨道选择
                ImGui.TableSetColumnIndex(ctx, 1)
                ImGui.PushID(ctx, "source_" .. i)
                
                local source_preview = source_selection[i] >= 0 and source_tracks[source_selection[i] + 1] or "Select source..."
                if ImGui.BeginCombo(ctx, "##source", source_preview) then
                    for j, track_name in ipairs(source_tracks) do
                        local is_selected = (source_selection[i] == j - 1)
                        if ImGui.Selectable(ctx, track_name, is_selected) then
                            source_selection[i] = j - 1
                        end
                        if is_selected then
                            ImGui.SetItemDefaultFocus(ctx)
                        end
                    end
                    ImGui.EndCombo(ctx)
                end
                ImGui.PopID(ctx)
                
                -- 目标轨道选择
                ImGui.TableSetColumnIndex(ctx, 2)
                ImGui.PushID(ctx, "dest_" .. i)
                
                local dest_preview = dest_selection[i] >= 0 and dest_tracks[dest_selection[i] + 1] or "Select target..."
                if ImGui.BeginCombo(ctx, "##dest", dest_preview) then
                    for j, track_name in ipairs(dest_tracks) do
                        local is_selected = (dest_selection[i] == j - 1)
                        if ImGui.Selectable(ctx, track_name, is_selected) then
                            dest_selection[i] = j - 1
                        end
                        if is_selected then
                            ImGui.SetItemDefaultFocus(ctx)
                        end
                    end
                    ImGui.EndCombo(ctx)
                end
                ImGui.PopID(ctx)
            end
            
            ImGui.EndTable(ctx)
        end
        
        ImGui.Spacing(ctx)
        
        -- 设置界面
        if show_settings then
            ImGui.Separator(ctx)
            ImGui.TextColored(ctx, 0xFF9800FF, "Target Track Settings")
            ImGui.Text(ctx, "Configure default target track mappings (leave empty to disable):")
            ImGui.Spacing(ctx)
            
            if ImGui.BeginTable(ctx, "SettingsTable", 3, ImGui.TableFlags_Borders() | ImGui.TableFlags_RowBg()) then
                ImGui.TableSetupColumn(ctx, "List #", ImGui.TableColumnFlags_WidthFixed(), 60)
                ImGui.TableSetupColumn(ctx, "Target Name", ImGui.TableColumnFlags_WidthStretch())
                ImGui.TableSetupColumn(ctx, "Action", ImGui.TableColumnFlags_WidthFixed(), 80)
                ImGui.TableHeadersRow(ctx)
                
                for i = 1, max_list_count do
                    ImGui.TableNextRow(ctx)
                    
                    ImGui.TableSetColumnIndex(ctx, 0)
                    ImGui.Text(ctx, tostring(i))
                    
                    ImGui.TableSetColumnIndex(ctx, 1)
                    ImGui.PushID(ctx, "setting_" .. i)
                    
                    local current_value = default_target_mappings[i] or ""
                    local changed, new_value = ImGui.InputText(ctx, "##mapping", current_value)
                    if changed then
                        if new_value == "" then
                            default_target_mappings[i] = nil
                        else
                            default_target_mappings[i] = new_value
                        end
                    end
                    
                    ImGui.TableSetColumnIndex(ctx, 2)
                    if ImGui.Button(ctx, "Apply") then
                        AutoSelectTargetTracks()
                    end
                    
                    ImGui.PopID(ctx)
                end
                
                ImGui.EndTable(ctx)
            end
            ImGui.Spacing(ctx)
        end
        
        ImGui.Separator(ctx)
        
        -- 操作按钮
        local button_width = 120
        local button_height = 35
        
        -- 执行转移按钮
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(), 0x4CAF50FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), 0x66BB6AFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), 0x43A047FF)
        
        if ImGui.Button(ctx, "Execute Transfer", button_width, button_height) then
            ExecuteTransfer()
        end
        
        ImGui.PopStyleColor(ctx, 3)
        
        -- 刷新轨道列表按钮
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Refresh Tracks", button_width, button_height) then
            need_refresh = true
            InitializeSelections()
        end
        
        -- 清空所有选择按钮
        ImGui.SameLine(ctx)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(), 0xFF9800FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), 0xFFB74DFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), 0xFFA726FF)
        
        if ImGui.Button(ctx, "Clear Selection", button_width, button_height) then
            InitializeSelections()
        end
        
        ImGui.PopStyleColor(ctx, 3)
        
        -- 关闭按钮
        ImGui.SameLine(ctx)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(), 0xF44336FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), 0xE57373FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), 0xD32F2FFF)
        
        if ImGui.Button(ctx, "Close", 80, button_height) then
            window_open = false
        end
        
        ImGui.PopStyleColor(ctx, 3)
        
        ImGui.Spacing(ctx)
        
        -- 状态信息
        ImGui.Separator(ctx)
        ImGui.TextColored(ctx, 0x757575FF, "Total Tracks: " .. #source_tracks)
        ImGui.SameLine(ctx)
        
        local valid_mappings = 0
        for i = 1, max_list_count do
            if source_selection[i] >= 0 and dest_selection[i] >= 0 then
                valid_mappings = valid_mappings + 1
            end
        end
        ImGui.TextColored(ctx, 0x757575FF, "| Mapped Pairs: " .. valid_mappings .. "/" .. max_list_count)
        
        ImGui.End(ctx)
    end
    
    return open and window_open
end

---------------------------------------------------------------------
-- 主函数
---------------------------------------------------------------------

function Main()
    if not r then
        print("错误: 无法访问 Reaper API")
        return
    end
    
    -- 初始化
    if not GetProjectTracks() then
        r.ShowMessageBox("无法获取工程轨道信息。\n\n可能的原因：\n- 当前工程没有轨道\n- 工程尚未保存\n\n请确保当前工程包含轨道并尝试保存工程。", SCRIPT_TITLE, 0)
        return
    end
    
    InitializeSelections()
    
    -- 主循环
    function loop()
        
        window_open = DrawGUI()
        
        
        if window_open then
            r.defer(loop)
        else
            if ImGui.DestroyContext then
                ImGui.DestroyContext(ctx)
            end
            LogMessage("图形界面已关闭。")
        end
    end
    
    -- 开始主循环
    r.defer(loop)
end

-- 执行主函数
local status, err = pcall(Main)
if not status then
    local err_msg = "脚本执行错误: " .. tostring(err)
    if r.ShowMessageBox then
        r.ShowMessageBox(err_msg, SCRIPT_TITLE .. " - 错误", 0)
    end
    LogMessage(err_msg, true)
    if ctx and ImGui.DestroyContext then
        ImGui.DestroyContext(ctx)
    end
end

