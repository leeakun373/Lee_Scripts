--[[
  Helper functions for UCS Rename Tools
]]

local Helpers = {}

-- Get script directory path
function Helpers.GetScriptPath()
    local info = debug.getinfo(1, 'S');
    return info.source:match[[^@?(.*[\/])[^\/]-$]]
end

-- Parse CSV line (handles quoted fields)
function Helpers.ParseCSVLine(s)
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

-- Tokenize string into words (supports Unicode)
function Helpers.Tokenize(str)
    local tokens = {}
    if not str then return tokens end
    for word in str:lower():gmatch("[%w\128-\255]+") do
        table.insert(tokens, word)
    end
    return tokens
end

-- Escape pattern characters for string matching
function Helpers.EscapePattern(text)
    return text:gsub("([^%w])", "%%%1")
end

-- Filter match function (case-insensitive substring search)
function Helpers.FilterMatch(input_text, target_text)
    if not input_text or input_text == "" then return true end
    if not target_text then return false end
    -- 转换为小写进行模糊匹配
    local input_lower = input_text:lower()
    local target_lower = target_text:lower()
    -- 检查是否包含输入文本
    return target_lower:find(input_lower, 1, true) ~= nil
end

return Helpers






























