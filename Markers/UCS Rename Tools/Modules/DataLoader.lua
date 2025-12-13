--[[
  Data loading module for UCS Rename Tools
  Handles CSV file loading and database initialization
]]

local DataLoader = {}

function DataLoader.LoadUserAlias(ucs_db, script_path, csv_alias_file, helpers)
    local path = script_path .. csv_alias_file
    local file = io.open(path, "r")
    ucs_db.alias_list = {} 
    if not file then return end
    
    for line in file:lines() do
        local cols = helpers.ParseCSVLine(line)
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

function DataLoader.SaveUserAlias(script_path, csv_alias_file, source, target)
    local path = script_path .. csv_alias_file
    local file = io.open(path, "a")  -- Append mode
    if not file then 
        return false, "Failed to open alias file for writing"
    end
    
    -- Write new alias entry (source and target already cleaned)
    file:write(source .. "," .. target .. "\n")
    file:close()
    return true, "Alias saved successfully"
end

function DataLoader.LoadUCSData(ucs_db, app_state, script_path, csv_db_file, csv_alias_file, helpers)
    local path = script_path .. csv_db_file
    local file = io.open(path, "r")
    
    if not file then
        app_state.status_msg = "Note: " .. csv_db_file .. " not found (UCS disabled)."
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

    for line in file:lines() do
        local cols = helpers.ParseCSVLine(line)
        
        -- Skip header/metadata rows:
        -- 1. Lines containing "UCS v" in first column (e.g., ",UCS v8.2.1")
        -- 2. Lines where first column equals "Category" (the actual header)
        -- 3. Empty lines or lines with insufficient columns
        local first_col = cols[1] or ""
        local is_invalid_row = (
            first_col:match("UCS") or 
            first_col == "Category" or 
            first_col == "" or
            #cols < 8
        )
        
        if not is_invalid_row and #cols >= 8 then
                local cat_en_raw = cols[1]  -- 原始英文字符串
                local sub_en_raw = cols[2]  -- 原始英文字符串
                local d = {
                    id      = cols[3], 
                    cat_en  = helpers.Tokenize(cols[1]),
                    sub_en  = helpers.Tokenize(cols[2]),
                    desc    = helpers.Tokenize(cols[5]),
                    syn_en  = helpers.Tokenize(cols[6]),
                    cat_zh  = cols[7], 
                    sub_zh  = cols[8], 
                    syn_zh  = helpers.Tokenize(cols[9]),
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
    file:close()
    
    -- Load aliases after DB
    DataLoader.LoadUserAlias(ucs_db, script_path, csv_alias_file, helpers)
    
    app_state.status_msg = string.format("Engine Ready: Loaded %d UCS definitions.", #ucs_db.flat_list)
    return true
end

return DataLoader






