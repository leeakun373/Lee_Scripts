-- @description ImGui Marker/Region Translator Pro (v10.0 Layout Perfected)
-- @version 10.0
-- @author Gemini Partner
-- @about
--   Layout Overhaul: 
--     1. Filters moved to top sub-header (replacing old log).
--     2. Status Log moved to window footer.
--     3. Column widths optimized: Preview gets more space.

local r = reaper
local ctx = r.ImGui_CreateContext('MarkerTranslatorPro')

-- =========================================================
-- 1. 核心配置
-- =========================================================
local CSV_FILENAME = "ucs_data.csv"
local SEPARATOR = "_"
local DEFAULT_UCS_MODE = false 

-- 智能匹配权重
local WEIGHTS = {
    CATEGORY    = 20,
    SUBCATEGORY = 60,
    SYNONYM     = 40,
    DESCRIPTION = 10,
    PERFECT_BONUS = 30
}
local MATCH_THRESHOLD = 15

local DOWNGRADE_WORDS = {
    ["small"] = true, ["medium"] = true, ["large"] = true, ["big"] = true, ["tiny"] = true,
    ["fast"] = true, ["slow"] = true, ["heavy"] = true, ["light"] = true,
    ["long"] = true, ["short"] = true, ["high"] = true, ["low"] = true,
    ["soft"] = true, ["hard"] = true, ["wet"] = true, ["dry"] = true,
    ["general"] = true, ["misc"] = true, ["miscellaneous"] = true,
    ["indoor"] = true, ["outdoor"] = true, ["exterior"] = true, ["interior"] = true
}

local COLORS = {
    TEXT_NORMAL   = 0xEEEEEEFF,
    TEXT_DIM      = 0x888888FF,
    TEXT_MODIFIED = 0x4DB6ACFF, 
    TEXT_AUTO     = 0xFFCA28FF, 
    ID_MARKER     = 0x90A4AEFF,
    ID_REGION     = 0x7986CBFF,
    
    BTN_COPY      = 0x42A5F5AA, 
    BTN_PASTE     = 0xFFA726AA, 
    BTN_REFRESH   = 0x666666AA,
    BTN_APPLY     = 0x2E7D32FF,
    BTN_AUTO      = 0xFFB300AA,
    
    BTN_MODE_ON   = 0x7E57C2AA, 
    BTN_MODE_OFF  = 0x555555AA, 
    
    BG_ROW_ALT    = 0xFFFFFF0D,
}

-- =========================================================
-- 2. 数据结构
-- =========================================================
local ucs_db = {
    flat_list = {},
    id_lookup = {},
    tree_data = {},
    categories_zh = {}
}

local app_state = {
    merged_list = {},
    status_msg = "Initializing...",
    filter_markers = true,
    filter_regions = true,
    use_ucs_mode = DEFAULT_UCS_MODE
}

---------------------------------------------------------
-- 3. 基础工具 & CSV 解析
---------------------------------------------------------
function GetScriptPath()
    local info = debug.getinfo(1, 'S');
    return info.source:match[[^@?(.*[\/])[^\/]-$]]
end

function ParseCSVLine(s)
    s = s .. ','        
    local t = {}        
    local fieldstart = 1
    repeat
        if string.find(s, '^"', fieldstart) then
            local a, c
            local i  = fieldstart
            repeat
                a, i, c = string.find(s, '"("?)', i+1)
            until c ~= '"' 
            if not i then break end
            local f = string.sub(s, fieldstart+1, i-1)
            table.insert(t, (string.gsub(f, '""', '"')))
            fieldstart = string.find(s, ',', i) + 1
        else
            local nexti = string.find(s, ',', fieldstart)
            table.insert(t, string.sub(s, fieldstart, nexti-1))
            fieldstart = nexti + 1
        end
    until fieldstart > string.len(s)
    return t
end

function Tokenize(str)
    local tokens = {}
    if not str then return tokens end
    for word in str:lower():gmatch("[%w\128-\255]+") do
        table.insert(tokens, word)
    end
    return tokens
end

