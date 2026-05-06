-- @description ImGui Marker/Region Translator Pro (v10.0 Layout Perfected)
-- @version 10.0
-- @author HongKun Li
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
local CSV_DB_FILE    = "ucs_data.csv"
local CSV_ALIAS_FILE = "ucs_alias.csv"
local SEPARATOR      = "_"
local DEFAULT_UCS_MODE = false 

-- 智能匹配权重
local WEIGHTS = {
    CATEGORY_EXACT = 50,
    CATEGORY_PART  = 10,
    SUBCATEGORY    = 60,
    SYNONYM        = 40,
    DESCRIPTION    = 5,
    PERFECT_BONUS  = 30
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
    tree_data = {},        -- 中文树结构
    tree_data_en = {},     -- 英文树结构
    categories_zh = {},
    categories_en = {},
    en_to_zh = {},         -- 英文到中文映射
    zh_to_en = {},         -- 中文到英文映射
    alias_list = {}        -- 别名列表（用于短语匹配）
}

-- 可选字段配置
local ucs_optional_fields = {
    {
        key = "vendor_category",
        display = "Vendor Category",
        position_after = "fx_name",
        validation = function(value)
            if not value or value == "" then return true end
            return not value:match("[_ ]")  -- 不能包含_和空格
        end
    },
    {
        key = "creator_id",
        display = "CreatorID",
        position_after = "fx_name",
        validation = function(value)
            if not value or value == "" then return true end
            return not value:match("[_ ]")
        end
    },
    {
        key = "source_id",
        display = "SourceID",
        position_after = "creator_id",
        validation = function(value)
            if not value or value == "" then return true end
            return not value:match("[_ ]")
        end
    },
    {
        key = "user_data",
        display = "User Data",
        position_after = "source_id",
        validation = nil  -- 无限制
    }
}

