--[[
  REAPER Lua Script: Project File Explorer
  Description: 在 REAPER 内部显示工程文件夹的资源管理器
  - 浏览工程文件夹
  - 显示文件和文件夹（分别枚举）
  - 双击打开文件或进入文件夹
  - 双击音频文件在REAPER中插入到轨道
  - 支持上级目录导航
  - 改进的点击反馈和选中高亮
]]

-- Check if ReaImGui is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("This script requires ReaImGui extension.\nPlease install 'ReaImGui' from Extensions > ReaPack > Browse packages", "Missing Dependency", 0)
    return
end

-- Get script directory
local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
local path_sep = package.config:sub(1,1) == "/" and "/" or "\\"

-- Load theme system from Item Workstation
local function loadModule(module_path)
    local f = loadfile(module_path)
    if f then
        return f()
    end
    return nil
end

local Themes = loadModule(script_path .. ".." .. path_sep .. "Items" .. path_sep .. "ItemsWorkstation" .. path_sep .. "Config" .. path_sep .. "Themes.lua")

-- Use modern theme
if Themes then
    Themes.setCurrentTheme("modern")
end

-- GUI variables
local ctx = reaper.ImGui_CreateContext('Project File Explorer')

-- Font size setting
local font_size = 14  -- Slightly larger than default (13)

local gui = {
    visible = true,
    width = 700,
    height = 600
}

-- Get colors from theme
local function getColors()
    local theme = Themes and Themes.getCurrentTheme() or nil
    if not theme then
        -- Fallback colors if theme not loaded
        return {
            TEXT_NORMAL    = 0xEEEEEEFF,
            TEXT_DIM       = 0x888888FF,
            TEXT_FOLDER    = 0x42A5F5FF,
            TEXT_FILE      = 0xCCCCCCFF,
            TEXT_AUDIO     = 0x0F766EFF,  -- Use theme color (Teal-700)
            TEXT_PROJECT   = 0xFFA726FF,
            TEXT_PARENT    = 0xFFA726FF,
            BTN_UP         = 0x27272AFF,
            BTN_REFRESH    = 0x27272AFF,
            BTN_OPEN       = 0x27272AFF,
            BTN_HOME       = 0x0F766EFF,  -- Use theme color
            BTN_INSERT     = 0x0F766EFF,  -- Use theme color
            BG_ROW_ALT     = 0xFFFFFF0D,
            BG_ROW_SELECT  = 0x3F3F46FF,  -- Use theme HEADER color
            BG_ROW_HOVER   = 0x52525BFF,  -- Use theme HEADER_HOVERED color
        }
    end
    
    -- Map theme colors to Project File Explorer colors
    return {
        TEXT_NORMAL    = theme.TEXT or theme.TEXT_NORMAL or 0xE4E4E7FF,
        TEXT_DIM       = theme.TEXT_DISABLED or theme.TEXT_DIM or 0xA1A1AAFF,
        TEXT_FOLDER    = 0x42A5F5FF,  -- Keep folder color (blue)
        TEXT_FILE      = theme.TEXT or theme.TEXT_NORMAL or 0xE4E4E7FF,
        TEXT_AUDIO     = theme.BTN_ITEM_ON or 0x0F766EFF,  -- Use theme item color
        TEXT_PROJECT   = 0xFFA726FF,  -- Keep project color (orange)
        TEXT_PARENT    = 0xFFA726FF,  -- Keep parent color (orange)
        BTN_UP         = theme.BTN_RELOAD or 0x27272AFF,
        BTN_REFRESH    = theme.BTN_RELOAD or 0x27272AFF,
        BTN_OPEN       = theme.BTN_CUSTOM or 0x27272AFF,
        BTN_HOME       = theme.BTN_ITEM_ON or 0x0F766EFF,  -- Use theme item color
        BTN_INSERT     = theme.BTN_ITEM_ON or 0x0F766EFF,  -- Use theme item color
        BG_ROW_ALT     = 0xFFFFFF0D,
        BG_ROW_SELECT  = theme.HEADER or 0x3F3F46FF,
        BG_ROW_HOVER   = theme.HEADER_HOVERED or 0x52525BFF,
    }
end

local COLORS = getColors()

