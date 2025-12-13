--[[
  GUI module for UCS Rename Tools
  Handles all ImGui UI rendering and user interactions
]]

local GUI = {}
local r = reaper

-- Main UI loop
function GUI.Loop(ctx, modules)
    -- Extract module dependencies
    local Constants = modules.Constants
    local Theme = modules.Theme
    local Helpers = modules.Helpers
    local NameProcessor = modules.NameProcessor
    local ProjectActions = modules.ProjectActions
    local UCSMatcher = modules.UCSMatcher
    local ucs_db = modules.ucs_db
    local app_state = modules.app_state
    local script_path = modules.script_path
    
    -- Apply modern theme
    local pop_vars, pop_cols = Theme.PushModernSlateTheme(ctx)
    
    r.ImGui_SetNextWindowSize(ctx, 900, 600, r.ImGui_Cond_FirstUseEver())
    
    local window_title = string.format('UCS Toolkit v%s - %s', Constants.VERSION, Constants.VERSION_DESC)
    local visible, open = r.ImGui_Begin(ctx, window_title, true, r.ImGui_WindowFlags_None())
    
    if visible then
        -- [Top Toolbar: Buttons Only]
        if Theme.BtnNormal(ctx, "Copy List") then 
            ProjectActions.ActionCopyOriginal(app_state) 
        end
        r.ImGui_SameLine(ctx)
        
        if Theme.BtnNormal(ctx, "Paste") then 
            ProjectActions.ActionSmartPaste(app_state, ucs_db, NameProcessor, UCSMatcher, 
                Constants.WEIGHTS, Constants.MATCH_THRESHOLD, Constants.DOWNGRADE_WORDS, 
                Helpers, Constants.UCS_OPTIONAL_FIELDS, Constants.SAFE_DOMINANT_KEYWORDS) 
        end
        r.ImGui_SameLine(ctx)
        
        if Theme.BtnNormal(ctx, "Refresh") then 
            ProjectActions.ReloadProjectData(app_state, ucs_db, NameProcessor, Constants.UCS_OPTIONAL_FIELDS,
                UCSMatcher, Constants.WEIGHTS, Constants.MATCH_THRESHOLD, Constants.DOWNGRADE_WORDS, Helpers, Constants.SAFE_DOMINANT_KEYWORDS) 
        end
        r.ImGui_SameLine(ctx)
        
        if Theme.BtnAlias(ctx, "+ Alias") then
            r.ImGui_OpenPopup(ctx, "alias_editor_popup")
            -- Initialize alias input fields
            if not app_state.alias_source then app_state.alias_source = "" end
            if not app_state.alias_target then app_state.alias_target = "" end
            -- Smart prefill from selected row if available
            if app_state.selected_row_idx and app_state.merged_list[app_state.selected_row_idx] then
                local item = app_state.merged_list[app_state.selected_row_idx]
                app_state.alias_source = item.trans_name or ""
                -- Try to get subcategory as target
                if item.sub_zh_sel and item.sub_zh_sel ~= "" then
                    app_state.alias_target = item.sub_zh_sel
                elseif item.ucs_cat_id and item.ucs_cat_id ~= "" then
                    app_state.alias_target = item.ucs_cat_id
                else
                    app_state.alias_target = ""
                end
            end
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, "|")
        r.ImGui_SameLine(ctx)
        
        -- UCS Mode toggle button
        local ucs_btn_txt = app_state.use_ucs_mode and "UCS Mode: ON" or "UCS Mode: OFF"
        if Theme.BtnToggle(ctx, ucs_btn_txt, app_state.use_ucs_mode) then
            app_state.use_ucs_mode = not app_state.use_ucs_mode
            NameProcessor.UpdateAllItemsMode(app_state, Constants.UCS_OPTIONAL_FIELDS)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, "|")
        r.ImGui_SameLine(ctx)
        
        -- Language toggle button
        local lang_btn_txt = (app_state.display_language == "en") and "Language: EN" or "Language: 中文"
        if Theme.BtnToggle(ctx, lang_btn_txt, app_state.display_language == "en") then
            app_state.display_language = (app_state.display_language == "zh") and "en" or "zh"
        end
        
        -- Field visibility controls (only in UCS mode)
        if app_state.use_ucs_mode then
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, "|")
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Fields:")
            r.ImGui_SameLine(ctx)
            
            -- Force text to bright white for checkbox visibility
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
            
            -- VendorCategory
            local _, v1 = r.ImGui_Checkbox(ctx, "V##vendor", app_state.field_visibility.vendor_category)
            if _ then 
                app_state.field_visibility.vendor_category = v1
                if not v1 then 
                    NameProcessor.ClearHiddenFieldsAndUpdate(app_state, Constants.UCS_OPTIONAL_FIELDS) 
                end
            end
            r.ImGui_SameLine(ctx)
            
            -- CreatorID
            local _, v2 = r.ImGui_Checkbox(ctx, "C##creator", app_state.field_visibility.creator_id)
            if _ then 
                app_state.field_visibility.creator_id = v2
                if not v2 then 
                    NameProcessor.ClearHiddenFieldsAndUpdate(app_state, Constants.UCS_OPTIONAL_FIELDS) 
                end
            end
            r.ImGui_SameLine(ctx)
            
            -- SourceID
            local _, v3 = r.ImGui_Checkbox(ctx, "S##source", app_state.field_visibility.source_id)
            if _ then 
                app_state.field_visibility.source_id = v3
                if not v3 then 
                    NameProcessor.ClearHiddenFieldsAndUpdate(app_state, Constants.UCS_OPTIONAL_FIELDS) 
                end
            end
            r.ImGui_SameLine(ctx)
            
            -- UserData
            local _, v4 = r.ImGui_Checkbox(ctx, "U##user", app_state.field_visibility.user_data)
            if _ then 
                app_state.field_visibility.user_data = v4
                if not v4 then 
                    NameProcessor.ClearHiddenFieldsAndUpdate(app_state, Constants.UCS_OPTIONAL_FIELDS) 
                end
            end
            
            -- Restore text color
            r.ImGui_PopStyleColor(ctx, 1)
        end
        
        -- [Sub Toolbar: Filters]
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "View Filter:")
        r.ImGui_SameLine(ctx)
        local _, v_m = r.ImGui_Checkbox(ctx, "Markers [M]", app_state.filter_markers)
        if _ then app_state.filter_markers = v_m end
        r.ImGui_SameLine(ctx)
        local _, v_r = r.ImGui_Checkbox(ctx, "Regions [R]", app_state.filter_regions)
        if _ then app_state.filter_regions = v_r end
        
        -- [Table Area]
        local footer_h = 85
        local c_flags = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 1
        if r.ImGui_BeginChild(ctx, "table_area", 0, -footer_h, c_flags) then
            
            local table_id = app_state.use_ucs_mode and 'table_ucs_v10' or 'table_simple_v10'
            local t_flags = r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_Borders() | 
                           r.ImGui_TableFlags_Resizable() | r.ImGui_TableFlags_ScrollY() | 
                           r.ImGui_TableFlags_SizingFixedFit()
            
            -- Calculate column count dynamically
            local base_cols = app_state.use_ucs_mode and 7 or 5
            local optional_cols_count = 0
            if app_state.use_ucs_mode then
                if app_state.field_visibility.vendor_category then optional_cols_count = optional_cols_count + 1 end
                if app_state.field_visibility.creator_id then optional_cols_count = optional_cols_count + 1 end
                if app_state.field_visibility.source_id then optional_cols_count = optional_cols_count + 1 end
                if app_state.field_visibility.user_data then optional_cols_count = optional_cols_count + 1 end
            end
            local num_cols = base_cols + optional_cols_count
            
            if r.ImGui_BeginTable(ctx, table_id, num_cols, t_flags) then
                
                -- [Column Setup]
                r.ImGui_TableSetupColumn(ctx, 'ID', r.ImGui_TableColumnFlags_WidthFixed(), 35)
                
                if app_state.use_ucs_mode then
                    local cat_header = (app_state.display_language == "en") and "Category" or "分类"
                    local sub_header = (app_state.display_language == "en") and "SubCategory" or "子分类"
                    r.ImGui_TableSetupColumn(ctx, cat_header, r.ImGui_TableColumnFlags_WidthFixed(), 90)
                    r.ImGui_TableSetupColumn(ctx, sub_header, r.ImGui_TableColumnFlags_WidthFixed(), 90)
                    r.ImGui_TableSetupColumn(ctx, 'CatID', r.ImGui_TableColumnFlags_WidthFixed(), 95)
                end
                
                local orig_header = (app_state.display_language == "en") and "Original" or "原名"
                r.ImGui_TableSetupColumn(ctx, orig_header, r.ImGui_TableColumnFlags_WidthFixed(), 150)
                local replace_header = app_state.use_ucs_mode and 'FXName' or 'Replace'
                r.ImGui_TableSetupColumn(ctx, replace_header, r.ImGui_TableColumnFlags_WidthFixed(), 120)
                
                -- Optional field columns
                if app_state.use_ucs_mode then
                    if app_state.field_visibility.vendor_category then
                        r.ImGui_TableSetupColumn(ctx, 'VC', r.ImGui_TableColumnFlags_WidthFixed(), 70)
                    end
                    if app_state.field_visibility.creator_id then
                        r.ImGui_TableSetupColumn(ctx, 'CID', r.ImGui_TableColumnFlags_WidthFixed(), 70)
                    end
                    if app_state.field_visibility.source_id then
                        r.ImGui_TableSetupColumn(ctx, 'SID', r.ImGui_TableColumnFlags_WidthFixed(), 70)
                    end
                    if app_state.field_visibility.user_data then
                        r.ImGui_TableSetupColumn(ctx, 'UD', r.ImGui_TableColumnFlags_WidthFixed(), 70)
                    end
                end
                
                -- Preview column - takes up all remaining space
                r.ImGui_TableSetupColumn(ctx, 'Preview', r.ImGui_TableColumnFlags_WidthStretch(), 3.0)
                
                -- [Table Headers with Fill/Clear buttons]
                r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_Headers())
                
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_TableHeader(ctx, 'ID')
                
                if app_state.use_ucs_mode then
                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    local cat_header = (app_state.display_language == "en") and "Category" or "分类"
                    r.ImGui_TableHeader(ctx, cat_header)
                    
                    r.ImGui_TableSetColumnIndex(ctx, 2)
                    local sub_header = (app_state.display_language == "en") and "SubCategory" or "子分类"
                    r.ImGui_TableHeader(ctx, sub_header)
                    
                    r.ImGui_TableSetColumnIndex(ctx, 3)
                    r.ImGui_TableHeader(ctx, 'CatID')
                end
                
                local orig_header = (app_state.display_language == "en") and "Original" or "原名"
                r.ImGui_TableSetColumnIndex(ctx, app_state.use_ucs_mode and 4 or 1)
                r.ImGui_TableHeader(ctx, orig_header)
                
                r.ImGui_TableSetColumnIndex(ctx, app_state.use_ucs_mode and 5 or 2)
                local replace_header = app_state.use_ucs_mode and 'FXName' or 'Replace'
                r.ImGui_TableHeader(ctx, replace_header)
                
                -- Optional field headers with Fill/Clear buttons
                local col_idx = app_state.use_ucs_mode and 5 or 2
                if app_state.use_ucs_mode then
                    -- VendorCategory
                    if app_state.field_visibility.vendor_category then
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_PushID(ctx, "header_vc")
                        r.ImGui_Text(ctx, 'VC')
                        r.ImGui_SameLine(ctx, 0.0, 2.0)
                        if Theme.BtnSmall(ctx, "F") then
                            NameProcessor.FillFieldToAll("vendor_category", app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Fill Vendor Category to all visible items")
                        end
                        r.ImGui_SameLine(ctx, 0.0, 1.0)
                        if Theme.BtnSmall(ctx, "C") then
                            NameProcessor.ClearFieldToAll("vendor_category", app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Clear Vendor Category for all visible items")
                        end
                        r.ImGui_PopID(ctx)
                    end
                    
                    -- CreatorID
                    if app_state.field_visibility.creator_id then
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_PushID(ctx, "header_ci")
                        r.ImGui_Text(ctx, 'CID')
                        r.ImGui_SameLine(ctx, 0.0, 2.0)
                        if Theme.BtnSmall(ctx, "F") then
                            NameProcessor.FillFieldToAll("creator_id", app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Fill CreatorID to all visible items")
                        end
                        r.ImGui_SameLine(ctx, 0.0, 1.0)
                        if Theme.BtnSmall(ctx, "C") then
                            NameProcessor.ClearFieldToAll("creator_id", app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Clear CreatorID for all visible items")
                        end
                        r.ImGui_PopID(ctx)
                    end
                    
                    -- SourceID
                    if app_state.field_visibility.source_id then
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_PushID(ctx, "header_si")
                        r.ImGui_Text(ctx, 'SID')
                        r.ImGui_SameLine(ctx, 0.0, 2.0)
                        if Theme.BtnSmall(ctx, "F") then
                            NameProcessor.FillFieldToAll("source_id", app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Fill SourceID to all visible items")
                        end
                        r.ImGui_SameLine(ctx, 0.0, 1.0)
                        if Theme.BtnSmall(ctx, "C") then
                            NameProcessor.ClearFieldToAll("source_id", app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Clear SourceID for all visible items")
                        end
                        r.ImGui_PopID(ctx)
                    end
                    
                    -- UserData
                    if app_state.field_visibility.user_data then
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_PushID(ctx, "header_ud")
                        r.ImGui_Text(ctx, 'UD')
                        r.ImGui_SameLine(ctx, 0.0, 2.0)
                        if Theme.BtnSmall(ctx, "F") then
                            NameProcessor.FillFieldToAll("user_data", app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Fill User Data to all visible items")
                        end
                        r.ImGui_SameLine(ctx, 0.0, 1.0)
                        if Theme.BtnSmall(ctx, "C") then
                            NameProcessor.ClearFieldToAll("user_data", app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Clear User Data for all visible items")
                        end
                        r.ImGui_PopID(ctx)
                    end
                end
                
                -- Preview column header
                col_idx = col_idx + 1
                r.ImGui_TableSetColumnIndex(ctx, col_idx)
                r.ImGui_TableHeader(ctx, 'Preview')
                
                -- [Table Rows]
                for i, item in ipairs(app_state.merged_list) do
                    local show = (item.type_str == "Marker" and app_state.filter_markers) or (item.type_str == "Region" and app_state.filter_regions)
                    
                    if show then
                        r.ImGui_PushID(ctx, i)
                        r.ImGui_TableNextRow(ctx)
                        
                        -- Col: ID (Clickable)
                        r.ImGui_TableSetColumnIndex(ctx, 0)
                        local id_col = (item.type_str == "Marker") and Constants.COLORS.ID_MARKER or Constants.COLORS.ID_REGION
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000) -- 透明背景
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), id_col + 0x20000000) -- 悬停时高亮
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), id_col + 0x40000000) -- 点击时高亮
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), id_col) -- 文字颜色
                        if r.ImGui_Button(ctx, tostring(item.id), -1, 0) then
                            ProjectActions.JumpToMarkerOrRegion(item)
                            app_state.selected_row_idx = i  -- Track selected row for Alias prefill
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            local tooltip = string.format("点击跳转到 %s #%d", item.type_str, item.id)
                            if item.isrgn then
                                tooltip = tooltip .. string.format("\n位置: %.3f - %.3f", item.pos, item.rgnend)
                            else
                                tooltip = tooltip .. string.format("\n位置: %.3f", item.pos)
                            end
                            r.ImGui_SetTooltip(ctx, tooltip)
                        end
                        r.ImGui_PopStyleColor(ctx, 4)
                        
                        if app_state.use_ucs_mode then
                            -- UCS Columns - 根据语言切换显示
                            -- Col: Category (可搜索Combo)
                            r.ImGui_TableSetColumnIndex(ctx, 1)
                            r.ImGui_SetNextItemWidth(ctx, -1)
                            
                            -- 根据显示语言获取当前值和预览
                            local cat_display, cat_list, cat_selected
                            if app_state.display_language == "en" then
                                -- 英文模式：显示英文，但内部存储中文
                                local cat_en_sel = ""
                                if item.cat_zh_sel and item.cat_zh_sel ~= "" then
                                    -- zh_to_en[cat_zh] 是一个table，包含所有sub的映射
                                    -- 每个sub的映射都有cat字段，都是相同的英文category
                                    if ucs_db.zh_to_en[item.cat_zh_sel] then
                                        -- 如果有sub_zh_sel，直接使用它来获取
                                        if item.sub_zh_sel and item.sub_zh_sel ~= "" and ucs_db.zh_to_en[item.cat_zh_sel][item.sub_zh_sel] then
                                            cat_en_sel = ucs_db.zh_to_en[item.cat_zh_sel][item.sub_zh_sel].cat or ""
                                        else
                                            -- 否则从任意一个sub的映射中获取cat字段
                                            local first_sub_key = next(ucs_db.zh_to_en[item.cat_zh_sel])
                                            if first_sub_key and ucs_db.zh_to_en[item.cat_zh_sel][first_sub_key] then
                                                cat_en_sel = ucs_db.zh_to_en[item.cat_zh_sel][first_sub_key].cat or ""
                                            end
                                        end
                                    end
                                end
                                cat_display = (cat_en_sel ~= "") and cat_en_sel or (item.cat_input or "")
                                cat_list = ucs_db.categories_en
                                cat_selected = cat_en_sel
                            else
                                -- 中文模式
                                cat_display = (item.cat_zh_sel and item.cat_zh_sel ~= "") and item.cat_zh_sel or (item.cat_input or "")
                                cat_list = ucs_db.categories_zh
                                cat_selected = item.cat_zh_sel
                            end
                            
                            -- Editable Category: InputText + ArrowButton + Popup
                            r.ImGui_SetNextItemWidth(ctx, -25)  -- Leave space for arrow button
                            local cat_changed, new_cat = r.ImGui_InputText(ctx, "##cat_input_" .. i, cat_display or "", r.ImGui_InputTextFlags_None())
                            if cat_changed then
                                -- User typed directly - update the value
                                if app_state.display_language == "en" then
                                    -- Convert EN input to ZH for storage
                                    if ucs_db.en_to_zh[new_cat] then
                                        local first_sub_key = next(ucs_db.en_to_zh[new_cat])
                                        if first_sub_key and ucs_db.en_to_zh[new_cat][first_sub_key] then
                                            item.cat_zh_sel = ucs_db.en_to_zh[new_cat][first_sub_key].cat
                                        end
                                    else
                                        item.cat_zh_sel = new_cat  -- Store as-is if no match
                                    end
                                else
                                    item.cat_zh_sel = new_cat
                                end
                                item.sub_zh_sel = ""  -- Clear subcategory
                                item.ucs_cat_id = ""
                                NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                            end
                            
                            -- Arrow button to open dropdown
                            r.ImGui_SameLine(ctx, 0, 2)
                            local cat_popup_id = "cat_popup_" .. tostring(i)
                            if r.ImGui_ArrowButton(ctx, "##cat_arrow_" .. i, r.ImGui_Dir_Down()) then
                                r.ImGui_OpenPopup(ctx, cat_popup_id)
                                item.cat_input = cat_display or ""  -- Initialize search filter
                            end
                            
                            -- Popup list
                            if r.ImGui_BeginPopup(ctx, cat_popup_id) then
                                r.ImGui_Text(ctx, "Search:")
                                r.ImGui_SameLine(ctx)
                                r.ImGui_SetNextItemWidth(ctx, 200)
                                local filter_changed, new_filter = r.ImGui_InputText(ctx, "##cat_search_" .. i, item.cat_input or "", r.ImGui_InputTextFlags_AutoSelectAll())
                                if filter_changed then
                                    item.cat_input = new_filter
                                end
                                r.ImGui_Separator(ctx)
                                
                                -- Filter and display list
                                local has_any_match = false
                                for _, cat in ipairs(cat_list) do
                                    if not item.cat_input or item.cat_input == "" or Helpers.FilterMatch(item.cat_input, cat) then
                                        has_any_match = true
                                        local is_selected = (cat_selected == cat)
                                        if r.ImGui_Selectable(ctx, cat, is_selected) then
                                            item.cat_input = ""
                                            item.sub_zh_sel = ""
                                            item.sub_input = ""
                                            item.ucs_cat_id = ""
                                            -- Language conversion: EN selection -> ZH storage
                                            if app_state.display_language == "en" then
                                                if ucs_db.en_to_zh[cat] then
                                                    local first_sub_key = next(ucs_db.en_to_zh[cat])
                                                    if first_sub_key and ucs_db.en_to_zh[cat][first_sub_key] then
                                                        item.cat_zh_sel = ucs_db.en_to_zh[cat][first_sub_key].cat
                                                    end
                                                end
                                            else
                                                item.cat_zh_sel = cat
                                            end
                                            NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                            r.ImGui_CloseCurrentPopup(ctx)
                                        end
                                    end
                                end
                                
                                if not has_any_match then
                                    local no_match_text = (app_state.display_language == "en") and "No match" or "无匹配项"
                                    r.ImGui_TextDisabled(ctx, no_match_text)
                                end
                                
                                r.ImGui_EndPopup(ctx)
                            end

                            -- Col: SubCategory (Editable Combo)
                            r.ImGui_TableSetColumnIndex(ctx, 2)
                            
                            -- 根据显示语言获取当前值和预览
                            local sub_display, sub_tree_data, sub_selected
                            if app_state.display_language == "en" then
                                -- 英文模式
                                local sub_en_sel = ""
                                local cat_en_for_sub = ""
                                
                                if item.cat_zh_sel and item.cat_zh_sel ~= "" then
                                    if item.sub_zh_sel and item.sub_zh_sel ~= "" and ucs_db.zh_to_en[item.cat_zh_sel] and ucs_db.zh_to_en[item.cat_zh_sel][item.sub_zh_sel] then
                                        sub_en_sel = ucs_db.zh_to_en[item.cat_zh_sel][item.sub_zh_sel].sub or ""
                                        cat_en_for_sub = ucs_db.zh_to_en[item.cat_zh_sel][item.sub_zh_sel].cat or ""
                                    elseif ucs_db.zh_to_en[item.cat_zh_sel] then
                                        local first_sub_key = next(ucs_db.zh_to_en[item.cat_zh_sel])
                                        if first_sub_key and ucs_db.zh_to_en[item.cat_zh_sel][first_sub_key] then
                                            cat_en_for_sub = ucs_db.zh_to_en[item.cat_zh_sel][first_sub_key].cat or ""
                                        end
                                    end
                                end
                                
                                sub_display = (sub_en_sel ~= "") and sub_en_sel or (item.sub_input or "")
                                sub_tree_data = (cat_en_for_sub ~= "" and ucs_db.tree_data_en[cat_en_for_sub]) and ucs_db.tree_data_en[cat_en_for_sub] or nil
                                sub_selected = sub_en_sel
                            else
                                -- 中文模式
                                sub_display = (item.sub_zh_sel and item.sub_zh_sel ~= "") and item.sub_zh_sel or (item.sub_input or "")
                                sub_tree_data = (item.cat_zh_sel ~= "" and ucs_db.tree_data[item.cat_zh_sel]) and ucs_db.tree_data[item.cat_zh_sel] or nil
                                sub_selected = item.sub_zh_sel
                            end
                            
                            -- Editable SubCategory: InputText + ArrowButton + Popup
                            r.ImGui_SetNextItemWidth(ctx, -25)  -- Leave space for arrow button
                            local sub_changed, new_sub = r.ImGui_InputText(ctx, "##sub_input_" .. i, sub_display or "", r.ImGui_InputTextFlags_None())
                            if sub_changed then
                                -- User typed directly - try to find matching ID
                                if sub_tree_data then
                                    local found_id = nil
                                    for sub, id in pairs(sub_tree_data) do
                                        if sub == new_sub then
                                            found_id = id
                                            break
                                        end
                                    end
                                    if found_id then
                                        item.ucs_cat_id = found_id
                                        NameProcessor.SyncFromID(item, ucs_db, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                    else
                                        -- No exact match, store as-is
                                        item.sub_zh_sel = new_sub
                                        item.ucs_cat_id = ""
                                        NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                    end
                                end
                            end
                            
                            -- Arrow button to open dropdown
                            r.ImGui_SameLine(ctx, 0, 2)
                            local sub_popup_id = "sub_popup_" .. tostring(i)
                            if r.ImGui_ArrowButton(ctx, "##sub_arrow_" .. i, r.ImGui_Dir_Down()) then
                                r.ImGui_OpenPopup(ctx, sub_popup_id)
                                item.sub_input = sub_display or ""
                            end
                            
                            -- Popup list
                            if r.ImGui_BeginPopup(ctx, sub_popup_id) then
                                r.ImGui_Text(ctx, "Search:")
                                r.ImGui_SameLine(ctx)
                                r.ImGui_SetNextItemWidth(ctx, 200)
                                local filter_changed, new_filter = r.ImGui_InputText(ctx, "##sub_search_" .. i, item.sub_input or "", r.ImGui_InputTextFlags_AutoSelectAll())
                                if filter_changed then
                                    item.sub_input = new_filter
                                end
                                r.ImGui_Separator(ctx)
                                
                                if sub_tree_data then
                                    local has_any_match = false
                                    for sub, id in pairs(sub_tree_data) do
                                        if not item.sub_input or item.sub_input == "" or Helpers.FilterMatch(item.sub_input, sub) then
                                            has_any_match = true
                                            local is_selected = (sub_selected == sub)
                                            if r.ImGui_Selectable(ctx, sub, is_selected) then
                                                item.sub_input = ""
                                                item.ucs_cat_id = id
                                                NameProcessor.SyncFromID(item, ucs_db, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                                r.ImGui_CloseCurrentPopup(ctx)
                                            end
                                        end
                                    end
                                    
                                    if not has_any_match then
                                        local no_match_text = (app_state.display_language == "en") and "No match" or "无匹配项"
                                        r.ImGui_TextDisabled(ctx, no_match_text)
                                    end
                                else
                                    local no_cat_text = (app_state.display_language == "en") and "Select Category first" or "请先选择Category"
                                    r.ImGui_TextDisabled(ctx, no_cat_text)
                                end
                                
                                r.ImGui_EndPopup(ctx)
                            end

                            -- Col: CatID (只读) + Auto
                            r.ImGui_TableSetColumnIndex(ctx, 3)
                            r.ImGui_AlignTextToFramePadding(ctx)  -- Align text vertically with buttons
                            
                            -- 显示 CatID
                            if item.ucs_cat_id and item.ucs_cat_id ~= "" then
                                r.ImGui_TextColored(ctx, 0xBBBBBBFF, item.ucs_cat_id) -- 稍微暗一点的灰白
                            else
                                r.ImGui_TextDisabled(ctx, "-")
                            end
                            
                            r.ImGui_SameLine(ctx, 60.0, 4.0) -- 保持原来的位置
                            
                            -- 【修复】Auto 按钮：哑光琥珀色 + 文字居中
                            -- 1. 颜色：哑光琥珀色 (低调、高级)
                            local col_auto_bg  = 0xB45309FF -- 深琥珀色
                            local col_auto_hov = 0xD97706FF -- 悬停稍亮
                            
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col_auto_bg)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_auto_hov)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x92400EFF)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF) -- 强制白字
                            
                            -- 2. 修正文字位置：将垂直 Padding (第二个参数) 设为 0
                            -- 这样文字就会在 18px 的高度里自动垂直居中，不会偏上或偏下
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 0) 
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2) -- 小圆角
                            
                            -- 3. 绘制按钮 (宽 38, 高 17)
                            -- 高度给 17 或 18 像素，配合 Padding=0，文字绝对居中
                            if r.ImGui_Button(ctx, "Auto", 38, 17) then 
                                NameProcessor.AutoMatchItem(item, ucs_db, app_state, Constants.UCS_OPTIONAL_FIELDS, 
                                    UCSMatcher, Constants.WEIGHTS, Constants.MATCH_THRESHOLD, Constants.DOWNGRADE_WORDS, Helpers, Constants.SAFE_DOMINANT_KEYWORDS) 
                            end
                            
                            r.ImGui_PopStyleVar(ctx, 2)   -- 弹出 Padding 和 Rounding
                            r.ImGui_PopStyleColor(ctx, 4) -- 弹出颜色
                        end

                        -- Col: 原名 (Original Name) - 可编辑
                        local col_idx = app_state.use_ucs_mode and 4 or 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        
                        -- 非UCS模式下：添加EnterReturnsTrue标志以检测Enter键
                        local input_flags = r.ImGui_InputTextFlags_AutoSelectAll()
                        if not app_state.use_ucs_mode then
                            input_flags = input_flags | r.ImGui_InputTextFlags_EnterReturnsTrue()
                        end
                        
                        local c1, new_current = r.ImGui_InputText(ctx, "##current", item.current_name, input_flags)
                        if c1 then
                            local old_current = item.current_name
                            item.current_name = new_current
                            
                            if app_state.use_ucs_mode then
                                -- UCS模式：保持原有逻辑
                                -- 如果trans_name和原current_name相同，也同步更新trans_name
                                if item.trans_name == old_current then
                                    item.trans_name = new_current
                                end
                                
                                -- 如果new_name和原current_name相同，也同步更新new_name
                                if item.new_name == old_current then
                                    item.new_name = new_current
                                end
                                
                                -- 更新状态
                                NameProcessor.UpdateItemStatus(item)
                            else
                                -- 非UCS模式：直接作为命名工具使用
                                -- 将trans_name同步为新的current_name，这样Preview会显示新名称
                                item.trans_name = new_current
                                -- 更新最终名称（在非UCS模式下，new_name = trans_name）
                                NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                -- 立即应用到工程（Enter键或失去焦点时）
                                ProjectActions.ApplySingleName(item)
                            end
                        end
                        
                        -- 非UCS模式下：检测失去焦点（编辑完成后），立即应用到工程
                        if not app_state.use_ucs_mode and r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
                            ProjectActions.ApplySingleName(item)
                        end

                        -- Col: Replace/FXName (用户粘贴的结果)
                        col_idx = app_state.use_ucs_mode and 5 or 2
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local c2, new_nm = r.ImGui_InputText(ctx, "##nm", item.trans_name, r.ImGui_InputTextFlags_AutoSelectAll())
                        if c2 then
                            item.trans_name = new_nm
                            -- 修改Replace/FXName时，Preview自动跟着更新
                            NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                        end

                        -- 可选字段列（动态添加）
                        if app_state.use_ucs_mode then
                            -- VendorCategory
                            if app_state.field_visibility.vendor_category then
                                col_idx = col_idx + 1
                                r.ImGui_TableSetColumnIndex(ctx, col_idx)
                                r.ImGui_SetNextItemWidth(ctx, -1)
                                local changed_vc, new_vc = r.ImGui_InputText(ctx, "##vc_" .. i, item.vendor_category or "", r.ImGui_InputTextFlags_AutoSelectAll())
                                if changed_vc then
                                    local valid, error_msg = NameProcessor.ValidateField("vendor_category", new_vc, Constants.UCS_OPTIONAL_FIELDS)
                                    item.vendor_category = new_vc
                                    NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                    if not valid then
                                        app_state.status_msg = error_msg
                                    end
                                end
                                -- 显示验证错误tooltip
                                if r.ImGui_IsItemHovered(ctx) and item.vendor_category and item.vendor_category ~= "" then
                                    local valid, error_msg = NameProcessor.ValidateField("vendor_category", item.vendor_category, Constants.UCS_OPTIONAL_FIELDS)
                                    if not valid then
                                        r.ImGui_SetTooltip(ctx, error_msg)
                                    end
                                end
                            end
                            
                            -- CreatorID
                            if app_state.field_visibility.creator_id then
                                col_idx = col_idx + 1
                                r.ImGui_TableSetColumnIndex(ctx, col_idx)
                                r.ImGui_SetNextItemWidth(ctx, -1)
                                local changed_ci, new_ci = r.ImGui_InputText(ctx, "##ci_" .. i, item.creator_id or "", r.ImGui_InputTextFlags_AutoSelectAll())
                                if changed_ci then
                                    local valid, error_msg = NameProcessor.ValidateField("creator_id", new_ci, Constants.UCS_OPTIONAL_FIELDS)
                                    item.creator_id = new_ci
                                    NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                    if not valid then
                                        app_state.status_msg = error_msg
                                    end
                                end
                                if r.ImGui_IsItemHovered(ctx) and item.creator_id and item.creator_id ~= "" then
                                    local valid, error_msg = NameProcessor.ValidateField("creator_id", item.creator_id, Constants.UCS_OPTIONAL_FIELDS)
                                    if not valid then
                                        r.ImGui_SetTooltip(ctx, error_msg)
                                    end
                                end
                            end
                            
                            -- SourceID
                            if app_state.field_visibility.source_id then
                                col_idx = col_idx + 1
                                r.ImGui_TableSetColumnIndex(ctx, col_idx)
                                r.ImGui_SetNextItemWidth(ctx, -1)
                                local changed_si, new_si = r.ImGui_InputText(ctx, "##si_" .. i, item.source_id or "", r.ImGui_InputTextFlags_AutoSelectAll())
                                if changed_si then
                                    local valid, error_msg = NameProcessor.ValidateField("source_id", new_si, Constants.UCS_OPTIONAL_FIELDS)
                                    item.source_id = new_si
                                    NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                    if not valid then
                                        app_state.status_msg = error_msg
                                    end
                                end
                                if r.ImGui_IsItemHovered(ctx) and item.source_id and item.source_id ~= "" then
                                    local valid, error_msg = NameProcessor.ValidateField("source_id", item.source_id, Constants.UCS_OPTIONAL_FIELDS)
                                    if not valid then
                                        r.ImGui_SetTooltip(ctx, error_msg)
                                    end
                                end
                            end
                            
                            -- UserData
                            if app_state.field_visibility.user_data then
                                col_idx = col_idx + 1
                                r.ImGui_TableSetColumnIndex(ctx, col_idx)
                                r.ImGui_SetNextItemWidth(ctx, -1)
                                local changed_ud, new_ud = r.ImGui_InputText(ctx, "##ud_" .. i, item.user_data or "", r.ImGui_InputTextFlags_AutoSelectAll())
                                if changed_ud then
                                    item.user_data = new_ud
                                    NameProcessor.UpdateFinalName(item, app_state, Constants.UCS_OPTIONAL_FIELDS)
                                end
                            end
                        end

                        -- Col: Preview (只读的最终预览)
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        
                        -- 根据状态设置文字颜色
                        local status_col = Constants.COLORS.TEXT_NORMAL
                        if item.status == "changed" then status_col = Constants.COLORS.TEXT_MODIFIED end
                        if app_state.use_ucs_mode and item.match_type == "auto" then status_col = Constants.COLORS.TEXT_AUTO end
                        
                        if app_state.use_ucs_mode then
                            -- UCS模式：显示最终生成的UCS格式名称
                            r.ImGui_TextColored(ctx, status_col, item.new_name)
                        else
                            -- 非UCS模式：显示Replace列的内容作为预览
                            if item.trans_name and item.trans_name ~= "" then
                                if item.status == "changed" then
                                    r.ImGui_TextColored(ctx, Constants.COLORS.TEXT_MODIFIED, item.trans_name)
                                else
                                    r.ImGui_TextColored(ctx, Constants.COLORS.TEXT_NORMAL, item.trans_name)
                                end
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
        
        -- 【布局微调】增加边距，让按钮更精致
        local button_padding = 4
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + button_padding)
        local button_width = r.ImGui_GetContentRegionAvail(ctx) - button_padding * 2
        
        if changes_count > 0 then
            if Theme.BtnPrimary(ctx, "APPLY " .. changes_count .. " CHANGES", button_width, 36) then
                ProjectActions.ActionApply(app_state, ProjectActions, NameProcessor, Constants.UCS_OPTIONAL_FIELDS, ucs_db,
                    UCSMatcher, Constants.WEIGHTS, Constants.MATCH_THRESHOLD, Constants.DOWNGRADE_WORDS, Helpers, Constants.SAFE_DOMINANT_KEYWORDS)
            end
        else
            r.ImGui_BeginDisabled(ctx)
            r.ImGui_Button(ctx, "NO CHANGES", button_width, 36)
            r.ImGui_EndDisabled(ctx)
        end

        -- [Footer: Status Log]
        r.ImGui_Separator(ctx)
        
        -- Version info on the left
        r.ImGui_TextColored(ctx, 0x4DB6ACFF, string.format("v%s (%s)", Constants.VERSION, Constants.VERSION_DATE))
        r.ImGui_SameLine(ctx)
        r.ImGui_TextColored(ctx, 0x666666FF, " | ")
        r.ImGui_SameLine(ctx)
        
        -- Status message
        r.ImGui_TextColored(ctx, 0xAAAAAAFF, "Log: " .. app_state.status_msg)
        
        -- [Alias Editor Popup Modal]
        if r.ImGui_BeginPopupModal(ctx, "alias_editor_popup", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_Text(ctx, "Add New Alias Rule")
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 5)
            
            -- Source input
            r.ImGui_Text(ctx, "Source (input phrase):")
            r.ImGui_SetNextItemWidth(ctx, 300)
            local source_changed, new_source = r.ImGui_InputText(ctx, "##alias_source", app_state.alias_source or "")
            if source_changed then
                app_state.alias_source = new_source
            end
            
            r.ImGui_Dummy(ctx, 0, 5)
            
            -- Target input
            r.ImGui_Text(ctx, "Target (replacement):")
            r.ImGui_SetNextItemWidth(ctx, 300)
            local target_changed, new_target = r.ImGui_InputText(ctx, "##alias_target", app_state.alias_target or "")
            if target_changed then
                app_state.alias_target = new_target
            end
            
            r.ImGui_Dummy(ctx, 0, 10)
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 5)
            
            -- Buttons
            local can_save = (app_state.alias_source and app_state.alias_source ~= "") and 
                           (app_state.alias_target and app_state.alias_target ~= "")
            
            if not can_save then
                r.ImGui_BeginDisabled(ctx)
            end
            
            if r.ImGui_Button(ctx, "Save", 145, 0) then
                -- Save alias to file
                local DataLoader = modules.DataLoader
                
                local success, msg = DataLoader.SaveUserAlias(
                    script_path, 
                    Constants.CSV_ALIAS_FILE, 
                    app_state.alias_source:lower():match("^%s*(.-)%s*$"),
                    app_state.alias_target:lower():match("^%s*(.-)%s*$")
                )
                
                if success then
                    -- Reload alias list
                    DataLoader.LoadUserAlias(ucs_db, script_path, Constants.CSV_ALIAS_FILE, Helpers)
                    app_state.status_msg = "Alias saved: " .. app_state.alias_source .. " -> " .. app_state.alias_target
                    -- Clear inputs
                    app_state.alias_source = ""
                    app_state.alias_target = ""
                    r.ImGui_CloseCurrentPopup(ctx)
                else
                    app_state.status_msg = "Error: " .. (msg or "Failed to save alias")
                end
            end
            
            if not can_save then
                r.ImGui_EndDisabled(ctx)
            end
            
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_Button(ctx, "Cancel", 145, 0) then
                app_state.alias_source = ""
                app_state.alias_target = ""
                r.ImGui_CloseCurrentPopup(ctx)
            end
            
            r.ImGui_EndPopup(ctx)
        end

        r.ImGui_End(ctx)
    end
    
    -- 还原样式
    r.ImGui_PopStyleVar(ctx, pop_vars)
    r.ImGui_PopStyleColor(ctx, pop_cols)

    return open
end

return GUI