---------------------------------------------------------
-- 4. 数据加载
---------------------------------------------------------
function LoadUCSData()
    local path = GetScriptPath() .. CSV_FILENAME
    local file = io.open(path, "r")
    
    if not file then
        app_state.status_msg = "Note: " .. CSV_FILENAME .. " not found (UCS disabled)."
        return false
    end

    ucs_db.flat_list = {}
    ucs_db.tree_data = {}
    ucs_db.id_lookup = {}
    ucs_db.categories_zh = {}
    
    local cat_seen = {}
    local is_header = true

    for line in file:lines() do
        if is_header then
            is_header = false
        else
            local cols = ParseCSVLine(line)
            if #cols >= 8 then
                local d = {
                    id      = cols[3], 
                    cat_en  = Tokenize(cols[1]),
                    sub_en  = Tokenize(cols[2]),
                    desc    = Tokenize(cols[5]),
                    syn_en  = Tokenize(cols[6]),
                    cat_zh  = cols[7], 
                    sub_zh  = cols[8], 
                    syn_zh  = Tokenize(cols[9]),
                    raw_cat_zh = cols[7],
                    raw_sub_zh = cols[8]
                }
                
                if d.id and d.id ~= "" then
                    table.insert(ucs_db.flat_list, d)
                    ucs_db.id_lookup[d.id] = { cat = d.raw_cat_zh, sub = d.raw_sub_zh }

                    if d.raw_cat_zh and d.raw_cat_zh ~= "" then
                        if not ucs_db.tree_data[d.raw_cat_zh] then
                            ucs_db.tree_data[d.raw_cat_zh] = {}
                            if not cat_seen[d.raw_cat_zh] then
                                table.insert(ucs_db.categories_zh, d.raw_cat_zh)
                                cat_seen[d.raw_cat_zh] = true
                            end
                        end
                        local sub_key = (d.raw_sub_zh and d.raw_sub_zh ~= "") and d.raw_sub_zh or "(General)"
                        ucs_db.tree_data[d.raw_cat_zh][sub_key] = d.id
                    end
                end
            end
        end
    end
    file:close()
    app_state.status_msg = string.format("Engine Ready: Loaded %d UCS definitions.", #ucs_db.flat_list)
    return true
end

---------------------------------------------------------
-- 5. 智能逻辑
---------------------------------------------------------
function FindBestUCS(user_input)
    if not user_input or user_input == "" then return nil end
    local input_words = Tokenize(user_input)
    if #input_words == 0 then return nil end

    local best_score = 0
    local best_match = nil

    for _, item in ipairs(ucs_db.flat_list) do
        local current_score = 0
        local cat_hit, sub_hit = false, false

        for _, word in ipairs(input_words) do
            if #word > 1 then 
                local is_weak_word = DOWNGRADE_WORDS[word] == true
                
                for _, k in ipairs(item.sub_en) do
                    if k == word then 
                        if is_weak_word then current_score = current_score + 5
                        else current_score = current_score + WEIGHTS.SUBCATEGORY; sub_hit = true end
                    elseif k:find(word, 1, true) then current_score = current_score + 10 end
                end
                
                for _, k in ipairs(item.syn_en) do
                    if k == word then 
                        if is_weak_word then current_score = current_score + 2
                        else current_score = current_score + WEIGHTS.SYNONYM; sub_hit = true end
                    end
                end
                
                for _, k in ipairs(item.cat_en) do
                    if k == word then current_score = current_score + WEIGHTS.CATEGORY; cat_hit = true end
                end
                
                for _, k in ipairs(item.desc) do
                    if k == word then current_score = current_score + WEIGHTS.DESCRIPTION end
                end
            end
        end

        if cat_hit and sub_hit then current_score = current_score + WEIGHTS.PERFECT_BONUS end

        if current_score > best_score then
            best_score = current_score
            best_match = item
        end
    end

    if best_score >= MATCH_THRESHOLD then return best_match end
    return nil
end

function UpdateFinalName(item)
    if app_state.use_ucs_mode and item.ucs_cat_id and item.ucs_cat_id ~= "" then
        item.new_name = item.ucs_cat_id .. SEPARATOR .. item.trans_name
    else
        item.new_name = item.trans_name
    end
    
    if item.new_name ~= item.current_name then
        item.status = "changed"
    else
        item.status = "same"
    end
end

function SyncFromID(item)
    local info = ucs_db.id_lookup[item.ucs_cat_id]
    if info then
        item.cat_zh_sel = info.cat
        item.sub_zh_sel = info.sub
    end
    UpdateFinalName(item)
end

function AutoMatchItem(item)
    if #ucs_db.flat_list > 0 then
        local match = FindBestUCS(item.trans_name)
        if match then
            item.ucs_cat_id = match.id
            item.cat_zh_sel = match.raw_cat_zh
            item.sub_zh_sel = match.raw_sub_zh
            item.match_type = "auto"
            SyncFromID(item)
        else
            item.match_type = ""
        end
    end
    UpdateFinalName(item)
end

function UpdateAllItemsMode()
    for _, item in ipairs(app_state.merged_list) do
        UpdateFinalName(item)
    end
end

---------------------------------------------------------
-- 6. 工程交互
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
                trans_name = name,
                cat_zh_sel = "",
                sub_zh_sel = "",
                ucs_cat_id = "",
                match_type = "",
                new_name = name,
                isrgn = isrgn,
                pos = pos,
                rgnend = rgnend,
                status = "same"
            })
        end
    end
    if app_state.status_msg == "Initializing..." then
        app_state.status_msg = "Project loaded."
    end
