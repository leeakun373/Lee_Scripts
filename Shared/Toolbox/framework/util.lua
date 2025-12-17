-- Shared/Toolbox/framework/util.lua
-- 一些通用工具：clamp、深拷贝、路径拼接、（安全）序列化/反序列化。

local M = {}

function M.clamp(x, lo, hi)
  if x == nil then return lo end
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function M.deepcopy(t, seen)
  if type(t) ~= "table" then return t end
  if seen and seen[t] then return seen[t] end
  seen = seen or {}
  local nt = {}
  seen[t] = nt
  for k, v in pairs(t) do
    nt[M.deepcopy(k, seen)] = M.deepcopy(v, seen)
  end
  return setmetatable(nt, getmetatable(t))
end

function M.path_join(...)
  local sep = package.config:sub(1, 1)
  local parts = {...}
  local out = ""
  for i = 1, #parts do
    local p = tostring(parts[i] or "")
    if p ~= "" then
      p = p:gsub("[\\/]+", sep)
      if out == "" then
        out = p
      else
        out = out:gsub("[\\/]+$", "") .. sep .. p:gsub("^[\\/]+", "")
      end
    end
  end
  return out
end

local function is_ident(s)
  return type(s) == "string" and s:match("^[%a_][%w_]*$") ~= nil
end

local function esc_str(s)
  return string.format("%q", s)
end

function M.serialize(tbl)
  -- 只支持：nil/boolean/number/string/table(数组或键值)
  local function ser(v)
    local tv = type(v)
    if tv == "nil" then
      return "nil"
    elseif tv == "boolean" then
      return v and "true" or "false"
    elseif tv == "number" then
      if v ~= v then return "0/0" end
      if v == math.huge then return "math.huge" end
      if v == -math.huge then return "-math.huge" end
      return tostring(v)
    elseif tv == "string" then
      return esc_str(v)
    elseif tv == "table" then
      local items = {}
      -- 先看是否是纯数组
      local n = #v
      local is_array = true
      local count = 0
      for k in pairs(v) do
        count = count + 1
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
          is_array = false
        end
      end
      if is_array and count == n then
        for i = 1, n do
          items[#items+1] = ser(v[i])
        end
        return "{" .. table.concat(items, ",") .. "}"
      end

      -- 键值表
      local keys = {}
      for k in pairs(v) do keys[#keys+1] = k end
      table.sort(keys, function(a, b)
        if type(a) == type(b) then return tostring(a) < tostring(b) end
        return type(a) < type(b)
      end)

      for _, k in ipairs(keys) do
        local kk
        if is_ident(k) then
          kk = k
        else
          kk = "[" .. ser(k) .. "]"
        end
        items[#items+1] = kk .. "=" .. ser(v[k])
      end
      return "{" .. table.concat(items, ",") .. "}"
    else
      error("unsupported type: " .. tv)
    end
  end

  return ser(tbl)
end

function M.deserialize(str)
  if type(str) ~= "string" or str == "" then
    return nil, "empty"
  end

  -- 沙箱环境：只允许 math.huge
  local env = { math = { huge = math.huge } }
  local chunk, err = load("return " .. str, "Toolbox.deserialize", "t", env)
  if not chunk then
    return nil, err
  end
  local ok, res = pcall(chunk)
  if not ok then
    return nil, res
  end
  return res
end

return M