-- State
local current_path = ""
local file_list = {}
local selected_file = nil
local selected_index = nil
local path_history = {}
local show_hidden = false

-- Helper: Get project folder
local function GetProjectFolder()
    local retval, project_path = reaper.EnumProjects(-1, "")
    
    if project_path == "" then
        project_path = reaper.GetProjectPath("")
        if project_path == "" then
            return nil, "工程未保存，无法打开文件夹"
        end
        return project_path
    end
    
    local os_sep = package.config:sub(1, 1)
    local folder = project_path:match("(.*" .. os_sep .. ")")
    
    return folder or project_path:match("(.*/)") or project_path:match("(.*\\)") or ""
end

-- Helper: Get file extension
local function GetFileExtension(filename)
    return filename:match("%.(.+)$") or ""
end

-- Helper: Check if file is audio file
local function IsAudioFile(filename)
    local ext = GetFileExtension(filename):lower()
    local audio_exts = {
        wav = true, mp3 = true, flac = true, aac = true, ogg = true,
        m4a = true, wma = true, aiff = true, aif = true, opus = true,
        wv = true, ape = true, dsd = true, dsf = true, dff = true
    }
    return audio_exts[ext] == true
end

-- Helper: Check if file is REAPER project file
local function IsProjectFile(filename)
    local ext = GetFileExtension(filename):lower()
    return ext == "rpp" or ext == "rpp-bak"
end

-- Helper: Get parent directory
local function GetParentDirectory(path)
    if not path or path == "" then return nil end
    
    local os_sep = package.config:sub(1, 1)
    -- Remove trailing separator
    path = path:gsub(os_sep .. "+$", "")
    
    -- Get parent
    local parent = path:match("(.*" .. os_sep .. ")")
    if parent then
        return parent
    end
    
    -- If no parent found, check if it's a root drive (Windows)
    if os_sep == "\\" and path:match("^[A-Z]:$") then
        return nil  -- Root drive, no parent
    end
    
    return nil
end

-- Load files from directory
local function LoadDirectory(path)
    if not path or path == "" then
        return false, "路径无效"
    end
    
    -- Ensure path ends with separator
    local os_sep = package.config:sub(1, 1)
    if not path:match(os_sep .. "$") then
        path = path .. os_sep
    end
    
    -- Rescan directory
    reaper.EnumerateFiles(path, -1)
    reaper.EnumerateSubdirectories(path, -1)
    
    file_list = {}
    local folders = {}
    local files = {}
    
    -- Add parent directory entry (..)
    local parent = GetParentDirectory(path)
    if parent then
        table.insert(folders, {
            name = "..",
            path = parent,
            is_dir = true,
            is_parent = true
        })
    end
    
    -- Enumerate subdirectories
    local i = 0
    while true do
        local folder = reaper.EnumerateSubdirectories(path, i)
        if not folder then break end
        
        -- Skip hidden folders if not showing hidden
        if show_hidden or not folder:match("^%.") then
            local full_path = path .. folder
            table.insert(folders, {
                name = folder,
                path = full_path,
                is_dir = true,
                is_parent = false
            })
        end
        
        i = i + 1
    end
    
    -- Enumerate files
    i = 0
    while true do
        local file = reaper.EnumerateFiles(path, i)
        if not file then break end
        
        -- Skip hidden files if not showing hidden
        if show_hidden or not file:match("^%.") then
            local full_path = path .. file
            local file_info = {
                name = file,
                path = full_path,
                is_dir = false,
                is_parent = false,
                is_audio = IsAudioFile(file),
                is_project = IsProjectFile(file)
            }
            
            table.insert(files, file_info)
        end
        
        i = i + 1
    end
    
    -- Sort: folders first (except parent), then files (both alphabetically)
    table.sort(folders, function(a, b)
        if a.is_parent then return true end
        if b.is_parent then return false end
        return a.name:lower() < b.name:lower()
    end)
    table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
    
    -- Combine: folders first
    for _, folder in ipairs(folders) do
        table.insert(file_list, folder)
    end
    for _, file in ipairs(files) do
        table.insert(file_list, file)
    end
    
    current_path = path
    selected_file = nil
    selected_index = nil
    return true
end

