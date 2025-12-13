--[[
  Name processing module for UCS Rename Tools
  Handles UCS name generation, parsing, validation, and field operations
]]

local NameProcessor = {}

function NameProcessor.UpdateFinalName(item, app_state, ucs_optional_fields)
    if app_state.use_ucs_mode and item.ucs_cat_id and item.ucs_cat_id ~= "" then
        local name_parts = {}
        
        -- 1. CatID（必填）
        table.insert(name_parts, item.ucs_cat_id)
        
        -- 2. VendorCategory + FXName（特殊组合，VendorCategory用"-"连接FXName）
        -- 只有当字段可见时才包含在结果中
        local fx_part = ""
        if app_state.field_visibility.vendor_category and item.vendor_category and item.vendor_category ~= "" then
            fx_part = item.vendor_category .. "-"
        end
        if item.trans_name and item.trans_name ~= "" then
            fx_part = fx_part .. item.trans_name
        elseif fx_part ~= "" then
            fx_part = fx_part:sub(1, -2)  -- 移除末尾的"-"
        end
        
        if fx_part ~= "" then
            table.insert(name_parts, fx_part)
        end
        
        -- 3. CreatorID（可选，只有可见时才包含）
        if app_state.field_visibility.creator_id and item.creator_id and item.creator_id ~= "" then
            table.insert(name_parts, item.creator_id)
        end
        
        -- 4. SourceID（可选，只有可见时才包含）
        if app_state.field_visibility.source_id and item.source_id and item.source_id ~= "" then
            table.insert(name_parts, item.source_id)
        end
        
        -- 5. UserData（可选，只有可见时才包含）
        if app_state.field_visibility.user_data and item.user_data and item.user_data ~= "" then
            table.insert(name_parts, item.user_data)
        end
        
        -- 最终组合：所有部分用"_"连接
        item.new_name = table.concat(name_parts, "_")
    else
        item.new_name = item.trans_name
    end
    
    NameProcessor.UpdateItemStatus(item)
end

function NameProcessor.UpdateItemStatus(item)
    if item.new_name ~= item.current_name then
        item.status = "changed"
    else
        item.status = "same"
    end
end

function NameProcessor.SyncFromID(item, ucs_db, app_state, ucs_optional_fields)
    local info = ucs_db.id_lookup[item.ucs_cat_id]
    if info then
        -- 始终使用中文作为内部存储
        item.cat_zh_sel = info.cat_zh
        item.sub_zh_sel = info.sub_zh
    end
    NameProcessor.UpdateFinalName(item, app_state, ucs_optional_fields)
end

function NameProcessor.AutoMatchItem(item, ucs_db, app_state, ucs_optional_fields, ucs_matcher, weights, match_threshold, downgrade_words, helpers, safe_dominant_keywords)
    if #ucs_db.flat_list > 0 then
        local match = ucs_matcher.FindBestUCS(item.trans_name, ucs_db, weights, match_threshold, downgrade_words, helpers, safe_dominant_keywords)
        if match then
            item.ucs_cat_id = match.id
            item.cat_zh_sel = match.raw_cat_zh
            item.sub_zh_sel = match.raw_sub_zh
            item.match_type = "auto"
            NameProcessor.SyncFromID(item, ucs_db, app_state, ucs_optional_fields)
        else
            item.match_type = ""
        end
    end
    NameProcessor.UpdateFinalName(item, app_state, ucs_optional_fields)
end

function NameProcessor.UpdateAllItemsMode(app_state, ucs_optional_fields)
    for _, item in ipairs(app_state.merged_list) do
        NameProcessor.UpdateFinalName(item, app_state, ucs_optional_fields)
    end
end

-- 填充字段到所有可见项目（使用第一行的值）
function NameProcessor.FillFieldToAll(field_key, app_state, ucs_optional_fields)
    -- 找到第一个可见行的值作为填充源
    local source_value = nil
    for _, item in ipairs(app_state.merged_list) do
        local is_visible = (item.type_str == "Marker" and app_state.filter_markers) or 
                          (item.type_str == "Region" and app_state.filter_regions)
        if is_visible then
            source_value = item[field_key] or ""
            break
        end
    end
    
    if source_value == nil then
        app_state.status_msg = "No visible items to fill."
        return
    end
    
    local fill_count = 0
    for _, item in ipairs(app_state.merged_list) do
        -- 只填充可见的项目
        local is_visible = (item.type_str == "Marker" and app_state.filter_markers) or 
                          (item.type_str == "Region" and app_state.filter_regions)
        
        if is_visible then
            item[field_key] = source_value
            NameProcessor.UpdateFinalName(item, app_state, ucs_optional_fields)
            fill_count = fill_count + 1
        end
    end
    
    local field_display = ""
    for _, f in ipairs(ucs_optional_fields) do
        if f.key == field_key then
            field_display = f.display
            break
        end
    end
    
    app_state.status_msg = string.format("Filled '%s' to %d visible items.", field_display, fill_count)
end

