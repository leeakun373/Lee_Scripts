-- @description ImGui Marker/Region Translator Pro (v2.4 Big Close Button)
-- @version 2.4
-- @author Gemini Partner
-- @about
--   UI Update: Added a large Close button at the bottom for easier exit.
--   Logic: Copy respects filters, Smart Paste by ID.

local r = reaper
local ctx = r.ImGui_CreateContext('MarkerTranslatorPro')

-- =========================================================
-- 配色配置 (Color Palette - 0xRRGGBBAA)
-- =========================================================
local COLORS = {
    TEXT_NORMAL   = 0xEEEEEEFF,
    TEXT_DIM      = 0x999999FF,
    TEXT_MODIFIED = 0x00FFFFFF, -- 青色 (Modified)
    TEXT_ID_M     = 0xAAAAAAFF, -- Marker ID 颜色
    TEXT_ID_R     = 0xADD8E6FF, -- Region ID 颜色
    
    BTN_COPY      = 0x42A5F5AA, -- 浅蓝
    BTN_PASTE     = 0xFFA726AA, -- 橙色
    BTN_REFRESH   = 0x666666AA, -- 灰色
    
    BTN_APPLY     = 0x2E7D32FF, -- 深绿 (Apply)
    BTN_APPLY_H   = 0x388E3CFF, -- 深绿高亮
    
    BTN_CLOSE     = 0xC62828FF, -- 深红 (Close)
    BTN_CLOSE_H   = 0xE53935FF, -- 亮红
    
    STATUS_BG     = 0x2D2D2DFF,
}

-- 数据存储与状态
local app_state = {
    merged_list = {},
    status_msg = "Welcome. Waiting for action...",
    filter_markers = true,
    filter_regions = true,
    last_paste_count = 0,
    user_wants_close = false -- 控制关闭状态
}

---------------------------------------------------------
-- 核心逻辑
---------------------------------------------------------

function ReloadProjectData()
    app_state.merged_list = {}
    local ret, num_markers, num_regions = r.CountProjectMarkers(0)
    
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers3(0, i)
        if retval ~= 0 then
            local type_str = isrgn and "Region" or "Marker"
            table.insert(app_state.merged_list, {
                index = i,
                id = markrgnindexnumber,
                type_str = type_str,
                current_name = name,
                new_name = name,
                isrgn = isrgn,
                pos = pos,
                rgnend = rgnend,
                status = "same"
            })
        end
    end
    app_state.status_msg = string.format("Loaded %d items from project.", #app_state.merged_list)
end

function ActionCopyOriginal()
    local str = ""
    local count = 0
    
    for _, item in ipairs(app_state.merged_list) do
        -- 检查筛选可见性
        local is_visible = false
        if item.type_str == "Marker" and app_state.filter_markers then is_visible = true end
        if item.type_str == "Region" and app_state.filter_regions then is_visible = true end
        
        if is_visible then
            str = str .. string.format("[%d] %s : %s\n", item.id, item.type_str, item.current_name)
            count = count + 1
        end
    end
    
    if count == 0 then
        app_state.status_msg = "Warning: No visible items to copy!"
        return
    end
    
    r.CF_SetClipboard(str)
    app_state.status_msg = string.format("Success: Copied %d VISIBLE items to clipboard.", count)
end

function ActionSmartPaste()
    local clipboard = r.CF_GetClipboard()
    if clipboard == "" then app_state.status_msg = "Clipboard is empty!" return end

    local match_count = 0
    local lookup = {}
    for _, item in ipairs(app_state.merged_list) do
        lookup[item.type_str .. "_" .. item.id] = item
    end

    for line in clipboard:gmatch("([^\r\n]*)\r?\n?") do
        if line ~= "" then
            local id_str, type_raw, content = line:match("%[(%d+)%]%s*(%a+)%s*[:：]%s*(.*)")
            if id_str and type_raw then
                local type_key = (type_raw:lower():sub(1,1) == "r") and "Region" or "Marker"
                local target = lookup[type_key .. "_" .. tonumber(id_str)]
                
                if target and target.new_name ~= content then
                    target.new_name = content
                    target.status = "changed"
                    match_count = match_count + 1
                end
            end
        end
    end
    app_state.last_paste_count = match_count
    app_state.status_msg = string.format("Smart Paste: Updated %d items.", match_count)
end

function ActionApply()
    r.Undo_BeginBlock()
    local update_count = 0
    local ret, num_markers, num_regions = r.CountProjectMarkers(0)
    
    local current_map = {}
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, _, _, _, markrgnindexnumber = r.EnumProjectMarkers3(0, i)
        local t = isrgn and "Region" or "Marker"
        current_map[t .. "_" .. markrgnindexnumber] = i
    end

    for _, item in ipairs(app_state.merged_list) do
        if item.status == "changed" then
            local key = item.type_str .. "_" .. item.id
            local idx = current_map[key]
            if idx then
                r.SetProjectMarkerByIndex(0, idx, item.isrgn, item.pos, item.rgnend, item.id, item.new_name, 0)
                update_count = update_count + 1
                item.current_name = item.new_name
                item.status = "same"
            end
        end
    end
    
    r.Undo_EndBlock("Batch Translate Markers", -1)
    r.UpdateArrange()
    app_state.status_msg = string.format("Done! Applied changes to %d items.", update_count)
    ReloadProjectData()
end

---------------------------------------------------------
-- UI 辅助绘制
---------------------------------------------------------
function PushBtnStyle(color_code)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color_code)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color_code + 0x11111100)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), color_code - 0x11111100)
end