end

function ActionSmartPaste()
    local clipboard = r.CF_GetClipboard()
    if clipboard == "" then return end
    local match_count = 0
    local lookup = {}
    for idx, item in ipairs(app_state.merged_list) do
        lookup[item.type_str .. "_" .. item.id] = idx
    end

    for line in clipboard:gmatch("([^\r\n]*)\r?\n?") do
        if line ~= "" then
            local id_str, type_raw, content = line:match("%[(%d+)%]%s*(%a+)%s*[:：]%s*(.*)")
            if id_str and type_raw then
                local type_key = (type_raw:lower():sub(1,1) == "r") and "Region" or "Marker"
                local idx = lookup[type_key .. "_" .. tonumber(id_str)]
                
                if idx then
                    local item = app_state.merged_list[idx]
                    item.trans_name = content
                    if #ucs_db.flat_list > 0 then AutoMatchItem(item) else UpdateFinalName(item) end
                    match_count = match_count + 1
                end
            end
        end
    end
    app_state.status_msg = string.format("Paste: Updated %d items.", match_count)
end

function ActionApply()
    r.Undo_BeginBlock()
    local update_count = 0
    local current_map = {}
    local ret, num_markers, num_regions = r.CountProjectMarkers(0)
    for i = 0, num_markers + num_regions - 1 do
        local _, isrgn, _, _, _, markrgnindexnumber = r.EnumProjectMarkers3(0, i)
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
    ReloadProjectData()
end

function ActionCopyOriginal()
    local str = ""
    local count = 0
    for _, item in ipairs(app_state.merged_list) do
        local is_visible = (item.type_str == "Marker" and app_state.filter_markers) or (item.type_str == "Region" and app_state.filter_regions)
        if is_visible then
            str = str .. string.format("[%d] %s : %s\n", item.id, item.type_str, item.current_name)
            count = count + 1
        end
    end
    r.CF_SetClipboard(str)
    app_state.status_msg = string.format("Copied %d visible items.", count)
end

---------------------------------------------------------
-- 7. UI 渲染
---------------------------------------------------------
function PushBtnStyle(color_code)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color_code)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color_code + 0x11111100)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), color_code - 0x11111100)
end

