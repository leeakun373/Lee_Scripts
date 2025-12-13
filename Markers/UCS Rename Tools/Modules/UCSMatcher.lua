--[[
  UCS matching module for UCS Rename Tools
  Handles intelligent matching of user input to UCS categories
]]

local UCSMatcher = {}

function UCSMatcher.FindBestUCS(user_input, ucs_db, weights, match_threshold, downgrade_words, helpers, safe_dominant_keywords)
    if not user_input or user_input == "" then return nil end
    
    -- 1. Pre-processing: Phrase Substitution using Alias List
    local processed_input = user_input:lower()
    for _, alias in ipairs(ucs_db.alias_list) do
        local esc_key = helpers.EscapePattern(alias.key)
        processed_input = processed_input:gsub(esc_key, " " .. alias.val .. " ") 
    end
    
    local input_words = helpers.Tokenize(processed_input)
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
                local is_weak = downgrade_words[word] == true
                
                -- Score Logic
                -- A. Category Match Logic (with Safe Dominant Bonus)
                for _, k in ipairs(item.cat_en) do
                    if k == word then 
                        current_score = current_score + weights.CATEGORY_EXACT
                        cat_hit = true
                        
                        -- Apply bonus for safe dominant keywords (e.g., water, glass, ice)
                        if safe_dominant_keywords and safe_dominant_keywords[word] then
                            current_score = current_score + weights.SAFE_DOMINANT_BONUS
                        end
                    elseif k:find(word, 1, true) then 
                        current_score = current_score + weights.CATEGORY_PART 
                    end
                end
                
                for _, k in ipairs(item.sub_en) do
                    if k == word then 
                        if is_weak then 
                            current_score = current_score + 5
                        else 
                            current_score = current_score + weights.SUBCATEGORY
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
                            current_score = current_score + weights.SYNONYM
                            sub_hit = true 
                        end
                    end
                end
                
                for _, k in ipairs(item.desc) do
                    if k == word then 
                        current_score = current_score + weights.DESCRIPTION 
                    end
                end
            end
        end
        
        if cat_hit and sub_hit then 
            current_score = current_score + weights.PERFECT_BONUS 
        end
        
        if is_general and current_score < 30 then 
            current_score = current_score - 15 
        end
        
        if current_score > best_score then
            best_score = current_score
            best_match = item
        end
    end
    
    if best_score >= match_threshold then return best_match end
    return nil
end

return UCSMatcher



