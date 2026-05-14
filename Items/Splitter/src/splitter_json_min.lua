-- Minimal JSON decoder for Splitter CLI stdout (flat object with string paths).
-- Logic adapted from SonicCompass_Spot/spot_listener.lua (json_parse).

local M = {}

function M.decode(s)
  if type(s) ~= "string" or #s == 0 then
    return nil, "empty"
  end

  if s:sub(1, 3) == "\239\187\191" then
    s = s:sub(4)
  end

  local brace = s:find("{")
  if not brace then
    return nil, "no_brace"
  end
  s = s:sub(brace)

  local pos = 1
  local len = #s

  local function err(msg)
    error(msg .. " at pos " .. tostring(pos), 0)
  end

  local function skip_ws()
    while pos <= len do
      local b = s:byte(pos)
      if b == 32 or b == 9 or b == 10 or b == 13 then
        pos = pos + 1
      else
        return
      end
    end
  end

  local parse_value

  local function parse_string()
    pos = pos + 1
    local out = {}
    while pos <= len do
      local c = s:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return table.concat(out)
      elseif c == "\\" then
        pos = pos + 1
        local esc = s:sub(pos, pos)
        if esc == '"' then
          out[#out + 1] = '"'
        elseif esc == "\\" then
          out[#out + 1] = "\\"
        elseif esc == "/" then
          out[#out + 1] = "/"
        elseif esc == "n" then
          out[#out + 1] = "\n"
        elseif esc == "t" then
          out[#out + 1] = "\t"
        elseif esc == "r" then
          out[#out + 1] = "\r"
        elseif esc == "b" then
          out[#out + 1] = "\b"
        elseif esc == "f" then
          out[#out + 1] = "\f"
        elseif esc == "u" then
          local hex = s:sub(pos + 1, pos + 4)
          local cp = tonumber(hex, 16)
          if cp then
            if cp < 0x80 then
              out[#out + 1] = string.char(cp)
            elseif cp < 0x800 then
              out[#out + 1] = string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
            else
              out[#out + 1] = string.char(
                0xE0 + math.floor(cp / 0x1000),
                0x80 + math.floor((cp % 0x1000) / 0x40),
                0x80 + (cp % 0x40)
              )
            end
          end
          pos = pos + 4
        else
          out[#out + 1] = esc
        end
        pos = pos + 1
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    err("unterminated string")
  end

  local function parse_number()
    local start = pos
    if s:sub(pos, pos) == "-" then
      pos = pos + 1
    end
    while pos <= len do
      local c = s:sub(pos, pos)
      if c:match("[%d%.eE%+%-]") then
        pos = pos + 1
      else
        break
      end
    end
    return tonumber(s:sub(start, pos - 1))
  end

  local function parse_array()
    pos = pos + 1
    local arr = {}
    skip_ws()
    if s:sub(pos, pos) == "]" then
      pos = pos + 1
      return arr
    end
    while true do
      skip_ws()
      arr[#arr + 1] = parse_value()
      skip_ws()
      local c = s:sub(pos, pos)
      if c == "," then
        pos = pos + 1
      elseif c == "]" then
        pos = pos + 1
        return arr
      else
        err("expected , or ] in array")
      end
    end
  end

  local function parse_object()
    pos = pos + 1
    local obj = {}
    skip_ws()
    if s:sub(pos, pos) == "}" then
      pos = pos + 1
      return obj
    end
    while true do
      skip_ws()
      if s:sub(pos, pos) ~= '"' then
        err("expected string key")
      end
      local key = parse_string()
      skip_ws()
      if s:sub(pos, pos) ~= ":" then
        err("expected : after key")
      end
      pos = pos + 1
      skip_ws()
      obj[key] = parse_value()
      skip_ws()
      local c = s:sub(pos, pos)
      if c == "," then
        pos = pos + 1
      elseif c == "}" then
        pos = pos + 1
        return obj
      else
        err("expected , or } in object")
      end
    end
  end

  parse_value = function()
    skip_ws()
    local c = s:sub(pos, pos)
    if c == '"' then
      return parse_string()
    elseif c == "{" then
      return parse_object()
    elseif c == "[" then
      return parse_array()
    elseif c == "t" and s:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif c == "f" and s:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif c == "n" and s:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    else
      return parse_number()
    end
  end

  local ok, result = pcall(parse_value)
  if not ok then
    return nil, tostring(result)
  end
  return result
end

return M