-- Navigate to parent directory
local function NavigateUp()
    if not current_path or current_path == "" then return end
    
    local parent = GetParentDirectory(current_path)
    if parent then
        LoadDirectory(parent)
    end
end

-- Navigate to folder
local function NavigateTo(folder_path)
    LoadDirectory(folder_path)
end

-- Navigate to project folder
local function NavigateHome()
    local folder, error_msg = GetProjectFolder()
    if folder then
        LoadDirectory(folder)
    else
        if error_msg then
            reaper.ShowMessageBox(error_msg, "提示", 0)
        end
    end
end

-- Open file in REAPER (for audio/project files) or externally
local function OpenFile(file_info)
    if not file_info then return end
    
    local file_path = file_info.path
    
    -- If it's a REAPER project file, open it
    if file_info.is_project then
        reaper.Main_openProject(file_path)
        return
    end
    
    -- If it's an audio file, insert it into REAPER
    if file_info.is_audio then
        local track = reaper.GetSelectedTrack(0, 0)
        if not track then
            -- If no track selected, create a new track or use first track
            local track_count = reaper.CountTracks(0)
            if track_count == 0 then
                reaper.InsertTrackAtIndex(0, true)
            end
            track = reaper.GetTrack(0, 0)
            reaper.SetOnlyTrackSelected(track)
        end
        
        -- Insert media at cursor position
        local cursor_pos = reaper.GetCursorPosition()
        reaper.InsertMedia(file_path, 0)  -- 0 = add to current track
        
        -- Move cursor to end of inserted item (optional)
        local item = reaper.GetSelectedMediaItem(0, 0)
        if item then
            local item_end = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + 
                           reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            reaper.SetEditCurPos(item_end, false, false)
        end
        return
    end
    
    -- For other files, open externally
    reaper.CF_ShellExecute(file_path)
end

-- Initialize: Load project folder
local function Initialize()
    local folder, error_msg = GetProjectFolder()
    if folder then
        LoadDirectory(folder)
    else
        file_list = {}
        current_path = ""
        if error_msg then
            reaper.ShowMessageBox(error_msg, "提示", 0)
        end
    end
end

-- Initialize
Initialize()

