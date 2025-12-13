--[[
  Project actions module for UCS Rename Tools
  Handles all REAPER project interactions (markers/regions)
]]

local ProjectActions = {}
local r = reaper

function ProjectActions.JumpToMarkerOrRegion(item)
    if not item or not item.pos then return end
    
    r.Undo_BeginBlock()
    
    if item.isrgn then
        -- Region: 跳转到开始位置，并设置时间选择为整个region范围
        r.SetEditCurPos(item.pos, true, true)
        r.GetSet_LoopTimeRange(true, false, item.pos, item.rgnend, false)
        r.Undo_EndBlock("Go to Region " .. item.id, -1)
    else
        -- Marker: 直接跳转到位置
        r.SetEditCurPos(item.pos, true, true)
        r.Undo_EndBlock("Go to Marker " .. item.id, -1)
    end
    
    r.UpdateArrange()
end

-- 立即应用单个marker/region的名称到工程（非UCS模式使用）
function ProjectActions.ApplySingleName(item)
    if not item then return false end
    
    -- 构建当前工程中所有marker/region的映射
    local current_map = {}
    local ret, num_markers, num_regions = r.CountProjectMarkers(0)
    for i = 0, num_markers + num_regions - 1 do
        local _, isrgn, _, _, _, markrgnindexnumber = r.EnumProjectMarkers3(0, i)
        local t = isrgn and "Region" or "Marker"
        current_map[t .. "_" .. markrgnindexnumber] = i
    end
    
    -- 查找对应的索引
    local key = item.type_str .. "_" .. item.id
    local idx = current_map[key]
    
    if idx then
        r.Undo_BeginBlock()
        -- 应用新名称（使用current_name，因为这是用户在原名列输入的值）
        r.SetProjectMarkerByIndex(0, idx, item.isrgn, item.pos, item.rgnend, item.id, item.current_name, 0)
        r.Undo_EndBlock("Rename " .. item.type_str .. " " .. item.id, -1)
        r.UpdateArrange()
        
        -- 更新item状态，使其与工程同步
        item.trans_name = item.current_name
        item.new_name = item.current_name
        item.status = "same"
        
        return true
    end
    
    return false
end

function ProjectActions.ReloadProjectData(app_state, ucs_db, name_processor, ucs_optional_fields, ucs_matcher, weights, match_threshold, downgrade_words, helpers, safe_dominant_keywords)
    app_state.merged_list = {}
    local ret, num_markers, num_regions = r.CountProjectMarkers(0)
    
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = r.EnumProjectMarkers3(0, i)
        if retval ~= 0 then
            local type_str = isrgn and "Region" or "Marker"
            local item = {
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
                cat_input = "",  -- 用户输入的Category搜索文本
                sub_input = "",  -- 用户输入的SubCategory搜索文本
                -- 新增可选字段
                vendor_category = "",
                creator_id = "",
                source_id = "",
                user_data = "",
                isrgn = isrgn,
                pos = pos,
                rgnend = rgnend,
                status = "same"
            }
            
            -- 尝试解析 UCS 格式名称（仅在 UCS 数据已加载时）
            -- 注意：如果名称不符合UCS格式（ParseUCSName返回nil），则保持原样，不进行任何拆分
            -- 所有UCS字段保持为空，只有current_name和trans_name有值（都是原名称）
            if ucs_db and ucs_db.flat_list and #ucs_db.flat_list > 0 then
                local parsed = name_processor.ParseUCSName(name, ucs_db)
                if parsed then
                    -- 名称符合UCS格式，进行解析和拆分
                    -- 填充解析出的字段
                    item.ucs_cat_id = parsed.ucs_cat_id
                    if parsed.vendor_category and parsed.vendor_category ~= "" then
                        item.vendor_category = parsed.vendor_category
                    end
                    if parsed.trans_name and parsed.trans_name ~= "" then
                        item.trans_name = parsed.trans_name
                    end
                    if parsed.creator_id and parsed.creator_id ~= "" then
                        item.creator_id = parsed.creator_id
                    end
                    if parsed.source_id and parsed.source_id ~= "" then
                        item.source_id = parsed.source_id
                    end
                    if parsed.user_data and parsed.user_data ~= "" then
                        item.user_data = parsed.user_data
                    end
                    
                    -- 根据 CatID 同步分类和子分类
                    name_processor.SyncFromID(item, ucs_db, app_state, ucs_optional_fields)
                    
                    -- 更新最终名称（应该和 current_name 相同）
                    name_processor.UpdateFinalName(item, app_state, ucs_optional_fields)
                else
                    -- 智能初始化：如果未解析出 UCS 格式，且为英文文件名，尝试自动匹配
                    if ucs_matcher and weights and match_threshold and downgrade_words and helpers and safe_dominant_keywords then
                        -- 检查是否为英文文件名（不包含中文字符）
                        local is_english = not name:match("[\128-\255]")
                        
                        if is_english and name ~= "" then
                            -- 自动匹配
                            local match = ucs_matcher.FindBestUCS(
                                name, ucs_db, weights, match_threshold, 
                                downgrade_words, helpers, safe_dominant_keywords
                            )
                            
                            if match then
                                item.ucs_cat_id = match.id
                                item.cat_zh_sel = match.raw_cat_zh
                                item.sub_zh_sel = match.raw_sub_zh
                                item.match_type = "auto_init"
                                name_processor.UpdateFinalName(item, app_state, ucs_optional_fields)
                            end
                        end
                    end
                end
            end
            
            table.insert(app_state.merged_list, item)
        end
    end
    if app_state.status_msg == "Initializing..." then
        app_state.status_msg = "Project loaded."
    end
end

function ProjectActions.ActionSmartPaste(app_state, ucs_db, name_processor, ucs_matcher, weights, match_threshold, downgrade_words, helpers, ucs_optional_fields, safe_dominant_keywords)
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
                    if #ucs_db.flat_list > 0 then 
                        name_processor.AutoMatchItem(item, ucs_db, app_state, ucs_optional_fields, ucs_matcher, weights, match_threshold, downgrade_words, helpers, safe_dominant_keywords)
                    else 
                        name_processor.UpdateFinalName(item, app_state, ucs_optional_fields)
                    end
                    match_count = match_count + 1
                end
            end
        end
    end
    app_state.status_msg = string.format("Paste: Updated %d items.", match_count)
end

function ProjectActions.ActionApply(app_state, project_actions, name_processor, ucs_optional_fields, ucs_db, ucs_matcher, weights, match_threshold, downgrade_words, helpers, safe_dominant_keywords)
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
    project_actions.ReloadProjectData(app_state, ucs_db, name_processor, ucs_optional_fields, ucs_matcher, weights, match_threshold, downgrade_words, helpers, safe_dominant_keywords)
end

function ProjectActions.ActionCopyOriginal(app_state)
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

return ProjectActions


