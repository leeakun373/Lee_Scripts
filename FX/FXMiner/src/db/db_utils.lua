-- FXMiner/src/db/db_utils.lua
-- 工具函数：路径处理、文件操作、哈希等

local json = require("json")

local Utils = {}

-- Time utilities
function Utils.now_sec()
  return os.time()
end

-- Directory utilities
function Utils.ensure_dir(path)
  -- best effort
  local r = reaper
  if r and r.RecursiveCreateDirectory then
    pcall(function()
      r.RecursiveCreateDirectory(path, 0)
    end)
  end
end

-- Error handling
function Utils.show_error(msg)
  local r = reaper
  if r and r.ShowMessageBox then
    r.ShowMessageBox(tostring(msg or "Unknown error"), "FXMiner", 0)
  end
end

-- File operations
function Utils.read_all(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*all")
  f:close()
  return s
end

function Utils.file_exists(path)
  if type(path) ~= "string" or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

function Utils.write_all(path, content)
  -- Use text mode ("w") instead of binary mode ("wb") to preserve line breaks
  local f, err = io.open(path, "w")
  if not f then
    return false, err
  end
  f:write(tostring(content or ""))
  f:close()
  return true
end

-- Path utilities
function Utils.path_join(a, b)
  local sep = package.config:sub(1, 1)
  a = tostring(a or ""):gsub("[\\/]+$", "")
  b = tostring(b or ""):gsub("^[\\/]+", "")
  if a == "" then return b end
  if b == "" then return a end
  return a .. sep .. b
end

function Utils.split_slash(p)
  local t = {}
  for part in tostring(p or ""):gmatch("[^/]+") do
    t[#t + 1] = part
  end
  return t
end

function Utils.split_any_sep(p)
  local s = tostring(p or ""):gsub("\\", "/")
  return Utils.split_slash(s)
end

function Utils.join_with_sep(parts, sep)
  return table.concat(parts, sep or package.config:sub(1, 1))
end

function Utils.norm_abs_path(abs_path)
  -- best effort: normalize separators and collapse ./.. segments
  local sep = package.config:sub(1, 1)
  local s = tostring(abs_path or ""):gsub("\\", "/")

  -- Extract drive prefix (Windows) like C:
  local drive = s:match("^(%a:)")
  if drive then
    s = s:sub(#drive + 1)
  end

  local leading_slash = s:sub(1, 1) == "/"
  local parts = Utils.split_slash(s)
  local out = {}
  for _, p in ipairs(parts) do
    if p == "" or p == "." then
      -- skip
    elseif p == ".." then
      if #out > 0 then
        table.remove(out, #out)
      end
    else
      out[#out + 1] = p
    end
  end

  local path = Utils.join_with_sep(out, "/")
  if leading_slash then
    path = "/" .. path
  end
  if drive then
    path = drive .. path
  end
  path = path:gsub("/", sep)
  return path
end

-- String utilities
function Utils.lower(s)
  return tostring(s):lower()
end

function Utils.trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function Utils.add_unique(arr, value)
  if type(arr) ~= "table" then return end
  value = Utils.trim(value)
  if value == "" then return end
  for _, v in ipairs(arr) do
    if tostring(v) == value then return end
  end
  arr[#arr + 1] = value
end

-- Hash utilities
function Utils.hash32(s)
  -- djb2 (no bitops)
  local h = 5381
  s = tostring(s or "")
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

return Utils