function Loop()
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 4, 6)

    r.ImGui_SetNextWindowSize(ctx, 900, 600, r.ImGui_Cond_FirstUseEver())

    local visible, open = r.ImGui_Begin(ctx, 'Marker/Region Translator Pro v10.0', true, r.ImGui_WindowFlags_None())
    
    if visible then
        -- [Top Toolbar: Buttons Only]
        PushBtnStyle(COLORS.BTN_COPY)
        if r.ImGui_Button(ctx, " Copy List ") then ActionCopyOriginal() end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_SameLine(ctx)
        
        PushBtnStyle(COLORS.BTN_PASTE)
        if r.ImGui_Button(ctx, " Paste ") then ActionSmartPaste() end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_SameLine(ctx)

        PushBtnStyle(COLORS.BTN_REFRESH)
        if r.ImGui_Button(ctx, " Refresh ") then ReloadProjectData() end
        r.ImGui_PopStyleColor(ctx, 3)
        
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, "|")
        r.ImGui_SameLine(ctx)

        local ucs_btn_col = app_state.use_ucs_mode and COLORS.BTN_MODE_ON or COLORS.BTN_MODE_OFF
        local ucs_btn_txt = app_state.use_ucs_mode and "UCS Mode: ON" or "UCS Mode: OFF"
        PushBtnStyle(ucs_btn_col)
        if r.ImGui_Button(ctx, ucs_btn_txt) then
            app_state.use_ucs_mode = not app_state.use_ucs_mode
            UpdateAllItemsMode()
        end
        r.ImGui_PopStyleColor(ctx, 3)

        -- [Sub Toolbar: Filters] (Previously Status Bar)
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "View Filter:")
        r.ImGui_SameLine(ctx)
        local _, v_m = r.ImGui_Checkbox(ctx, "Markers [M]", app_state.filter_markers)
        if _ then app_state.filter_markers = v_m end
        r.ImGui_SameLine(ctx)
        local _, v_r = r.ImGui_Checkbox(ctx, "Regions [R]", app_state.filter_regions)
        if _ then app_state.filter_regions = v_r end
        
        -- [Table Area]
        -- 计算剩余高度：底部保留 60px (Apply) + 25px (Footer Status)
        local footer_h = 85
        local c_flags = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 1
        if r.ImGui_BeginChild(ctx, "table_area", 0, -footer_h, c_flags) then
            
            local table_id = app_state.use_ucs_mode and 'table_ucs_v10' or 'table_simple_v10'
            local t_flags = r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_Resizable() | r.ImGui_TableFlags_ScrollY() | r.ImGui_TableFlags_SizingStretchProp()
            local num_cols = app_state.use_ucs_mode and 6 or 4
            
            if r.ImGui_BeginTable(ctx, table_id, num_cols, t_flags) then
                
                -- [Column Weights Optimization]
                r.ImGui_TableSetupColumn(ctx, 'ID', r.ImGui_TableColumnFlags_WidthFixed(), 35)
                
                if app_state.use_ucs_mode then
                    r.ImGui_TableSetupColumn(ctx, 'Category (ZH)', r.ImGui_TableColumnFlags_WidthFixed(), 90)
                    r.ImGui_TableSetupColumn(ctx, 'SubCategory (ZH)', r.ImGui_TableColumnFlags_WidthFixed(), 90)
                    r.ImGui_TableSetupColumn(ctx, 'CatID', r.ImGui_TableColumnFlags_WidthFixed(), 95) -- [v10] Reduced
                end
                
                -- [v10] Balanced Weights: Translation 1.0 vs Preview 2.0
                r.ImGui_TableSetupColumn(ctx, 'Translation', r.ImGui_TableColumnFlags_WidthStretch(), 1.0)
                
                if app_state.use_ucs_mode then
                    r.ImGui_TableSetupColumn(ctx, 'Preview', r.ImGui_TableColumnFlags_WidthStretch(), 2.0) -- More space!
                else
                    r.ImGui_TableSetupColumn(ctx, 'Preview', r.ImGui_TableColumnFlags_WidthStretch(), 1.5)
                end
                
                r.ImGui_TableHeadersRow(ctx)

                for i, item in ipairs(app_state.merged_list) do
                    local show = (item.type_str == "Marker" and app_state.filter_markers) or (item.type_str == "Region" and app_state.filter_regions)
                    
                    if show then
                        r.ImGui_PushID(ctx, i)
                        r.ImGui_TableNextRow(ctx)
                        
                        -- Col: ID
                        r.ImGui_TableSetColumnIndex(ctx, 0)
                        local id_col = (item.type_str == "Marker") and COLORS.ID_MARKER or COLORS.ID_REGION
                        r.ImGui_TextColored(ctx, id_col, tostring(item.id))
                        
                        if app_state.use_ucs_mode then
                            -- UCS Columns
                            -- Col: Cat ZH
                            r.ImGui_TableSetColumnIndex(ctx, 1)
                            r.ImGui_SetNextItemWidth(ctx, -1)
                            local cat_lbl = (item.cat_zh_sel and item.cat_zh_sel ~= "") and item.cat_zh_sel or " "
                            if r.ImGui_BeginCombo(ctx, "##cat", cat_lbl) then
                                for _, cat in ipairs(ucs_db.categories_zh) do
                                    if r.ImGui_Selectable(ctx, cat .. "##c", item.cat_zh_sel == cat) then
                                        item.cat_zh_sel = cat
                                        item.sub_zh_sel = ""
                                        item.ucs_cat_id = ""
                                        UpdateFinalName(item)
                                    end
                                end
                                r.ImGui_EndCombo(ctx)
                            end

                            -- Col: Sub ZH
                            r.ImGui_TableSetColumnIndex(ctx, 2)
                            r.ImGui_SetNextItemWidth(ctx, -1)
                            local sub_lbl = (item.sub_zh_sel and item.sub_zh_sel ~= "") and item.sub_zh_sel or " "
                            if r.ImGui_BeginCombo(ctx, "##sub", sub_lbl) then
                                if item.cat_zh_sel ~= "" and ucs_db.tree_data[item.cat_zh_sel] then
                                    for sub, id in pairs(ucs_db.tree_data[item.cat_zh_sel]) do
                                        if r.ImGui_Selectable(ctx, sub .. "##" .. id, item.sub_zh_sel == sub) then
                                            item.sub_zh_sel = sub
                                            item.ucs_cat_id = id
                                            UpdateFinalName(item)
                                        end
                                    end
                                end
                                r.ImGui_EndCombo(ctx)
                            end

                            -- Col: CatID + Auto
                            r.ImGui_TableSetColumnIndex(ctx, 3)
                            r.ImGui_SetNextItemWidth(ctx, 60) -- 缩小输入框
                            local changed, new_id = r.ImGui_InputText(ctx, "##id", item.ucs_cat_id, r.ImGui_InputTextFlags_AutoSelectAll())
                            if changed then
                                item.ucs_cat_id = new_id
                                SyncFromID(item)
                            end
                            r.ImGui_SameLine(ctx)
                            PushBtnStyle(COLORS.BTN_AUTO)
                            if r.ImGui_Button(ctx, "Auto##btn") then AutoMatchItem(item) end
                            r.ImGui_PopStyleColor(ctx, 3)
                        end

                        -- Col: Translation
                        local col_idx = app_state.use_ucs_mode and 4 or 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local c2, new_nm = r.ImGui_InputText(ctx, "##nm", item.trans_name, r.ImGui_InputTextFlags_AutoSelectAll())
                        if c2 then
                            item.trans_name = new_nm
                            UpdateFinalName(item)
                        end

                        -- Col: Preview
                        col_idx = app_state.use_ucs_mode and 5 or 2
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        
                        local status_col = COLORS.TEXT_DIM
                        if item.status == "changed" then status_col = COLORS.TEXT_MODIFIED end
                        if app_state.use_ucs_mode and item.match_type == "auto" then status_col = COLORS.TEXT_AUTO end
                        
                        if app_state.use_ucs_mode then
                            r.ImGui_TextColored(ctx, status_col, item.new_name)
                        else
                            if item.status == "changed" then
                                r.ImGui_TextColored(ctx, COLORS.TEXT_MODIFIED, item.new_name)
                            else
                                r.ImGui_TextDisabled(ctx, "-")
                            end
                        end

                        r.ImGui_PopID(ctx)
                    end
                end
                r.ImGui_EndTable(ctx)
            end
            r.ImGui_EndChild(ctx)
        end

        -- [Bottom: Apply Button]
        r.ImGui_Dummy(ctx, 0, 4)
        local changes_count = 0
        for _, v in ipairs(app_state.merged_list) do if v.status == "changed" then changes_count = changes_count + 1 end end
        
        if changes_count > 0 then
            PushBtnStyle(COLORS.BTN_APPLY)
            if r.ImGui_Button(ctx, "APPLY " .. changes_count .. " CHANGES", -1, 40) then
                ActionApply()
            end
            r.ImGui_PopStyleColor(ctx, 3)
        else
            r.ImGui_BeginDisabled(ctx)
            r.ImGui_Button(ctx, "NO CHANGES", -1, 40)
            r.ImGui_EndDisabled(ctx)
        end

        -- [Footer: Status Log]
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0xAAAAAAFF, "Log: " .. app_state.status_msg)

        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 3)

    if open then r.defer(Loop) end
end

if not reaper.APIExists('ImGui_GetVersion') then
    reaper.ShowMessageBox("Please install 'ReaImGui' via ReaPack.", "Error", 0)
else
    LoadUCSData()
    ReloadProjectData()
    r.defer(Loop)
end