local app_state = {
    merged_list = {},
    status_msg = "Initializing...",
    filter_markers = true,
    filter_regions = true,
    use_ucs_mode = DEFAULT_UCS_MODE,
    display_language = "zh",  -- 显示语言：zh=中文, en=英文
    -- 字段显示状态（默认全部隐藏）
    field_visibility = {
        vendor_category = false,
        creator_id = false,
        source_id = false,
        user_data = false
    }
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

function EscapePattern(text)
    return text:gsub("([^%w])", "%%%1")
end

---------------------------------------------------------
-- 4. 数据加载
---------------------------------------------------------
function LoadUserAlias()
    local path = GetScriptPath() .. CSV_ALIAS_FILE
    local file = io.open(path, "r")
    ucs_db.alias_list = {} 
    if not file then return end
    
    for line in file:lines() do
        local cols = ParseCSVLine(line)
        if #cols >= 2 then
            local key = cols[1]:lower():match("^%s*(.-)%s*$")
            local val = cols[2]:lower():match("^%s*(.-)%s*$")
            if key ~= "" and val ~= "" then
                table.insert(ucs_db.alias_list, { key = key, val = val })
            end
        end
    end
    file:close()
    -- Sort by length descending for phrase matching
    table.sort(ucs_db.alias_list, function(a, b) return #a.key > #b.key end)
end

function LoadUCSData()
    local path = GetScriptPath() .. CSV_DB_FILE
    local file = io.open(path, "r")
    
    if not file then
        app_state.status_msg = "Note: " .. CSV_DB_FILE .. " not found (UCS disabled)."
        return false
    end

    ucs_db.flat_list = {}
    ucs_db.tree_data = {}
    ucs_db.tree_data_en = {}
    ucs_db.id_lookup = {}
    ucs_db.categories_zh = {}
    ucs_db.categories_en = {}
    ucs_db.en_to_zh = {}
    ucs_db.zh_to_en = {}
    
    local cat_seen_zh = {}
    local cat_seen_en = {}
    local is_header = true

    for line in file:lines() do
        if is_header then
            is_header = false
        else
            local cols = ParseCSVLine(line)
            if #cols >= 8 then
                local cat_en_raw = cols[1]  -- 原始英文字符串
                local sub_en_raw = cols[2]  -- 原始英文字符串
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
                    raw_sub_zh = cols[8],
                    raw_cat_en = cat_en_raw,  -- 保存原始英文
                    raw_sub_en = sub_en_raw   -- 保存原始英文
                }
                
                if d.id and d.id ~= "" then
                    table.insert(ucs_db.flat_list, d)
                    ucs_db.id_lookup[d.id] = { 
                        cat_zh = d.raw_cat_zh, 
                        sub_zh = d.raw_sub_zh,
                        cat_en = d.raw_cat_en,
                        sub_en = d.raw_sub_en
                    }

                    -- 构建中文树结构
                    if d.raw_cat_zh and d.raw_cat_zh ~= "" then
                        if not ucs_db.tree_data[d.raw_cat_zh] then
                            ucs_db.tree_data[d.raw_cat_zh] = {}
                            if not cat_seen_zh[d.raw_cat_zh] then
                                table.insert(ucs_db.categories_zh, d.raw_cat_zh)
                                cat_seen_zh[d.raw_cat_zh] = true
                            end
                        end
                        local sub_key = (d.raw_sub_zh and d.raw_sub_zh ~= "") and d.raw_sub_zh or "(General)"
                        ucs_db.tree_data[d.raw_cat_zh][sub_key] = d.id
                    end

                    -- 构建英文树结构
                    if cat_en_raw and cat_en_raw ~= "" then
                        if not ucs_db.tree_data_en[cat_en_raw] then
                            ucs_db.tree_data_en[cat_en_raw] = {}
                            if not cat_seen_en[cat_en_raw] then
                                table.insert(ucs_db.categories_en, cat_en_raw)
                                cat_seen_en[cat_en_raw] = true
                            end
                        end
                        local sub_key_en = (sub_en_raw and sub_en_raw ~= "") and sub_en_raw or "(General)"
                        ucs_db.tree_data_en[cat_en_raw][sub_key_en] = d.id
                    end

                    -- 建立双向映射
                    if d.raw_cat_zh and d.raw_cat_zh ~= "" and cat_en_raw and cat_en_raw ~= "" then
                        if not ucs_db.en_to_zh[cat_en_raw] then
                            ucs_db.en_to_zh[cat_en_raw] = {}
                        end
                        local sub_en_key = (sub_en_raw and sub_en_raw ~= "") and sub_en_raw or "(General)"
                        local sub_zh_key = (d.raw_sub_zh and d.raw_sub_zh ~= "") and d.raw_sub_zh or "(General)"
                        ucs_db.en_to_zh[cat_en_raw][sub_en_key] = {
                            cat = d.raw_cat_zh,
                            sub = sub_zh_key
                        }

                        if not ucs_db.zh_to_en[d.raw_cat_zh] then
                            ucs_db.zh_to_en[d.raw_cat_zh] = {}
                        end
                        ucs_db.zh_to_en[d.raw_cat_zh][sub_zh_key] = {
                            cat = cat_en_raw,
                            sub = sub_en_key
                        }
                    end
                end
            end
        end
    end
    file:close()
    
    -- Load aliases after DB
    LoadUserAlias()
    
    app_state.status_msg = string.format("Engine Ready: Loaded %d UCS definitions.", #ucs_db.flat_list)
    return true
end

---------------------------------------------------------
-- 5. 智能逻辑
---------------------------------------------------------
function FindBestUCS(user_input)
    if not user_input or user_input == "" then return nil end
    
    -- 1. Pre-processing: Phrase Substitution using Alias List
    local processed_input = user_input:lower()
    for _, alias in ipairs(ucs_db.alias_list) do
        local esc_key = EscapePattern(alias.key)
        processed_input = processed_input:gsub(esc_key, " " .. alias.val .. " ") 
    end
    
    local input_words = Tokenize(processed_input)
    if #input_words == 0 then return nil end
    
    local best_score = -999
    local best_match = nil
    
    for _, item in ipairs(ucs_db.flat_list) do
        local current_score = 0
        local cat_hit, sub_hit = false, false
        
        -- Check generic penalty
        local is_general = false
        for _, k in ipairs(item.sub_en) do
            if k == "general" or k == "misc" then is_general = true break end
        end
        
        for _, word in ipairs(input_words) do
            if #word > 1 then 
                local is_weak = DOWNGRADE_WORDS[word] == true
                
                -- Score Logic
                for _, k in ipairs(item.cat_en) do
                    if k == word then 
                        current_score = current_score + WEIGHTS.CATEGORY_EXACT
                        cat_hit = true
                    elseif k:find(word, 1, true) then 
                        current_score = current_score + WEIGHTS.CATEGORY_PART 
                    end
                end
                
                for _, k in ipairs(item.sub_en) do
                    if k == word then 
                        if is_weak then 
                            current_score = current_score + 5
                        else 
                            current_score = current_score + WEIGHTS.SUBCATEGORY
                            sub_hit = true 
                        end
                    elseif not is_weak and k:find(word, 1, true) then 
                        current_score = current_score + 10 
                    end
                end
                
                for _, k in ipairs(item.syn_en) do
                    if k == word then 
                        if is_weak then 
                            current_score = current_score + 2
                        else 
                            current_score = current_score + WEIGHTS.SYNONYM
                            sub_hit = true 
                        end
                    end
                end
                
                for _, k in ipairs(item.desc) do
                    if k == word then 
                        current_score = current_score + WEIGHTS.DESCRIPTION 
                    end
                end
            end
        end
        
        if cat_hit and sub_hit then 
            current_score = current_score + WEIGHTS.PERFECT_BONUS 
        end
        
        if is_general and current_score < 30 then 
            current_score = current_score - 15 
        end
        
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
    
    UpdateItemStatus(item)
end

function UpdateItemStatus(item)
    if item.new_name ~= item.current_name then
        item.status = "changed"
    else
        item.status = "same"
    end
end

-- 过滤匹配函数
function FilterMatch(input_text, target_text)
    if not input_text or input_text == "" then return true end
    if not target_text then return false end
    -- 转换为小写进行模糊匹配
    local input_lower = input_text:lower()
    local target_lower = target_text:lower()
    -- 检查是否包含输入文本
    return target_lower:find(input_lower, 1, true) ~= nil
end

function SyncFromID(item)
    local info = ucs_db.id_lookup[item.ucs_cat_id]
    if info then
        -- 始终使用中文作为内部存储
        item.cat_zh_sel = info.cat_zh
        item.sub_zh_sel = info.sub_zh
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

-- 填充字段到所有可见项目（使用第一行的值）
function FillFieldToAll(field_key)
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
            UpdateFinalName(item)
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
function ClearFieldToAll(field_key)
    local clear_count = 0
    for _, item in ipairs(app_state.merged_list) do
        local is_visible = (item.type_str == "Marker" and app_state.filter_markers) or 
                          (item.type_str == "Region" and app_state.filter_regions)
        if is_visible then
            item[field_key] = ""
            UpdateFinalName(item)
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
function ClearHiddenFieldsAndUpdate()
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
            UpdateFinalName(item)
            update_count = update_count + 1
        end
    end
    if update_count > 0 then
        app_state.status_msg = string.format("Cleared hidden fields for %d items.", update_count)
    end
end

-- 验证字段值
function ValidateField(field_key, value)
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

-- 解析 UCS 格式名称
function ParseUCSName(name)
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

---------------------------------------------------------
-- 6. 工程交互
---------------------------------------------------------
function JumpToMarkerOrRegion(item)
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

function ReloadProjectData()
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
            if #ucs_db.flat_list > 0 then
                local parsed = ParseUCSName(name)
                if parsed then
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
                    SyncFromID(item)
                    
                    -- 更新最终名称（应该和 current_name 相同）
                    UpdateFinalName(item)
                end
            end
            
            table.insert(app_state.merged_list, item)
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
-- 现代主题：Modern Slate (深岩灰风格)
function PushModernSlateTheme(ctx)
    -- 1. 样式变量：增加呼吸感和现代圆角
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(),    6)  -- 窗口圆角
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(),     4)  -- 输入框/按钮圆角 (4px 是现代 UI 标准)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(),     4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(),      4)
    
    -- 间距设置：比默认稍微宽松一点，让中文不拥挤
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(),       8, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(),      8, 5) 
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(),       6, 4) -- 表格内部留白
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(),     10, 10)

    -- 2. 颜色设置：Modern Slate (深岩灰风格)
    -- 核心逻辑：背景(深灰) -> 按钮(中灰) -> 输入框(黑灰) -> 文字(亮白)
    
    local bg_base      = 0x202020FF -- 整体背景 (深灰，不刺眼)
    local bg_popup     = 0x282828F0 -- 弹窗稍亮
    local bg_input     = 0x151515FF -- 输入框 (比背景黑，产生凹陷感)
    local border_col   = 0x383838FF -- 边框 (很淡)
    
    local btn_norm     = 0x353535FF -- 默认按钮 (中性灰)
    local btn_hover    = 0x454545FF -- 悬停
    local btn_active   = 0x252525FF -- 点击
    
    local accent_col   = 0x42A5F5FF -- 强调色：安静的蓝色 (用于选中、滑块)
    local accent_hover = 0x64B5F6FF

    -- [Window & Border]
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(),      bg_base)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(),       bg_base)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(),       bg_popup)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(),        border_col)
    
    -- [Header & Selection] (列表选中项)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(),        0x42A5F533) -- 淡淡的蓝色背景
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x42A5F555)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(),  0x42A5F577)
    
    -- [Inputs / Frame] (关键：深色凹陷)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),       bg_input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(),0x2A2A2AFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x303030FF)
    
    -- [Button] (默认全部灰色，去除彩虹色)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        btn_norm)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  btn_active)
    
    -- [Text]
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),          0xE0E0E0FF) -- 稍微柔和的白
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(),  0x808080FF)
    
    -- [Misc]
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(),     accent_col) -- 勾选框颜色
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),    btn_hover)  -- 滑块
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), accent_col)

    return 8, 18 -- 8 vars, 18 colors