function PopBtnStyle()
    r.ImGui_PopStyleColor(ctx, 3)
end

---------------------------------------------------------
-- 主循环
---------------------------------------------------------

function Loop()
    -- 全局样式：增加间距，让按钮更大
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 12)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 6) -- 增加内部填充，让按钮变胖

    local visible, open = r.ImGui_Begin(ctx, 'Marker/Region Translator Pro', true, r.ImGui_WindowFlags_None())
    
    if visible then
        
        -- === 1. 顶部工具栏 ===
        PushBtnStyle(COLORS.BTN_COPY)
        if r.ImGui_Button(ctx, " Copy List ") then ActionCopyOriginal() end
        PopBtnStyle()
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy VISIBLE names to clipboard") end

        r.ImGui_SameLine(ctx)
        
        PushBtnStyle(COLORS.BTN_PASTE)
        if r.ImGui_Button(ctx, " Paste Translated ") then ActionSmartPaste() end
        PopBtnStyle()
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Match and paste by [ID]") end

        r.ImGui_SameLine(ctx)

        PushBtnStyle(COLORS.BTN_REFRESH)
        if r.ImGui_Button(ctx, " Refresh ") then ReloadProjectData() end
        PopBtnStyle()

        -- 筛选器 (右对齐)
        local window_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_SameLine(ctx, window_width - 170)
        
        r.ImGui_Text(ctx, "View:")
        r.ImGui_SameLine(ctx)
        local _, v_m = r.ImGui_Checkbox(ctx, "M", app_state.filter_markers)
        if _ then app_state.filter_markers = v_m end
        
        r.ImGui_SameLine(ctx)
        local _, v_r = r.ImGui_Checkbox(ctx, "R", app_state.filter_regions)
        if _ then app_state.filter_regions = v_r end

        -- === 2. 状态栏 ===
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COLORS.STATUS_BG)
        local c_flags = r.ImGui_ChildFlags_None and r.ImGui_ChildFlags_None() or 0
        if r.ImGui_BeginChild(ctx, "status_bar", 0, 28, c_flags) then -- 稍微加高状态栏
            r.ImGui_Dummy(ctx, 0, 2) -- 垂直居中微调
            r.ImGui_SameLine(ctx)
            r.ImGui_TextColored(ctx, 0xFFD700FF, app_state.status_msg)
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_PopStyleColor(ctx)
        
        r.ImGui_Separator(ctx)

        -- === 3. 主列表 ===
        -- 留出底部按钮空间 (高度增加到 55 以容纳大按钮)
        local footer_height = 55
        local child_flags = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 1 
        
        if r.ImGui_BeginChild(ctx, "list_area", 0, -footer_height, child_flags) then
            
            local t_flags = r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_Resizable() | r.ImGui_TableFlags_ScrollY()
            
            if r.ImGui_BeginTable(ctx, 'main_table', 4, t_flags) then
                
                r.ImGui_TableSetupColumn(ctx, 'ID', r.ImGui_TableColumnFlags_WidthFixed(), 40)
                r.ImGui_TableSetupColumn(ctx, 'Original Name', r.ImGui_TableColumnFlags_WidthStretch(), 1)
                r.ImGui_TableSetupColumn(ctx, 'Translation (Edit)', r.ImGui_TableColumnFlags_WidthStretch(), 1.2)
                r.ImGui_TableSetupColumn(ctx, 'State', r.ImGui_TableColumnFlags_WidthFixed(), 40)
                r.ImGui_TableHeadersRow(ctx)

                for i, item in ipairs(app_state.merged_list) do
                    local show = (item.type_str == "Marker" and app_state.filter_markers) or (item.type_str == "Region" and app_state.filter_regions)
                    
                    if show then
                        r.ImGui_TableNextRow(ctx)
                        
                        -- ID
                        r.ImGui_TableSetColumnIndex(ctx, 0)
                        local icon = (item.type_str == "Marker") and "M" or "R"
                        local id_col = (item.type_str == "Marker") and COLORS.TEXT_ID_M or COLORS.TEXT_ID_R
                        r.ImGui_TextColored(ctx, id_col, string.format("%d %s", item.id, icon))
                        
                        -- Original
                        r.ImGui_TableSetColumnIndex(ctx, 1)
                        r.ImGui_TextColored(ctx, COLORS.TEXT_DIM, item.current_name)
                        
                        -- New Name
                        r.ImGui_TableSetColumnIndex(ctx, 2)
                        r.ImGui_PushID(ctx, i)
                        
                        local input_col = COLORS.TEXT_NORMAL
                        if item.status == "changed" then input_col = COLORS.TEXT_MODIFIED end
                        
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), input_col)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        
                        local changed, new_val = r.ImGui_InputText(ctx, "##edit", item.new_name, r.ImGui_InputTextFlags_AutoSelectAll())
                        if changed then
                            item.new_name = new_val
                            item.status = (item.new_name ~= item.current_name) and "changed" or "same"
                        end
                        r.ImGui_PopStyleColor(ctx)
                        r.ImGui_PopID(ctx)
                        
                        -- Status
                        r.ImGui_TableSetColumnIndex(ctx, 3)
                        if item.status == "changed" then
                            r.ImGui_TextColored(ctx, COLORS.TEXT_MODIFIED, "MOD")
                        end
                    end
                end
                r.ImGui_EndTable(ctx)
            end
            r.ImGui_EndChild(ctx)
        end
        
        -- === 4. 底部按钮区 (Bottom Buttons) ===
        r.ImGui_Dummy(ctx, 0, 4) -- 间距
        
        local changes_count = 0
        for _, v in ipairs(app_state.merged_list) do if v.status == "changed" then changes_count = changes_count + 1 end end
        
        local btn_height = 40 -- 按钮高度统一设定
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)

        if changes_count > 0 then
            -- 场景 A: 有修改 -> [ Apply (Green) ] [ Close (Red) ]
            local w_apply = avail_w * 0.75 -- Apply 占 75%
            local w_close = -1             -- Close 占剩余空间
            
            -- Apply Button
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.BTN_APPLY)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.BTN_APPLY_H)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.BTN_APPLY)
            if r.ImGui_Button(ctx, "APPLY " .. changes_count .. " CHANGES", w_apply, btn_height) then
                ActionApply()
            end
            r.ImGui_PopStyleColor(ctx, 3)
            
            r.ImGui_SameLine(ctx)
            
            -- Close Button (Small Red)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.BTN_CLOSE)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.BTN_CLOSE_H)
            if r.ImGui_Button(ctx, "CLOSE", w_close, btn_height) then
                app_state.user_wants_close = true
            end
            r.ImGui_PopStyleColor(ctx, 2)
            
        else
            -- 场景 B: 无修改 -> [ CLOSE SCRIPT (Red, Full Width) ]
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.BTN_CLOSE)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.BTN_CLOSE_H)
            
            if r.ImGui_Button(ctx, "CLOSE SCRIPT", -1, btn_height) then
                app_state.user_wants_close = true
            end
            
            r.ImGui_PopStyleColor(ctx, 2)
        end
        
        r.ImGui_End(ctx)
    end
    
    r.ImGui_PopStyleVar(ctx, 3)

    if open and not app_state.user_wants_close then
        r.defer(Loop)
    end
end

if not reaper.APIExists('ImGui_GetVersion') then
    reaper.ShowMessageBox("Please install 'ReaImGui' via ReaPack.", "Dependency Error", 0)
else
    ReloadProjectData()
    r.defer(Loop)
end
