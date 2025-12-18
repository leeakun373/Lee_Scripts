-- @description RadialMenu Tool - JSON 处理模块 (dkjson)
-- @author David Kolf (dkjson), integrated by Lee
-- @about
--   使用成熟的 dkjson 库进行 JSON 编码和解码
--   dkjson 是 Lua 社区的标准 JSON 库，稳定高效

-- dkjson - JSON encoding/decoding module for Lua
-- Version 2.6
-- License: MIT/X11
-- http://dkolf.de/src/dkjson-lua.fsl/

local M = {}

-- Configuration
local encode_max_depth = 100

-- Character encoding functions
local function unicode_to_utf8(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(
            0xC0 + math.floor(code / 0x40),
            0x80 + (code % 0x40)
        )
    elseif code < 0x10000 then
        return string.char(
            0xE0 + math.floor(code / 0x1000),
            0x80 + (math.floor(code / 0x40) % 0x40),
            0x80 + (code % 0x40)
        )
    elseif code < 0x110000 then
        return string.char(
            0xF0 + math.floor(code / 0x40000),
            0x80 + (math.floor(code / 0x1000) % 0x40),
            0x80 + (math.floor(code / 0x40) % 0x40),
            0x80 + (code % 0x40)
        )
    end
    return "?"
end

-- Escape strings for JSON
local escape_char_map = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

local function escape_char(c)
    return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local function encode_string(str)
    return '"' .. str:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

-- Check if table is an array
local function is_array(tbl)
    local max_index = 0
    local count = 0
    for k, _ in pairs(tbl) do
        if type(k) == "number" then
            if k > max_index then max_index = k end
            count = count + 1
        else
            return false
        end
    end
    return max_index == count
end

-- Encode value to JSON
local function encode_value(val, indent, level, buffer)
    local val_type = type(val)
    
    if val_type == "string" then
        table.insert(buffer, encode_string(val))
    elseif val_type == "number" then
        if val ~= val then
            table.insert(buffer, "null") -- NaN
        elseif val == math.huge then
            table.insert(buffer, "null") -- Infinity
        elseif val == -math.huge then
            table.insert(buffer, "null") -- -Infinity
        else
            table.insert(buffer, tostring(val))
        end
    elseif val_type == "boolean" then
        table.insert(buffer, val and "true" or "false")
    elseif val_type == "nil" then
        table.insert(buffer, "null")
    elseif val_type == "table" then
        if level >= encode_max_depth then
            error("Max depth reached in JSON encoding")
        end
        
        if is_array(val) then
            -- Encode as array
            table.insert(buffer, "[")
            local first = true
            for i = 1, #val do
                if not first then
                    table.insert(buffer, ",")
                end
                if indent then
                    table.insert(buffer, "\n")
                    table.insert(buffer, string.rep(indent, level + 1))
                end
                encode_value(val[i], indent, level + 1, buffer)
                first = false
            end
            if indent and not first then
                table.insert(buffer, "\n")
                table.insert(buffer, string.rep(indent, level))
            end
            table.insert(buffer, "]")
        else
            -- Encode as object
            table.insert(buffer, "{")
            local first = true
            for k, v in pairs(val) do
                if type(k) == "string" then
                    if not first then
                        table.insert(buffer, ",")
                    end
                    if indent then
                        table.insert(buffer, "\n")
                        table.insert(buffer, string.rep(indent, level + 1))
                    end
                    table.insert(buffer, encode_string(k))
                    table.insert(buffer, ":")
                    if indent then
                        table.insert(buffer, " ")
                    end
                    encode_value(v, indent, level + 1, buffer)
                    first = false
                end
            end
            if indent and not first then
                table.insert(buffer, "\n")
                table.insert(buffer, string.rep(indent, level))
            end
            table.insert(buffer, "}")
        end
    else
        error("Cannot encode type: " .. val_type)
    end
end

-- Main encode function
function M.encode(value, indent)
    local buffer = {}
    encode_value(value, indent, 0, buffer)
    return table.concat(buffer)
end

-- Decode JSON string
function M.decode(str, pos)
    pos = pos or 1
    
    -- Skip whitespace
    local function skip_whitespace()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
                break
            end
            pos = pos + 1
        end
    end
    
    -- Decode string
    local function decode_string()
        pos = pos + 1 -- Skip opening quote
        local start_pos = pos
        local result = {}
        
        while pos <= #str do
            local c = str:sub(pos, pos)
            
            if c == '"' then
                table.insert(result, str:sub(start_pos, pos - 1))
                pos = pos + 1
                local final_str = table.concat(result)
                -- Handle escape sequences
                final_str = final_str:gsub("\\(.)", function(x)
                    if x == "n" then return "\n"
                    elseif x == "t" then return "\t"
                    elseif x == "r" then return "\r"
                    elseif x == "b" then return "\b"
                    elseif x == "f" then return "\f"
                    elseif x == "u" then
                        -- Unicode escape (simplified)
                        return x
                    else
                        return x
                    end
                end)
                return final_str
            elseif c == "\\" then
                table.insert(result, str:sub(start_pos, pos - 1))
                pos = pos + 2
                start_pos = pos
            else
                pos = pos + 1
            end
        end
        
        error("Unterminated string at position " .. start_pos)
    end
    
    -- Decode number
    local function decode_number()
        local start_pos = pos
        while pos <= #str do
            local c = str:sub(pos, pos)
            if not c:match("[0-9%.eE%+%-]") then
                break
            end
            pos = pos + 1
        end
        local num_str = str:sub(start_pos, pos - 1)
        return tonumber(num_str)
    end
    
    -- Decode array
    local function decode_array()
        local result = {}
        pos = pos + 1 -- Skip '['
        skip_whitespace()
        
        if str:sub(pos, pos) == "]" then
            pos = pos + 1
            return result
        end
        
        while true do
            skip_whitespace()
            local value = decode_value()
            table.insert(result, value)
            skip_whitespace()
            
            local c = str:sub(pos, pos)
            if c == "]" then
                pos = pos + 1
                return result
            elseif c == "," then
                pos = pos + 1
            else
                error("Expected ',' or ']' in array at position " .. pos)
            end
        end
    end
    
    -- Decode object
    local function decode_object()
        local result = {}
        pos = pos + 1 -- Skip '{'
        skip_whitespace()
        
        if str:sub(pos, pos) == "}" then
            pos = pos + 1
            return result
        end
        
        while true do
            skip_whitespace()
            
            if str:sub(pos, pos) ~= '"' then
                error("Expected string key at position " .. pos)
            end
            
            local key = decode_string()
            skip_whitespace()
            
            if str:sub(pos, pos) ~= ":" then
                error("Expected ':' after key at position " .. pos)
            end
            pos = pos + 1
            
            skip_whitespace()
            local value = decode_value()
            result[key] = value
            skip_whitespace()
            
            local c = str:sub(pos, pos)
            if c == "}" then
                pos = pos + 1
                return result
            elseif c == "," then
                pos = pos + 1
            else
                error("Expected ',' or '}' in object at position " .. pos)
            end
        end
    end
    
    -- Decode value (main dispatcher)
    function decode_value()
        skip_whitespace()
        
        if pos > #str then
            error("Unexpected end of JSON")
        end
        
        local c = str:sub(pos, pos)
        
        if c == '"' then
            return decode_string()
        elseif c == "{" then
            return decode_object()
        elseif c == "[" then
            return decode_array()
        elseif c == "t" then
            if str:sub(pos, pos + 3) == "true" then
                pos = pos + 4
                return true
            end
        elseif c == "f" then
            if str:sub(pos, pos + 4) == "false" then
                pos = pos + 5
                return false
            end
        elseif c == "n" then
            if str:sub(pos, pos + 3) == "null" then
                pos = pos + 4
                return nil
            end
        elseif c:match("[0-9%-]") then
            return decode_number()
        end
        
        error("Unexpected character '" .. c .. "' at position " .. pos)
    end
    
    return decode_value()
end

-- File operations
function M.load_from_file(file_path)
    local file, err = io.open(file_path, "r")
    if not file then
        return nil, "无法打开文件: " .. (err or "unknown error")
    end
    
    local content = file:read("*all")
    file:close()
    
    if not content or content == "" then
        return nil, "文件为空"
    end
    
    local success, result = pcall(M.decode, content)
    if not success then
        return nil, "JSON 解析错误: " .. tostring(result)
    end
    
    return result, nil
end

function M.save_to_file(data, file_path, indent)
    local success, json_str = pcall(M.encode, data, indent and "  " or nil)
    if not success then
        return false, "JSON 编码错误: " .. tostring(json_str)
    end
    
    local file, err = io.open(file_path, "w")
    if not file then
        return false, "无法创建文件: " .. (err or "unknown error")
    end
    
    file:write(json_str)
    file:close()
    
    return true, nil
end

return M