end

-- 按钮辅助函数
-- 1. 普通功能按钮 (灰色，低调)
function BtnNormal(ctx, label)
    return r.ImGui_Button(ctx, label)
end

-- 2. 状态开关按钮 (激活时变蓝，否则灰)
function BtnToggle(ctx, label, is_active)
    if is_active then
        -- 激活时：使用舒适的蓝色
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x1976D2FF) 
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2196F3FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x1565C0FF)
    end
    
    local clicked = r.ImGui_Button(ctx, label)
    
    if is_active then r.ImGui_PopStyleColor(ctx, 3) end
    return clicked
end

-- 3. 强调/执行按钮 (绿色，只用于 Apply)
function BtnPrimary(ctx, label, w, h)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x2E7D32FF) -- 沉稳的绿色
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x388E3CFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x1B5E20FF)
    local clicked = r.ImGui_Button(ctx, label, w, h)
    r.ImGui_PopStyleColor(ctx, 3)
    return clicked
end

-- 4. 小按钮 (用于表格中的Fill/Clear按钮)
function BtnSmall(ctx, label)
    return r.ImGui_SmallButton(ctx, label)
end

function Loop()
    -- 应用现代主题
    local pop_vars, pop_cols = PushModernSlateTheme(ctx)

    r.ImGui_SetNextWindowSize(ctx, 900, 600, r.ImGui_Cond_FirstUseEver())

    local visible, open = r.ImGui_Begin(ctx, 'UCS Toolkit', true, r.ImGui_WindowFlags_None())
    
    if visible then
        -- [Top Toolbar: Buttons Only] - 全部使用普通按钮，整齐划一
        if BtnNormal(ctx, "Copy List") then ActionCopyOriginal() end
        r.ImGui_SameLine(ctx)
        
        if BtnNormal(ctx, "Paste") then ActionSmartPaste() end
        r.ImGui_SameLine(ctx)

        if BtnNormal(ctx, "Refresh") then ReloadProjectData() end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, "|")
        r.ImGui_SameLine(ctx)

        -- UCS Mode 开关按钮
        local ucs_btn_txt = app_state.use_ucs_mode and "UCS Mode: ON" or "UCS Mode: OFF"
        if BtnToggle(ctx, ucs_btn_txt, app_state.use_ucs_mode) then
            app_state.use_ucs_mode = not app_state.use_ucs_mode
            UpdateAllItemsMode()
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_TextDisabled(ctx, "|")
        r.ImGui_SameLine(ctx)
        
        -- 语言切换按钮
        local lang_btn_txt = (app_state.display_language == "en") and "Language: EN" or "Language: 中文"
        if BtnToggle(ctx, lang_btn_txt, app_state.display_language == "en") then
            app_state.display_language = (app_state.display_language == "zh") and "en" or "zh"
        end
        
        -- 字段显示控制（仅在UCS模式下显示）
        if app_state.use_ucs_mode then
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, "|")
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Fields:")
            r.ImGui_SameLine(ctx)
            
            -- 【修复】强制文本为亮白色，确保 Checkbox 文字清晰可见
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
            
            -- VendorCategory
            local _, v1 = r.ImGui_Checkbox(ctx, "V##vendor", app_state.field_visibility.vendor_category)
            if _ then 
                app_state.field_visibility.vendor_category = v1
                if not v1 then ClearHiddenFieldsAndUpdate() end
            end
            r.ImGui_SameLine(ctx)
            
            -- CreatorID
            local _, v2 = r.ImGui_Checkbox(ctx, "C##creator", app_state.field_visibility.creator_id)
            if _ then 
                app_state.field_visibility.creator_id = v2
                if not v2 then ClearHiddenFieldsAndUpdate() end
            end
            r.ImGui_SameLine(ctx)
            
            -- SourceID
            local _, v3 = r.ImGui_Checkbox(ctx, "S##source", app_state.field_visibility.source_id)
            if _ then 
                app_state.field_visibility.source_id = v3
                if not v3 then ClearHiddenFieldsAndUpdate() end
            end
            r.ImGui_SameLine(ctx)
            
            -- UserData
            local _, v4 = r.ImGui_Checkbox(ctx, "U##user", app_state.field_visibility.user_data)
            if _ then 
                app_state.field_visibility.user_data = v4
                if not v4 then ClearHiddenFieldsAndUpdate() end
            end
            
            -- 恢复文本颜色
            r.ImGui_PopStyleColor(ctx, 1)
        end

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
            
            -- 动态计算列数
            local base_cols = app_state.use_ucs_mode and 7 or 5  -- 基础列数
            local optional_cols_count = 0
            if app_state.use_ucs_mode then
                if app_state.field_visibility.vendor_category then optional_cols_count = optional_cols_count + 1 end
                if app_state.field_visibility.creator_id then optional_cols_count = optional_cols_count + 1 end
                if app_state.field_visibility.source_id then optional_cols_count = optional_cols_count + 1 end
                if app_state.field_visibility.user_data then optional_cols_count = optional_cols_count + 1 end
            end
            local num_cols = base_cols + optional_cols_count
            
            if r.ImGui_BeginTable(ctx, table_id, num_cols, t_flags) then
                
                -- [Column Weights Optimization]
                r.ImGui_TableSetupColumn(ctx, 'ID', r.ImGui_TableColumnFlags_WidthFixed(), 35)
                
                if app_state.use_ucs_mode then
                    local cat_header = (app_state.display_language == "en") and "Category" or "分类"
                    local sub_header = (app_state.display_language == "en") and "SubCategory" or "子分类"
                    r.ImGui_TableSetupColumn(ctx, cat_header, r.ImGui_TableColumnFlags_WidthFixed(), 90)
                    r.ImGui_TableSetupColumn(ctx, sub_header, r.ImGui_TableColumnFlags_WidthFixed(), 90)
                    r.ImGui_TableSetupColumn(ctx, 'CatID', r.ImGui_TableColumnFlags_WidthFixed(), 95)
                end
                
                -- 原名列（使用更大的权重，确保有足够空间）
                local orig_header = (app_state.display_language == "en") and "Original" or "原名"
                r.ImGui_TableSetupColumn(ctx, orig_header, r.ImGui_TableColumnFlags_WidthStretch(), 2.0)
                
                -- FXName列（使用更大的权重，确保有足够空间）
                r.ImGui_TableSetupColumn(ctx, 'FXName', r.ImGui_TableColumnFlags_WidthStretch(), 1.5)
                
                -- 可选字段列（动态添加，仅在UCS模式下且字段可见时）
                -- 使用 NoResize 标志强制遵守固定宽度（参考另一个成功的脚本）
                if app_state.use_ucs_mode then
                    if app_state.field_visibility.vendor_category then
                        r.ImGui_TableSetupColumn(ctx, 'VC', r.ImGui_TableColumnFlags_WidthFixed() | r.ImGui_TableColumnFlags_NoResize(), 70)
                    end
                    if app_state.field_visibility.creator_id then
                        r.ImGui_TableSetupColumn(ctx, 'CID', r.ImGui_TableColumnFlags_WidthFixed() | r.ImGui_TableColumnFlags_NoResize(), 70)
                    end
                    if app_state.field_visibility.source_id then
                        r.ImGui_TableSetupColumn(ctx, 'SID', r.ImGui_TableColumnFlags_WidthFixed() | r.ImGui_TableColumnFlags_NoResize(), 70)
                    end
                    if app_state.field_visibility.user_data then
                        r.ImGui_TableSetupColumn(ctx, 'UD', r.ImGui_TableColumnFlags_WidthFixed() | r.ImGui_TableColumnFlags_NoResize(), 70)
                    end
                end
                
                -- Preview列（调整权重，为其他列留出空间）
                if app_state.use_ucs_mode then
                    r.ImGui_TableSetupColumn(ctx, 'Preview', r.ImGui_TableColumnFlags_WidthStretch(), 1.2)
                else
                    r.ImGui_TableSetupColumn(ctx, 'Preview', r.ImGui_TableColumnFlags_WidthStretch(), 1.5)
                end
                
                -- 手动创建表头（以便添加Fill按钮）
                r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_Headers())
                
                -- Col: ID
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_TableHeader(ctx, 'ID')
                
                if app_state.use_ucs_mode then
                    -- Col: Category
                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    local cat_header = (app_state.display_language == "en") and "Category" or "分类"
                    r.ImGui_TableHeader(ctx, cat_header)
                    
                    -- Col: SubCategory
                    r.ImGui_TableSetColumnIndex(ctx, 2)
                    local sub_header = (app_state.display_language == "en") and "SubCategory" or "子分类"
                    r.ImGui_TableHeader(ctx, sub_header)
                    
                    -- Col: CatID
                    r.ImGui_TableSetColumnIndex(ctx, 3)
                    r.ImGui_TableHeader(ctx, 'CatID')
                end
                
                -- Col: 原名
                local orig_header = (app_state.display_language == "en") and "Original" or "原名"
                r.ImGui_TableSetColumnIndex(ctx, app_state.use_ucs_mode and 4 or 1)
                r.ImGui_TableHeader(ctx, orig_header)
                
                -- Col: FXName
                r.ImGui_TableSetColumnIndex(ctx, app_state.use_ucs_mode and 5 or 2)
                r.ImGui_TableHeader(ctx, 'FXName')
                
                -- 可选字段列头（带Fill按钮）
                local col_idx = app_state.use_ucs_mode and 5 or 2
                if app_state.use_ucs_mode then
                    -- VendorCategory (使用缩写 VC)
                    if app_state.field_visibility.vendor_category then
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_PushID(ctx, "header_vc")
                        r.ImGui_Text(ctx, 'VC')
                        r.ImGui_SameLine(ctx, 0.0, 2.0)
                        if BtnSmall(ctx, "F") then
                            FillFieldToAll("vendor_category")
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Fill Vendor Category to all visible items")
                        end
                        r.ImGui_SameLine(ctx, 0.0, 1.0)
                        if BtnSmall(ctx, "C") then
                            ClearFieldToAll("vendor_category")
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Clear Vendor Category for all visible items")
                        end
                        r.ImGui_PopID(ctx)
                    end
                    
                    -- CreatorID (使用缩写 CID)
                    if app_state.field_visibility.creator_id then
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_PushID(ctx, "header_ci")
                        r.ImGui_Text(ctx, 'CID')
                        r.ImGui_SameLine(ctx, 0.0, 2.0)
                        if BtnSmall(ctx, "F") then
                            FillFieldToAll("creator_id")
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Fill CreatorID to all visible items")
                        end
                        r.ImGui_SameLine(ctx, 0.0, 1.0)
                        if BtnSmall(ctx, "C") then
                            ClearFieldToAll("creator_id")
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Clear CreatorID for all visible items")
                        end
                        r.ImGui_PopID(ctx)
                    end
                    
                    -- SourceID (使用缩写 SID)
                    if app_state.field_visibility.source_id then
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_PushID(ctx, "header_si")
                        r.ImGui_Text(ctx, 'SID')
                        r.ImGui_SameLine(ctx, 0.0, 2.0)
                        if BtnSmall(ctx, "F") then
                            FillFieldToAll("source_id")
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Fill SourceID to all visible items")
                        end
                        r.ImGui_SameLine(ctx, 0.0, 1.0)
                        if BtnSmall(ctx, "C") then
                            ClearFieldToAll("source_id")
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Clear SourceID for all visible items")
                        end
                        r.ImGui_PopID(ctx)
                    end
                    
                    -- UserData (使用缩写 UD)
                    if app_state.field_visibility.user_data then
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_PushID(ctx, "header_ud")
                        r.ImGui_Text(ctx, 'UD')
                        r.ImGui_SameLine(ctx, 0.0, 2.0)
                        if BtnSmall(ctx, "F") then
                            FillFieldToAll("user_data")
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Fill User Data to all visible items")
                        end
                        r.ImGui_SameLine(ctx, 0.0, 1.0)
                        if BtnSmall(ctx, "C") then
                            ClearFieldToAll("user_data")
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Clear User Data for all visible items")
                        end
                        r.ImGui_PopID(ctx)
                    end
                end
                
                -- Col: Preview
                col_idx = col_idx + 1
                r.ImGui_TableSetColumnIndex(ctx, col_idx)
                r.ImGui_TableHeader(ctx, 'Preview')

                for i, item in ipairs(app_state.merged_list) do
                    local show = (item.type_str == "Marker" and app_state.filter_markers) or (item.type_str == "Region" and app_state.filter_regions)
                    
                    if show then
                        r.ImGui_PushID(ctx, i)
                        r.ImGui_TableNextRow(ctx)
                        
                        -- Col: ID (Clickable)
                        r.ImGui_TableSetColumnIndex(ctx, 0)
                        local id_col = (item.type_str == "Marker") and COLORS.ID_MARKER or COLORS.ID_REGION
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000) -- 透明背景
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), id_col + 0x20000000) -- 悬停时高亮
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), id_col + 0x40000000) -- 点击时高亮
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), id_col) -- 文字颜色
                        if r.ImGui_Button(ctx, tostring(item.id), -1, 0) then
                            JumpToMarkerOrRegion(item)
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
                            
                            if r.ImGui_BeginCombo(ctx, "##cat", cat_display) then
                                r.ImGui_SetNextItemWidth(ctx, -1)
                                local cat_filter_changed, new_filter = r.ImGui_InputText(ctx, "##cat_filter", item.cat_input or "", r.ImGui_InputTextFlags_AutoSelectAll())
                                if cat_filter_changed then
                                    item.cat_input = new_filter
                                end
                                r.ImGui_Separator(ctx)
                                
                                local has_any_match = false
                                local filtered_cats = {}
                                for _, cat in ipairs(cat_list) do
                                    if not item.cat_input or item.cat_input == "" or FilterMatch(item.cat_input, cat) then
                                        has_any_match = true
                                        table.insert(filtered_cats, cat)
                                    end
                                end
                                
                                if has_any_match then
                                    for _, cat in ipairs(filtered_cats) do
                                        local is_selected = (cat_selected == cat)
                                        if r.ImGui_Selectable(ctx, cat .. "##c", is_selected) then
                                            item.cat_input = ""
                                            item.sub_zh_sel = ""
                                            item.sub_input = ""
                                            item.ucs_cat_id = ""
                                            -- 根据语言转换：英文选择 -> 中文存储
                                            if app_state.display_language == "en" then
                                                -- 英文选择：找到对应的中文category
                                                if ucs_db.en_to_zh[cat] then
                                                    -- en_to_zh[cat_en] 是一个table，包含所有sub的映射
                                                    -- 我们需要找到第一个sub的映射来获取cat_zh
                                                    local first_sub_key = next(ucs_db.en_to_zh[cat])
                                                    if first_sub_key and ucs_db.en_to_zh[cat][first_sub_key] then
                                                        item.cat_zh_sel = ucs_db.en_to_zh[cat][first_sub_key].cat
                                                    end
                                                end
                                            else
                                                -- 中文选择：直接使用
                                                item.cat_zh_sel = cat
                                            end
                                            UpdateFinalName(item)
                                        end
                                        if is_selected then
                                            r.ImGui_SetItemDefaultFocus(ctx)
                                        end
                                    end
                                end
                                
                                if item.cat_input and item.cat_input ~= "" and not has_any_match then
                                    local no_match_text = (app_state.display_language == "en") and "No match" or "无匹配项"
                                    r.ImGui_TextDisabled(ctx, no_match_text)
                                end
                                
                                r.ImGui_EndCombo(ctx)
                            end

                            -- Col: SubCategory (可搜索Combo)
                            r.ImGui_TableSetColumnIndex(ctx, 2)
                            r.ImGui_SetNextItemWidth(ctx, -1)
                            
                            -- 根据显示语言获取当前值和预览
                            local sub_display, sub_list, sub_selected, sub_tree_data
                            if app_state.display_language == "en" then
                                -- 英文模式
                                local sub_en_sel = ""
                                local cat_en_for_sub = ""
                                
                                if item.cat_zh_sel and item.cat_zh_sel ~= "" then
                                    if item.sub_zh_sel and item.sub_zh_sel ~= "" and ucs_db.zh_to_en[item.cat_zh_sel] and ucs_db.zh_to_en[item.cat_zh_sel][item.sub_zh_sel] then
                                        -- 有sub_zh_sel，直接获取对应的英文sub和cat
                                        sub_en_sel = ucs_db.zh_to_en[item.cat_zh_sel][item.sub_zh_sel].sub or ""
                                        cat_en_for_sub = ucs_db.zh_to_en[item.cat_zh_sel][item.sub_zh_sel].cat or ""
                                    elseif ucs_db.zh_to_en[item.cat_zh_sel] then
                                        -- 没有sub_zh_sel，但从任意一个sub的映射中获取cat
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
                            
                            if r.ImGui_BeginCombo(ctx, "##sub", sub_display) then
                                r.ImGui_SetNextItemWidth(ctx, -1)
                                local sub_filter_changed, new_sub_filter = r.ImGui_InputText(ctx, "##sub_filter", item.sub_input or "", r.ImGui_InputTextFlags_AutoSelectAll())
                                if sub_filter_changed then
                                    item.sub_input = new_sub_filter
                                end
                                r.ImGui_Separator(ctx)
                                
                                if sub_tree_data then
                                    local has_any_match = false
                                    local filtered_subs = {}
                                    for sub, id in pairs(sub_tree_data) do
                                        if not item.sub_input or item.sub_input == "" or FilterMatch(item.sub_input, sub) then
                                            has_any_match = true
                                            table.insert(filtered_subs, {sub = sub, id = id})
                                        end
                                    end
                                    
                                    if has_any_match then
                                        for _, entry in ipairs(filtered_subs) do
                                            local is_selected = (sub_selected == entry.sub)
                                            if r.ImGui_Selectable(ctx, entry.sub .. "##" .. entry.id, is_selected) then
                                                item.sub_input = ""
                                                item.ucs_cat_id = entry.id
                                                -- 使用SyncFromID来同步所有字段（包括cat_zh_sel和sub_zh_sel）
                                                SyncFromID(item)
                                            end
                                            if is_selected then
                                                r.ImGui_SetItemDefaultFocus(ctx)
                                            end
                                        end
                                    end
                                    
                                    if item.sub_input and item.sub_input ~= "" and not has_any_match then
                                        local no_match_text = (app_state.display_language == "en") and "No match" or "无匹配项"
                                        r.ImGui_TextDisabled(ctx, no_match_text)
                                    end
                                else
                                    local no_cat_text = (app_state.display_language == "en") and "Select Category first" or "请先选择Category"
                                    r.ImGui_TextDisabled(ctx, no_cat_text)
                                end
                                
                                r.ImGui_EndCombo(ctx)
                            end

                            -- Col: CatID (只读) + Auto
                            r.ImGui_TableSetColumnIndex(ctx, 3)
                            
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
                                AutoMatchItem(item) 
                            end
                            
                            r.ImGui_PopStyleVar(ctx, 2)   -- 弹出 Padding 和 Rounding
                            r.ImGui_PopStyleColor(ctx, 4) -- 弹出颜色
                        end

                        -- Col: 原名 (Original Name) - 可编辑
                        local col_idx = app_state.use_ucs_mode and 4 or 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local c1, new_current = r.ImGui_InputText(ctx, "##current", item.current_name, r.ImGui_InputTextFlags_AutoSelectAll())
                        if c1 then
                            local old_current = item.current_name
                            item.current_name = new_current
                            
                            -- 如果trans_name和原current_name相同，也同步更新trans_name
                            if item.trans_name == old_current then
                                item.trans_name = new_current
                            end
                            
                            -- 如果new_name和原current_name相同，也同步更新new_name
                            if item.new_name == old_current then
                                item.new_name = new_current
                            end
                            
                            -- 更新状态
                            UpdateItemStatus(item)
                        end

                        -- Col: FXName (用户粘贴的结果)
                        col_idx = app_state.use_ucs_mode and 5 or 2
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local c2, new_nm = r.ImGui_InputText(ctx, "##nm", item.trans_name, r.ImGui_InputTextFlags_AutoSelectAll())
                        if c2 then
                            item.trans_name = new_nm
                            -- 修改FXName时，Preview自动跟着更新
                            UpdateFinalName(item)
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
                                    local valid, error_msg = ValidateField("vendor_category", new_vc)
                                    item.vendor_category = new_vc
                                    UpdateFinalName(item)
                                    if not valid then
                                        app_state.status_msg = error_msg
                                    end
                                end
                                -- 显示验证错误tooltip
                                if r.ImGui_IsItemHovered(ctx) and item.vendor_category and item.vendor_category ~= "" then
                                    local valid, error_msg = ValidateField("vendor_category", item.vendor_category)
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
                                    local valid, error_msg = ValidateField("creator_id", new_ci)
                                    item.creator_id = new_ci
                                    UpdateFinalName(item)
                                    if not valid then
                                        app_state.status_msg = error_msg
                                    end
                                end
                                if r.ImGui_IsItemHovered(ctx) and item.creator_id and item.creator_id ~= "" then
                                    local valid, error_msg = ValidateField("creator_id", item.creator_id)
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
                                    local valid, error_msg = ValidateField("source_id", new_si)
                                    item.source_id = new_si
                                    UpdateFinalName(item)
                                    if not valid then
                                        app_state.status_msg = error_msg
                                    end
                                end
                                if r.ImGui_IsItemHovered(ctx) and item.source_id and item.source_id ~= "" then
                                    local valid, error_msg = ValidateField("source_id", item.source_id)
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
                                    UpdateFinalName(item)
                                end
                            end
                        end

                        -- Col: Preview (只读的最终预览)
                        col_idx = col_idx + 1
                        r.ImGui_TableSetColumnIndex(ctx, col_idx)
                        
                        -- 根据状态设置文字颜色
                        local status_col = COLORS.TEXT_NORMAL
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
        
        -- 【布局微调】增加边距，让按钮更精致
        local button_padding = 4
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + button_padding)
        local button_width = r.ImGui_GetContentRegionAvail(ctx) - button_padding * 2
        
        if changes_count > 0 then
            if BtnPrimary(ctx, "APPLY " .. changes_count .. " CHANGES", button_width, 36) then
                ActionApply()
            end
        else
            r.ImGui_BeginDisabled(ctx)
            r.ImGui_Button(ctx, "NO CHANGES", button_width, 36)
            r.ImGui_EndDisabled(ctx)
        end

        -- [Footer: Status Log]
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0xAAAAAAFF, "Log: " .. app_state.status_msg)

        r.ImGui_End(ctx)
    end
    
    -- 还原样式
    r.ImGui_PopStyleVar(ctx, pop_vars)
    r.ImGui_PopStyleColor(ctx, pop_cols)

    if open then r.defer(Loop) end
end

if not reaper.APIExists('ImGui_GetVersion') then
    reaper.ShowMessageBox("Please install 'ReaImGui' via ReaPack.", "Error", 0)
else
    LoadUCSData()
    ReloadProjectData()
    r.defer(Loop)
end