-- GUI main loop
local function main_loop()
    -- Apply theme
    local style_var_count = 0
    local color_count = 0
    if Themes then
        local theme = Themes.getCurrentTheme()
        if theme then
            style_var_count, color_count = Themes.applyTheme(ctx, theme)
        end
    end
    
    -- Track additional style vars we push (for themes without style_vars)
    local additional_style_vars = 0
    if not Themes or not Themes.getCurrentTheme() or not Themes.getCurrentTheme().style_vars then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, 10)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 6, 6)
        additional_style_vars = 2
    end
    
    reaper.ImGui_SetNextWindowSize(ctx, gui.width, gui.height, reaper.ImGui_Cond_FirstUseEver())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Project File Explorer', true, reaper.ImGui_WindowFlags_None())
    
    if visible then
        -- Push larger font size for all text
        reaper.ImGui_PushFont(ctx, nil, font_size)
        -- Header: Path display
        reaper.ImGui_TextColored(ctx, COLORS.TEXT_NORMAL, "路径:")
        reaper.ImGui_SameLine(ctx)
        local path_display = current_path or "未选择路径"
        if #path_display > 80 then
            path_display = "..." .. path_display:sub(-77)
        end
        reaper.ImGui_TextWrapped(ctx, path_display)
        
        reaper.ImGui_Separator(ctx)
        
        -- Toolbar buttons
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLORS.BTN_HOME)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COLORS.BTN_HOME + 0x11111100)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COLORS.BTN_HOME - 0x11111100)
        if reaper.ImGui_Button(ctx, " 工程文件夹 ") then
            NavigateHome()
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLORS.BTN_UP)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COLORS.BTN_UP + 0x11111100)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COLORS.BTN_UP - 0x11111100)
        if reaper.ImGui_Button(ctx, " 上级 ") then
            NavigateUp()
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLORS.BTN_REFRESH)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COLORS.BTN_REFRESH + 0x11111100)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COLORS.BTN_REFRESH - 0x11111100)
        if reaper.ImGui_Button(ctx, " 刷新 ") then
            if current_path ~= "" then
                LoadDirectory(current_path)
            else
                Initialize()
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLORS.BTN_OPEN)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COLORS.BTN_OPEN + 0x11111100)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COLORS.BTN_OPEN - 0x11111100)
        if reaper.ImGui_Button(ctx, " 外部打开 ") then
            if current_path ~= "" then
                reaper.CF_ShellExecute(current_path)
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_SameLine(ctx)
        
        -- Show hidden files checkbox
        local changed, checked = reaper.ImGui_Checkbox(ctx, "显示隐藏文件", show_hidden)
        if changed then
            show_hidden = checked
            if current_path ~= "" then
                LoadDirectory(current_path)
            end
        end
        
        reaper.ImGui_Separator(ctx)
        
        -- File list (scrollable)
        local footer_height = 50
        local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
        if reaper.ImGui_BeginChild(ctx, "file_list", 0, -footer_height, child_flags) then
            -- Table header
            if reaper.ImGui_BeginTable(ctx, "files", 3, 
                reaper.ImGui_TableFlags_RowBg() | 
                reaper.ImGui_TableFlags_Borders() | 
                reaper.ImGui_TableFlags_Resizable() |
                reaper.ImGui_TableFlags_ScrollY() |
                reaper.ImGui_TableFlags_Sortable()) then
                
                reaper.ImGui_TableSetupColumn(ctx, "名称", reaper.ImGui_TableColumnFlags_WidthStretch(), 0, 0)
                reaper.ImGui_TableSetupColumn(ctx, "类型", reaper.ImGui_TableColumnFlags_WidthFixed(), 120, 1)
                reaper.ImGui_TableSetupColumn(ctx, "路径", reaper.ImGui_TableColumnFlags_WidthFixed(), 250, 2)
                reaper.ImGui_TableHeadersRow(ctx)
                
                -- File rows
                if #file_list == 0 then
                    reaper.ImGui_TableNextRow(ctx)
                    reaper.ImGui_TableNextColumn(ctx)
                    reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "文件夹为空")
                else
                    for i, file_info in ipairs(file_list) do
                        reaper.ImGui_TableNextRow(ctx)
                        
                        -- Check if this row is selected
                        local is_selected = (selected_index == i)
                        
                        -- Name column (clickable)
                        reaper.ImGui_TableNextColumn(ctx)
                        reaper.ImGui_PushID(ctx, i)
                        
                        local text_color
                        if file_info.is_parent then
                            text_color = COLORS.TEXT_PARENT
                        elseif file_info.is_dir then
                            text_color = COLORS.TEXT_FOLDER
                        elseif file_info.is_audio then
                            text_color = COLORS.TEXT_AUDIO
                        elseif file_info.is_project then
                            text_color = COLORS.TEXT_PROJECT
                        else
                            text_color = COLORS.TEXT_FILE
                        end
                        
                        -- Add icons/prefixes
                        if file_info.is_dir then
                            reaper.ImGui_TextColored(ctx, text_color, "[文件夹] ")
                            reaper.ImGui_SameLine(ctx)
                        elseif file_info.is_audio then
                            reaper.ImGui_TextColored(ctx, text_color, "[音频] ")
                            reaper.ImGui_SameLine(ctx)
                        elseif file_info.is_project then
                            reaper.ImGui_TextColored(ctx, text_color, "[工程] ")
                            reaper.ImGui_SameLine(ctx)
                        end
                        
                        -- Make the name clickable with better feedback
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)
                        local selectable_flags = reaper.ImGui_SelectableFlags_SpanAllColumns()
                        if reaper.ImGui_SelectableFlags_AllowDoubleClick then
                            selectable_flags = selectable_flags | reaper.ImGui_SelectableFlags_AllowDoubleClick()
                        end
                        reaper.ImGui_Selectable(ctx, file_info.name, is_selected, selectable_flags, 0, 0)
                        reaper.ImGui_PopStyleColor(ctx, 1)
                        
                        -- Drag and drop source for files (especially audio files)
                        -- Note: 从 ImGui 窗口拖拽文件到 REAPER 轨道需要系统级拖拽支持
                        -- 目前使用标准 SetDragDropPayload 传递文件路径
                        if not file_info.is_dir and reaper.ImGui_BeginDragDropSource(ctx) then
                            -- 使用标准拖拽 API 传递文件路径
                            if reaper.ImGui_SetDragDropPayload then
                                reaper.ImGui_SetDragDropPayload(ctx, "REAPER_FILE_PATH", file_info.path)
                                reaper.ImGui_Text(ctx, file_info.name)
                                if file_info.is_audio then
                                    reaper.ImGui_TextColored(ctx, COLORS.TEXT_AUDIO, "提示: 双击插入到轨道更可靠")
                                elseif file_info.is_project then
                                    reaper.ImGui_TextColored(ctx, COLORS.TEXT_PROJECT, "提示: 双击打开工程更可靠")
                                else
                                    reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "提示: 双击打开文件更可靠")
                                end
                            end
                            reaper.ImGui_EndDragDropSource(ctx)
                        end
                        
                        -- Double-click to open/navigate
                        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                            if file_info.is_dir then
                                NavigateTo(file_info.path)
                            else
                                OpenFile(file_info)
                            end
                        end
                        
                        -- Single click to select
                        if reaper.ImGui_IsItemClicked(ctx, 0) then
                            selected_file = file_info
                            selected_index = i
                        end
                        
                        -- Type column
                        reaper.ImGui_TableNextColumn(ctx)
                        if file_info.is_dir then
                            reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "文件夹")
                        elseif file_info.is_audio then
                            local ext = GetFileExtension(file_info.name)
                            reaper.ImGui_TextColored(ctx, COLORS.TEXT_AUDIO, ext:upper() .. " 音频")
                        elseif file_info.is_project then
                            reaper.ImGui_TextColored(ctx, COLORS.TEXT_PROJECT, "REAPER 工程")
                        else
                            local ext = GetFileExtension(file_info.name)
                            reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, ext ~= "" and ext:upper() or "文件")
                        end
                        
                        -- Path column (truncated)
                        reaper.ImGui_TableNextColumn(ctx)
                        local path_display = file_info.path
                        if #path_display > 45 then
                            path_display = "..." .. path_display:sub(-42)
                        end
                        reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, path_display)
                        
                        reaper.ImGui_PopID(ctx)
                    end
                end
                
                reaper.ImGui_EndTable(ctx)
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        -- Footer: Selected file info and actions
        reaper.ImGui_Separator(ctx)
        if selected_file then
            reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "选中: ")
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_Text(ctx, selected_file.name)
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, " | ")
            reaper.ImGui_SameLine(ctx)
            local path_display = selected_file.path
            if #path_display > 60 then
                path_display = "..." .. path_display:sub(-57)
            end
            reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, path_display)
            
            -- Action buttons for selected file
            if not selected_file.is_dir then
                reaper.ImGui_SameLine(ctx, 0, 20)
                
                if selected_file.is_audio or selected_file.is_project then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLORS.BTN_INSERT)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COLORS.BTN_INSERT + 0x11111100)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COLORS.BTN_INSERT - 0x11111100)
                    if reaper.ImGui_Button(ctx, selected_file.is_project and " 打开工程 " or " 插入到轨道 ") then
                        OpenFile(selected_file)
                    end
                    reaper.ImGui_PopStyleColor(ctx, 3)
                    reaper.ImGui_SameLine(ctx)
                end
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLORS.BTN_OPEN)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COLORS.BTN_OPEN + 0x11111100)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COLORS.BTN_OPEN - 0x11111100)
                if reaper.ImGui_Button(ctx, " 外部打开 ") then
                    reaper.CF_ShellExecute(selected_file.path)
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
            end
        else
            local footer_text = "双击文件打开，双击文件夹进入 | 音频文件双击插入到轨道 | 共 " .. #file_list .. " 项"
            reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, footer_text)
        end
        
        -- Pop font size
        reaper.ImGui_PopFont(ctx)
        
        reaper.ImGui_End(ctx)
    end
    
    -- Pop theme styles and colors
    if Themes then
        Themes.popTheme(ctx, style_var_count, color_count)
    end
    
    -- Pop additional style vars we added (for themes without style_vars)
    if additional_style_vars > 0 then
        reaper.ImGui_PopStyleVar(ctx, additional_style_vars)
    end
    
    if open and gui.visible then
        reaper.defer(main_loop)
    else
        return
    end
end

-- Launch GUI
main_loop()