-- 清除单个字段到所有可见项目
function NameProcessor.ClearFieldToAll(field_key, app_state, ucs_optional_fields)
    local clear_count = 0
    for _, item in ipairs(app_state.merged_list) do
        local is_visible = (item.type_str == "Marker" and app_state.filter_markers) or 
                          (item.type_str == "Region" and app_state.filter_regions)
        if is_visible then
            item[field_key] = ""
            NameProcessor.UpdateFinalName(item, app_state, ucs_optional_fields)
            clear_count = clear_count + 1
        end
    end
    
    local field_display = ""
    for _, f in ipairs(ucs_optional_fields) do
        if f.key == field_key then
            field_display = f.display
            break
        end
    end
    
    app_state.status_msg = string.format("Cleared '%s' for %d visible items.", field_display, clear_count)
end

-- 清除隐藏字段的内容并更新
function NameProcessor.ClearHiddenFieldsAndUpdate(app_state, ucs_optional_fields)
    local update_count = 0
    for _, item in ipairs(app_state.merged_list) do
        local need_update = false
        if not app_state.field_visibility.vendor_category and item.vendor_category ~= "" then
            item.vendor_category = ""
            need_update = true
        end
        if not app_state.field_visibility.creator_id and item.creator_id ~= "" then
            item.creator_id = ""
            need_update = true
        end
        if not app_state.field_visibility.source_id and item.source_id ~= "" then
            item.source_id = ""
            need_update = true
        end
        if not app_state.field_visibility.user_data and item.user_data ~= "" then
            item.user_data = ""
            need_update = true
        end
        if need_update then
            NameProcessor.UpdateFinalName(item, app_state, ucs_optional_fields)
            update_count = update_count + 1
        end
    end
    if update_count > 0 then
        app_state.status_msg = string.format("Cleared hidden fields for %d items.", update_count)
    end
end

-- 验证字段值
function NameProcessor.ValidateField(field_key, value, ucs_optional_fields)
    if not value or value == "" then return true, nil end
    
    for _, f in ipairs(ucs_optional_fields) do
        if f.key == field_key and f.validation then
            local valid = f.validation(value)
            if not valid then
                local error_msg = string.format("%s cannot contain '_' or spaces", f.display)
                return false, error_msg
            end
        end
    end
    
    return true, nil
end

-- 验证CatID是否存在于UCS数据库中
function NameProcessor.ValidateCatID(cat_id, ucs_db)
    if not cat_id or cat_id == "" then return false, "CatID is empty" end
    if not ucs_db or not ucs_db.id_lookup then return false, "UCS database not loaded" end
    if not ucs_db.id_lookup[cat_id] then return false, "CatID not found in UCS database" end
    return true, nil
end

-- 验证完整的UCS格式名称
function NameProcessor.ValidateUCSFormat(item, ucs_db, ucs_optional_fields)
    local errors = {}
    
    -- 验证CatID
    if item.ucs_cat_id and item.ucs_cat_id ~= "" then
        local valid, error_msg = NameProcessor.ValidateCatID(item.ucs_cat_id, ucs_db)
        if not valid then
            table.insert(errors, "CatID: " .. error_msg)
        end
    end
    
    -- 验证可选字段格式
    for _, field in ipairs(ucs_optional_fields) do
        local value = item[field.key]
        if value and value ~= "" then
            local valid, error_msg = NameProcessor.ValidateField(field.key, value, ucs_optional_fields)
            if not valid then
                table.insert(errors, error_msg)
            end
        end
    end
    
    if #errors > 0 then
        return false, table.concat(errors, "; ")
    end
    
    return true, nil
end

-- 解析 UCS 格式名称
function NameProcessor.ParseUCSName(name, ucs_db)
    if not name or name == "" then return nil end
    
    -- 用下划线分割
    local parts = {}
    for part in name:gmatch("([^_]+)") do
        table.insert(parts, part)
    end
    
    if #parts == 0 then return nil end
    
    -- 第一部分应该是 CatID
    local cat_id = parts[1]
    
    -- 检查 CatID 是否在数据库中
    if not ucs_db.id_lookup[cat_id] then
        return nil  -- 不是有效的 UCS 格式
    end
    
    local result = {
        ucs_cat_id = cat_id,
        vendor_category = "",
        trans_name = "",
        creator_id = "",
        source_id = "",
        user_data = ""
    }
    
    -- 第二部分：可能是 VendorCategory-FXName 或直接是 FXName
    if #parts >= 2 then
        local part2 = parts[2]
        -- 检查是否包含 "-"（VendorCategory-FXName 格式）
        local dash_pos = part2:find("-", 1, true)
        if dash_pos then
            result.vendor_category = part2:sub(1, dash_pos - 1)
            result.trans_name = part2:sub(dash_pos + 1)
        else
            result.trans_name = part2
        end
    end
    
    -- 后续部分：CreatorID, SourceID, UserData（按顺序）
    if #parts >= 3 then
        result.creator_id = parts[3]
    end
    if #parts >= 4 then
        result.source_id = parts[4]
    end
    if #parts >= 5 then
        result.user_data = parts[5]
    end
    
    return result
end

return NameProcessor


