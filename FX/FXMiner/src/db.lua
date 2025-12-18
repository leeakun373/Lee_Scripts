-- FXMiner/src/db.lua
-- 影子数据库：唯一允许读写 JSON 的模块

local json = require("json")

local DB = {}
DB.__index = DB

local function now_sec()
  return os.time()
end

local function ensure_dir(path)
  -- best effort
  local r = reaper
  if r and r.RecursiveCreateDirectory then
    pcall(function()
      r.RecursiveCreateDirectory(path, 0)
    end)
  end
end

local function show_error(msg)
  local r = reaper
  if r and r.ShowMessageBox then
    r.ShowMessageBox(tostring(msg or "Unknown error"), "FXMiner", 0)
  end
end

local function read_all(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*all")
  f:close()
  return s
end

local function file_exists(path)
  if type(path) ~= "string" or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function write_all(path, content)
  local f, err = io.open(path, "wb")
  if not f then
    return false, err
  end
  f:write(tostring(content or ""))
  f:close()
  return true
end

local function path_join(a, b)
  local sep = package.config:sub(1, 1)
  a = tostring(a or ""):gsub("[\\/]+$", "")
  b = tostring(b or ""):gsub("^[\\/]+", "")
  if a == "" then return b end
  if b == "" then return a end
  return a .. sep .. b
end

local function split_slash(p)
  local t = {}
  for part in tostring(p or ""):gmatch("[^/]+") do
    t[#t + 1] = part
  end
  return t
end

local function split_any_sep(p)
  local s = tostring(p or ""):gsub("\\", "/")
  return split_slash(s)
end

local function join_with_sep(parts, sep)
  return table.concat(parts, sep or package.config:sub(1, 1))
end

local function norm_abs_path(abs_path)
  -- best effort: normalize separators and collapse ./.. segments
  local sep = package.config:sub(1, 1)
  local s = tostring(abs_path or ""):gsub("\\", "/")

  -- Extract drive prefix (Windows) like C:
  local drive = s:match("^(%a:)")
  if drive then
    s = s:sub(#drive + 1)
  end

  local leading_slash = s:sub(1, 1) == "/"
  local parts = split_slash(s)
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

  local path = join_with_sep(out, "/")
  if leading_slash then
    path = "/" .. path
  end
  if drive then
    path = drive .. path
  end
  path = path:gsub("/", sep)
  return path
end

local function lower(s)
  return tostring(s):lower()
end

local function hash32(s)
  -- djb2 (no bitops)
  local h = 5381
  s = tostring(s or "")
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

function DB:new(cfg)
  local o = setmetatable({}, self)
  o.cfg = cfg or require("config")
  o.data = nil
  o._index = {}
  -- legacy (previous static tags config)
  o.tag_config = nil
  o.tag_config_path = nil

  -- dynamic fields config (new)
  o.fields_config = nil
  o.fields_config_path = nil

  -- folders db (new)
  o.folders = nil
  o.folders_path = nil
  return o
end

function DB:db_dir()
  return self.cfg.DATA_DIR_PATH
end

function DB:db_path()
  return self.cfg.DB_PATH
end

function DB:_reindex()
  self._index = {}
  if not self.data or not self.data.entries then return end
  for _, e in ipairs(self.data.entries) do
    if e and e.rel_path then
      self._index[e.rel_path] = e
    end
  end
end

local function ensure_array(v)
  if type(v) == "table" then return v end
  if v == nil then return {} end
  return { v }
end

local function any_field_has_values(meta)
  if type(meta) ~= "table" then return false end
  for k, v in pairs(meta) do
    if k ~= "Category" and type(v) == "table" and #v > 0 then
      return true
    end
  end
  return false
end

local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function add_unique(arr, value)
  if type(arr) ~= "table" then return end
  value = trim(value)
  if value == "" then return end
  for _, v in ipairs(arr) do
    if tostring(v) == value then return end
  end
  arr[#arr + 1] = value
end

-- Default fields config: simple array of {key, label}
local function default_fields_config()
  return {
    { key = "Designer", label = "Designer" },
    { key = "Project",  label = "Project" },
    { key = "Keywords", label = "Keywords" },
  }
end

-- ---- Dynamic fields config (Source of Truth) ----
function DB:load_fields_config(script_root)
  local root = tostring(script_root or "")
  if root == "" then
    return false, "script_root missing"
  end

  local path = path_join(root, "config_fields.json")
  self.fields_config_path = path

  if not file_exists(path) then
    local ok, err = json.save_to_file(default_fields_config(), path, true)
    if not ok then
      return false, err
    end
  end

  local data, err = json.load_from_file(path)
  if not data then
    return false, err
  end

  -- Accept array format; fallback to default if not array
  if type(data) ~= "table" or #data == 0 then
    data = default_fields_config()
  end

  self.fields_config = data
  return true
end

function DB:get_fields_config()
  return self.fields_config or default_fields_config()
end

function DB:get_fields_config_path()
  return self.fields_config_path
end

function DB:_ensure_entry_defaults(e)
  if type(e) ~= "table" then return end

  e.folder_id = tonumber(e.folder_id) or 0

  e.metadata = e.metadata or {}
  if type(e.metadata) ~= "table" then
    e.metadata = {}
  end

  -- All metadata fields are stored as strings (simple model)
  local fields = self:get_fields_config()
  for _, f in ipairs(fields) do
    local k = type(f) == "table" and tostring(f.key or "") or ""
    if k ~= "" then
      local v = e.metadata[k]
      -- Convert array to comma-separated string if needed (legacy migration)
      if type(v) == "table" then
        local parts = {}
        for _, it in ipairs(v) do
          local s = trim(tostring(it or ""))
          if s ~= "" then parts[#parts + 1] = s end
        end
        e.metadata[k] = table.concat(parts, ", ")
      else
        e.metadata[k] = tostring(v or "")
      end
    end
  end

  e.status = (e.status == "indexed" or e.status == "unindexed") and e.status or "unindexed"
  e.keywords = tostring(e.keywords or "")
  e.name = tostring(e.name or "")
  e.description = tostring(e.description or "")
  e.plugins = e.plugins or {}
end

function DB:calc_status(e)
  self:_ensure_entry_defaults(e)
  -- Check if any metadata field has non-empty value
  for k, v in pairs(e.metadata or {}) do
    if trim(tostring(v or "")) ~= "" then
      return "indexed"
    end
  end
  return "unindexed"
end

function DB:rebuild_keywords(e)
  self:_ensure_entry_defaults(e)

  local tokens = {}
  local seen = {}

  local function add_token(x)
    x = tostring(x or ""):lower()
    x = x:gsub("^%s+", ""):gsub("%s+$", "")
    if x == "" then return end
    if seen[x] then return end
    seen[x] = true
    tokens[#tokens + 1] = x
  end

  add_token(e.name)
  add_token(e.description)

  -- Add all metadata field values (they are strings now)
  for k, v in pairs(e.metadata or {}) do
    add_token(v)
  end

  e.keywords = table.concat(tokens, " ")
  return e.keywords
end

function DB:update_entry(e, opts)
  opts = opts or {}
  self:_ensure_entry_defaults(e)
  e.updated_at = now_sec()
  e.status = self:calc_status(e)
  self:rebuild_keywords(e)
  if opts.save ~= false then
    self:save()
  end
  return true
end

function DB:migrate_entries(opts)
  opts = opts or {}
  if not self.data or type(self.data.entries) ~= "table" then
    return true
  end

  for _, e in ipairs(self.data.entries) do
    self:_ensure_entry_defaults(e)
    e.status = self:calc_status(e)
    self:rebuild_keywords(e)
  end
  self:_reindex()
  if opts.save ~= false then
    self:save()
  end
  return true
end

-- CollectUsedTags/Values for a specific field key (dynamic collection)
function DB:collect_used_values(key)
  key = tostring(key or "")
  if key == "" then return {} end

  local values = {}
  local seen = {}

  for _, e in ipairs(self:entries()) do
    self:_ensure_entry_defaults(e)
    if tostring(e.status) == "indexed" then
      if key == "Category" then
        local v = trim(e.metadata.Category)
        if v ~= "" and not seen[v] then
          seen[v] = true
          values[#values + 1] = v
        end
      else
        local arr = e.metadata[key]
        if type(arr) == "table" then
          for _, it in ipairs(arr) do
            local v = trim(it)
            if v ~= "" and not seen[v] then
              seen[v] = true
              values[#values + 1] = v
            end
          end
        end
      end
    end
  end

  table.sort(values, function(a, b) return a:lower() < b:lower() end)
  return values
end

-- ---- Folders DB (virtual folders) ----
local function default_folders_db()
  return {
    next_id = 1,
    folders_by_id = {
      ["0"] = { id = 0, name = "Root", parent_id = nil },
    },
  }
end

local function normalize_folders_db(data)
  if type(data) ~= "table" then
    data = default_folders_db()
  end
  data.next_id = tonumber(data.next_id) or 1
  if type(data.folders_by_id) ~= "table" then
    data.folders_by_id = default_folders_db().folders_by_id
  end
  -- ensure root exists
  if type(data.folders_by_id["0"]) ~= "table" then
    data.folders_by_id["0"] = { id = 0, name = "Root", parent_id = nil }
  end
  if data.folders_by_id["0"].id ~= 0 then
    data.folders_by_id["0"].id = 0
  end
  if data.folders_by_id["0"].name == nil or data.folders_by_id["0"].name == "" then
    data.folders_by_id["0"].name = "Root"
  end

  -- ordering: add sort index (stable manual order)
  -- migration rule: if missing, use id order within each parent
  local by_parent = {}
  for _, f in pairs(data.folders_by_id) do
    if type(f) == "table" then
      local pid = f.parent_id
      local key = pid == nil and "nil" or tostring(tonumber(pid) or 0)
      by_parent[key] = by_parent[key] or {}
      table.insert(by_parent[key], f)
    end
  end
  for _, arr in pairs(by_parent) do
    table.sort(arr, function(a, b)
      local sa = tonumber(a.sort)
      local sb = tonumber(b.sort)
      if sa and sb then return sa < sb end
      if sa and not sb then return true end
      if sb and not sa then return false end
      return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    local idx = 0
    for _, f in ipairs(arr) do
      -- keep root sort 0
      if tonumber(f.id) == 0 then
        f.sort = 0
      else
        idx = idx + 1
        f.sort = tonumber(f.sort) or idx
      end
    end
  end
  return data
end

function DB:load_folders(script_root)
  local root = tostring(script_root or "")
  if root == "" then
    return false, "script_root missing"
  end

  local path = path_join(root, "folders_db.json")
  self.folders_path = path

  if not file_exists(path) then
    local ok, err = json.save_to_file(default_folders_db(), path, true)
    if not ok then
      return false, err
    end
  end

  local data, err = json.load_from_file(path)
  if not data then
    return false, err
  end

  self.folders = normalize_folders_db(data)
  return true
end

function DB:save_folders()
  if not self.folders_path or self.folders_path == "" then
    return false, "folders_db path missing"
  end
  self.folders = normalize_folders_db(self.folders)
  return json.save_to_file(self.folders, self.folders_path, true)
end

function DB:get_folders()
  self.folders = normalize_folders_db(self.folders)
  return self.folders
end

function DB:get_folder(id)
  self.folders = normalize_folders_db(self.folders)
  id = tonumber(id) or 0
  return self.folders.folders_by_id[tostring(id)]
end

function DB:get_folder_name(id)
  local f = self:get_folder(id)
  return (f and tostring(f.name)) or ""
end

function DB:list_children(parent_id)
  self.folders = normalize_folders_db(self.folders)
  parent_id = parent_id == nil and nil or tonumber(parent_id)
  local out = {}
  for _, f in pairs(self.folders.folders_by_id) do
    if type(f) == "table" then
      local pid = f.parent_id
      if pid == nil and parent_id == nil then
        out[#out + 1] = f
      elseif tonumber(pid) == tonumber(parent_id) then
        out[#out + 1] = f
      end
    end
  end
  table.sort(out, function(a, b)
    local sa = tonumber(a.sort) or 0
    local sb = tonumber(b.sort) or 0
    if sa ~= sb then return sa < sb end
    return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
  end)
  return out
end

local function renumber_sorts(folders_by_id, parent_id)
  local arr = {}
  for _, f in pairs(folders_by_id) do
    if type(f) == "table" and tonumber(f.id) ~= 0 and tonumber(f.parent_id) == tonumber(parent_id) then
      arr[#arr + 1] = f
    end
  end
  table.sort(arr, function(a, b)
    local sa = tonumber(a.sort) or 0
    local sb = tonumber(b.sort) or 0
    if sa ~= sb then return sa < sb end
    return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
  end)
  for i, f in ipairs(arr) do
    f.sort = i
  end
end

function DB:create_folder(name, parent_id, opts)
  self.folders = normalize_folders_db(self.folders)
  name = trim(name)
  if name == "" then return false, "Folder name empty" end
  parent_id = tonumber(parent_id) or 0
  opts = type(opts) == "table" and opts or {}

  local id = tonumber(self.folders.next_id) or 1
  self.folders.next_id = id + 1

  local insert_after_id = tonumber(opts.insert_after_id)
  local after_sort = nil
  if insert_after_id and insert_after_id > 0 then
    local af = self.folders.folders_by_id[tostring(insert_after_id)]
    if af and tonumber(af.parent_id) == parent_id then
      after_sort = tonumber(af.sort) or 0
    end
  end

  local max_sort = 0
  for _, f in pairs(self.folders.folders_by_id) do
    if type(f) == "table" and tonumber(f.id) ~= 0 and tonumber(f.parent_id) == parent_id then
      local s = tonumber(f.sort) or 0
      if s > max_sort then max_sort = s end
    end
  end

  local new_sort
  if after_sort then
    -- shift items after "after_sort" to make room
    for _, f in pairs(self.folders.folders_by_id) do
      if type(f) == "table" and tonumber(f.id) ~= 0 and tonumber(f.parent_id) == parent_id then
        local s = tonumber(f.sort) or 0
        if s > after_sort then
          f.sort = s + 1
        end
      end
    end
    new_sort = after_sort + 1
  else
    new_sort = max_sort + 1
  end

  self.folders.folders_by_id[tostring(id)] = { id = id, name = name, parent_id = parent_id, sort = new_sort }
  renumber_sorts(self.folders.folders_by_id, parent_id)
  self:save_folders()
  return true, id
end

local function folder_is_descendant(folders_by_id, folder_id, maybe_parent_id)
  -- returns true if maybe_parent_id is inside folder_id subtree
  folder_id = tonumber(folder_id)
  maybe_parent_id = tonumber(maybe_parent_id)
  if folder_id == nil or maybe_parent_id == nil then return false end
  if folder_id == maybe_parent_id then return true end

  local cur = folders_by_id[tostring(maybe_parent_id)]
  local guard = 0
  while cur and guard < 256 do
    guard = guard + 1
    local pid = cur.parent_id
    if pid == nil then return false end
    if tonumber(pid) == folder_id then
      return true
    end
    cur = folders_by_id[tostring(pid)]
  end
  return false
end

function DB:rename_folder(id, new_name)
  self.folders = normalize_folders_db(self.folders)
  id = tonumber(id) or 0
  if id == 0 then
    return false, "Cannot rename Root"
  end
  new_name = trim(new_name)
  if new_name == "" then
    return false, "Folder name empty"
  end
  local f = self.folders.folders_by_id[tostring(id)]
  if not f then
    return false, "Folder not found"
  end
  f.name = new_name
  self:save_folders()
  return true
end

function DB:move_folder(id, new_parent_id)
  self.folders = normalize_folders_db(self.folders)
  id = tonumber(id) or 0
  new_parent_id = tonumber(new_parent_id) or 0
  if id == 0 then
    return false, "Cannot move Root"
  end
  local f = self.folders.folders_by_id[tostring(id)]
  if not f then
    return false, "Folder not found"
  end
  if folder_is_descendant(self.folders.folders_by_id, id, new_parent_id) then
    return false, "Invalid parent (cycle)"
  end
  local old_parent = tonumber(f.parent_id) or 0
  f.parent_id = new_parent_id
  -- move to end of new parent
  local max_sort = 0
  for _, sf in pairs(self.folders.folders_by_id) do
    if type(sf) == "table" and tonumber(sf.id) ~= 0 and tonumber(sf.parent_id) == new_parent_id then
      local s = tonumber(sf.sort) or 0
      if s > max_sort then max_sort = s end
    end
  end
  f.sort = max_sort + 1
  renumber_sorts(self.folders.folders_by_id, old_parent)
  renumber_sorts(self.folders.folders_by_id, new_parent_id)
  self:save_folders()
  return true
end

function DB:create_parent_folder(child_id, name)
  self.folders = normalize_folders_db(self.folders)
  child_id = tonumber(child_id) or 0
  if child_id == 0 then
    return false, "Cannot wrap Root"
  end
  local child = self.folders.folders_by_id[tostring(child_id)]
  if not child then
    return false, "Child folder not found"
  end
  local parent_id = tonumber(child.parent_id) or 0
  local child_sort = tonumber(child.sort) or 1
  local ok, new_id_or_err = self:create_folder(name, parent_id, { insert_after_id = nil })
  if not ok then
    return false, new_id_or_err
  end
  local new_id = tonumber(new_id_or_err)
  -- place new parent at child's position in the sibling order
  local new_parent = self.folders.folders_by_id[tostring(new_id)]
  if new_parent then
    new_parent.sort = child_sort
  end
  -- shift siblings after child's slot (excluding new parent)
  for _, f in pairs(self.folders.folders_by_id) do
    if type(f) == "table" and tonumber(f.id) ~= 0 and tonumber(f.parent_id) == parent_id and tonumber(f.id) ~= new_id then
      local s = tonumber(f.sort) or 0
      if s >= child_sort then
        f.sort = s + 1
      end
    end
  end
  -- move child under new parent and make it first
  child.parent_id = new_id
  child.sort = 1
  renumber_sorts(self.folders.folders_by_id, parent_id)
  renumber_sorts(self.folders.folders_by_id, new_id)
  self:save_folders()
  return true, new_id
end

function DB:delete_folder(id)
  self.folders = normalize_folders_db(self.folders)
  id = tonumber(id) or 0
  if id == 0 then
    return false, "Cannot delete Root"
  end
  local f = self.folders.folders_by_id[tostring(id)]
  if not f then
    return false, "Folder not found"
  end
  local parent_id = tonumber(f.parent_id) or 0
  local deleted_sort = tonumber(f.sort) or 1

  -- move entries in this folder to parent
  if self.data and type(self.data.entries) == "table" then
    for _, e in ipairs(self.data.entries) do
      if e and tonumber(e.folder_id) == id then
        e.folder_id = parent_id
      end
    end
    self:save()
  end

  -- collect children folders (keep their order)
  local kids = {}
  for _, cf in pairs(self.folders.folders_by_id) do
    if type(cf) == "table" and tonumber(cf.parent_id) == id then
      kids[#kids + 1] = cf
    end
  end
  table.sort(kids, function(a, b)
    local sa = tonumber(a.sort) or 0
    local sb = tonumber(b.sort) or 0
    if sa ~= sb then return sa < sb end
    return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
  end)

  local delta = #kids - 1
  -- shift existing siblings after deleted slot
  for _, sf in pairs(self.folders.folders_by_id) do
    if type(sf) == "table" and tonumber(sf.id) ~= 0 and tonumber(sf.parent_id) == parent_id and tonumber(sf.id) ~= id then
      local s = tonumber(sf.sort) or 0
      if s > deleted_sort then
        sf.sort = s + delta
      end
    end
  end
  -- reparent children into parent, inserted at deleted slot
  for i, cf in ipairs(kids) do
    cf.parent_id = parent_id
    cf.sort = deleted_sort + (i - 1)
  end

  -- delete folder
  self.folders.folders_by_id[tostring(id)] = nil
  renumber_sorts(self.folders.folders_by_id, parent_id)
  self:save_folders()
  return true
end

function DB:set_entry_folder(rel_path, folder_id)
  rel_path = tostring(rel_path or "")
  if rel_path == "" then return false, "rel_path missing" end
  folder_id = tonumber(folder_id) or 0
  local e = self:find_entry_by_rel(rel_path)
  if not e then return false, "Entry not found" end
  e.folder_id = folder_id
  self:update_entry(e)
  return true
end

function DB:load()
  local dir = self:db_dir()
  local path = self:db_path()

  if type(dir) ~= "string" or dir == "" or type(path) ~= "string" or path == "" then
    show_error(
      "FXMiner DB init failed: invalid config paths.\n\n" ..
      "DB dir: " .. tostring(dir) .. "\n" ..
      "DB path: " .. tostring(path) .. "\n\n" ..
      "Tip: This often happens when module name 'config' conflicts with Toolbox config.lua."
    )
    return false
  end

  ensure_dir(dir)

  local raw = read_all(path)
  if not raw or raw == "" then
    self.data = {
      schema_version = self.cfg.SCHEMA_VERSION or "1.0",
      entries = {},
    }
    self:_reindex()
    self:save()
    return true
  end

  local ok, decoded = pcall(function()
    return json.decode(raw)
  end)
  if not ok or type(decoded) ~= "table" then
    -- 如果 DB 损坏：备份并重建（尽量不阻断用户）
    local backup = self:db_path() .. ".bak_" .. tostring(now_sec())
    pcall(function()
      local f = io.open(backup, "w")
      if f then
        f:write(raw)
        f:close()
      end
    end)
    self.data = {
      schema_version = self.cfg.SCHEMA_VERSION or "1.0",
      entries = {},
      _recovered_from = backup,
    }
    self:_reindex()
    self:save()
    return true
  end

  decoded.entries = decoded.entries or {}
  self.data = decoded
  -- 兼容迁移：确保每条 entry 字段完整
  for _, e in ipairs(self.data.entries) do
    self:_ensure_entry_defaults(e)
    -- 如果 keywords 不存在或为空，补一次
    if not e.keywords or e.keywords == "" then
      self:rebuild_keywords(e)
    end
    -- 如果 status 不存在或非法，补一次
    e.status = (e.status == "indexed" or e.status == "unindexed") and e.status or self:calc_status(e)
  end
  self:_reindex()
  return true
end

function DB:save()
  ensure_dir(self:db_dir())
  return json.save_to_file(self.data or {}, self:db_path(), true)
end

function DB:make_relpath(abs_rfx_path)
  local from_dir = self.cfg.norm_slash and self.cfg.norm_slash(self:db_dir()) or tostring(self:db_dir()):gsub("\\", "/")
  local to_path = self.cfg.norm_slash and self.cfg.norm_slash(abs_rfx_path) or tostring(abs_rfx_path):gsub("\\", "/")

  from_dir = from_dir:gsub("/+$", "")
  to_path = to_path:gsub("/+$", "")

  from_dir = from_dir:gsub("/+", "/")
  to_path = to_path:gsub("/+", "/")

  from_dir = from_dir:gsub("/$", "")

  local from_parts = split_slash(from_dir)
  local to_parts = split_slash(to_path)

  local i = 1
  while i <= #from_parts and i <= #to_parts and lower(from_parts[i]) == lower(to_parts[i]) do
    i = i + 1
  end
  local common = i - 1

  local rel = {}
  for _ = 1, (#from_parts - common) do
    rel[#rel + 1] = ".."
  end
  for j = common + 1, #to_parts do
    rel[#rel + 1] = to_parts[j]
  end

  return table.concat(rel, "/")
end

function DB:add_entry(abs_rfx_path, meta)
  meta = meta or {}

  local rel = self:make_relpath(abs_rfx_path)
  local e = self._index[rel]
  local t = now_sec()

  if not e then
    e = {
      id = hash32(rel),
      rel_path = rel,
      created_at = t,
    }
    self.data.entries[#self.data.entries + 1] = e
    self._index[rel] = e
  end

  self:_ensure_entry_defaults(e)

  e.name = meta.name or e.name or ""
  e.description = meta.description or e.description or ""
  e.plugins = meta.plugins or e.plugins or {}

  -- Virtual folder assignment
  if meta.folder_id ~= nil then
    e.folder_id = tonumber(meta.folder_id) or 0
  end

  -- Metadata fields (all strings)
  if type(meta.metadata) == "table" then
    e.metadata = e.metadata or {}
    for k, v in pairs(meta.metadata) do
      e.metadata[tostring(k)] = tostring(v or "")
    end
  end

  e.updated_at = t
  e.status = self:calc_status(e)
  self:rebuild_keywords(e)

  self:save()
  return e
end

-- ---- Tag config (Source of Truth) ----
local function default_tag_config()
  return {
    Category = {
      type = "single",
      options = { "Processing", "Design", "Utility" },
    },
    Project = {
      type = "multi",
      options = { "Hero_Wukong", "General_Library" },
    },
    Element = {
      type = "multi",
      options = { "Fire", "Water", "Magic", "Tech" },
    },
  }
end

function DB:load_tag_config(script_root)
  -- script_root: .../Lee_Scripts/FX/FXMiner/
  local root = tostring(script_root or "")
  if root == "" then
    return false, "script_root missing"
  end

  local sep = self.cfg and self.cfg.PATH_SEP or package.config:sub(1, 1)
  local path = root:gsub("[\\/]+$", "") .. sep .. "config_tags.json"
  self.tag_config_path = path

  if not file_exists(path) then
    local ok, err = json.save_to_file(default_tag_config(), path, true)
    if not ok then
      return false, err
    end
  end

  local data, err = json.load_from_file(path)
  if not data then
    return false, err
  end

  self.tag_config = data
  return true
end

function DB:get_tag_config()
  return self.tag_config or {}
end

function DB:get_tag_config_path()
  return self.tag_config_path
end

-- Browser helpers (read-only)
function DB:entries()
  return (self.data and self.data.entries) or {}
end

function DB:find_entry_by_rel(rel_path)
  return self._index and self._index[rel_path] or nil
end

local function strip_ext(filename)
  local s = tostring(filename or "")
  return (s:gsub("%.RfxChain$", ""):gsub("%.rfxchain$", ""))
end

function DB:scan_fxchains()
  local r = reaper
  if not r or not r.EnumerateFiles or not r.EnumerateSubdirectories then
    return false, "EnumerateFiles/Subdirectories not available"
  end

  local root = tostring(self.cfg and self.cfg.FXCHAINS_ROOT or "")
  if root == "" then
    return false, "FXCHAINS_ROOT missing"
  end

  self.data = self.data or { schema_version = self.cfg.SCHEMA_VERSION or "1.0", entries = {} }
  self.data.entries = self.data.entries or {}

  local excluded = (self.cfg and self.cfg.EXCLUDED_FOLDERS) or {}
  local fields = self:get_fields_config()

  local function walk_dir(abs_dir)
    -- files
    local fi = 0
    while true do
      local fn = r.EnumerateFiles(abs_dir, fi)
      if not fn then break end
      fi = fi + 1

      if fn:lower():match("%.rfxchain$") then
        local sep = self.cfg and self.cfg.PATH_SEP or package.config:sub(1, 1)
        local abs = abs_dir:gsub("[\\/]+$", "") .. sep .. fn
        local rel = self:make_relpath(abs)

        local e = self._index[rel]
        if not e then
          local meta = {}
          for _, f in ipairs(fields) do
            local k = type(f) == "table" and tostring(f.key or "") or ""
            if k ~= "" then
              meta[k] = ""
            end
          end
          e = {
            id = hash32(rel),
            rel_path = rel,
            created_at = now_sec(),
            name = strip_ext(fn),
            description = "",
            plugins = {},
            folder_id = 0,
            metadata = meta,
            custom_tags = {},
            status = "unindexed",
            keywords = "",
          }
          self.data.entries[#self.data.entries + 1] = e
          self._index[rel] = e
        end

        self:_ensure_entry_defaults(e)
        if not e.name or e.name == "" then
          e.name = strip_ext(fn)
        end
        e.status = self:calc_status(e)
        if not e.keywords or e.keywords == "" then
          self:rebuild_keywords(e)
        end
      end
    end

    -- subdirs
    local di = 0
    while true do
      local sub = r.EnumerateSubdirectories(abs_dir, di)
      if not sub then break end
      di = di + 1

      if not excluded[sub] then
        local sep = self.cfg and self.cfg.PATH_SEP or package.config:sub(1, 1)
        walk_dir(abs_dir:gsub("[\\/]+$", "") .. sep .. sub)
      end
    end
  end

  walk_dir(root)
  self:save()
  return true
end

function DB:prune_missing_files()
  local entries = self:entries()
  if #entries == 0 then return true end

  for i = #entries, 1, -1 do
    local e = entries[i]
    local rel = e and e.rel_path
    if type(rel) ~= "string" or rel == "" then
      table.remove(entries, i)
    else
      local abs = self:rel_to_abs(rel)
      if not abs or not file_exists(abs) then
        self._index[rel] = nil
        table.remove(entries, i)
      end
    end
  end

  self:_reindex()
  self:save()
  return true
end

function DB:get_all_tags()
  local tags = {}
  local seen = {}
  for _, e in ipairs(self:entries()) do
    if e and type(e.tags) == "table" then
      for _, t in ipairs(e.tags) do
        t = tostring(t or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" and not seen[t] then
          seen[t] = true
          tags[#tags + 1] = t
        end
      end
    end
  end
  table.sort(tags, function(a, b) return a:lower() < b:lower() end)
  return tags
end

function DB:rel_to_abs(rel_path)
  -- rel_path is relative to DATA_DIR_PATH (e.g. ../Foo.RfxChain)
  local base = tostring(self:db_dir() or "")
  if base == "" then return nil end
  local rel = tostring(rel_path or "")
  if rel == "" then return nil end

  -- join using '/' then normalize
  local joined = base:gsub("\\", "/"):gsub("/+$", "") .. "/" .. rel:gsub("\\", "/")
  return norm_abs_path(joined)
end

-- ============================================================================
-- Team DB Sync Functions
-- ============================================================================

-- Load team database from server path
-- Returns: data table or nil, error_message
function DB:load_team_db(team_db_path)
  if not team_db_path or team_db_path == "" then
    return nil, "Team DB path not configured"
  end

  if not file_exists(team_db_path) then
    -- Return empty structure if file doesn't exist yet
    return {
      schema_version = "1.0",
      entries = {},
      last_updated = now_sec(),
    }
  end

  local raw = read_all(team_db_path)
  if not raw or raw == "" then
    return {
      schema_version = "1.0",
      entries = {},
      last_updated = now_sec(),
    }
  end

  local ok, data = pcall(function() return json.decode(raw) end)
  if not ok or type(data) ~= "table" then
    return nil, "Failed to parse team DB JSON"
  end

  return data
end

-- Save team database to server path
-- Fast read-modify-write to minimize lock time
function DB:save_team_db(team_db_path, data)
  if not team_db_path or team_db_path == "" then
    return false, "Team DB path not configured"
  end

  if type(data) ~= "table" then
    return false, "Invalid data"
  end

  data.last_updated = now_sec()

  -- Capturing real error messages and removing the second parameter for compatibility.
  -- The custom json.lua expects a string or nil for the second argument, not a boolean.
  local ok, json_str_or_err = pcall(function() return json.encode(data) end)
  
  if not ok then
    -- This will print the specific error, e.g., "Cycle detected" or "Invalid type function"
    return false, "JSON Encode Crash: " .. tostring(json_str_or_err)
  end
  
  if not json_str_or_err then
    return false, "JSON Encode returned nil result"
  end

  local json_str = json_str_or_err

  -- Ensure team directory exists
  local team_dir = team_db_path:match("^(.*)[\\/]")
  if team_dir then ensure_dir(team_dir) end

  local success, err = write_all(team_db_path, json_str)
  if not success then
    return false, "Failed to write file: " .. tostring(err)
  end

  return true
end

-- Sync a single entry to team database
-- Uses fast read-modify-write pattern to minimize concurrent conflicts
-- Returns: success, message
function DB:sync_entry_to_team(team_db_path, filename, metadata)
  if not team_db_path or team_db_path == "" then
    return false, "Team DB path not configured"
  end

  -- Step 1: Quick read
  local data, err = self:load_team_db(team_db_path)
  if not data then
    return false, err
  end

  -- Step 2: Modify
  data.entries = data.entries or {}

  -- Find existing entry by filename or create new
  local found_idx = nil
  for i, e in ipairs(data.entries) do
    if e and e.filename == filename then
      found_idx = i
      break
    end
  end

  local entry = {
    filename = filename,
    name = metadata.name or filename:gsub("%.RfxChain$", ""),
    description = metadata.description or "",
    metadata = metadata.metadata or {},
    plugins = metadata.plugins or {},
    published_by = metadata.published_by or os.getenv("USERNAME") or os.getenv("USER") or "Unknown",
    published_at = now_sec(),
    updated_at = now_sec(),
  }

  if found_idx then
    -- Update existing
    entry.published_at = data.entries[found_idx].published_at or now_sec() -- preserve original publish time
    data.entries[found_idx] = entry
  else
    -- Add new
    data.entries[#data.entries + 1] = entry
  end

  -- Step 3: Quick write
  local ok, save_err = self:save_team_db(team_db_path, data)
  if not ok then
    return false, save_err
  end

  return true, "Synced to team DB"
end

-- Get all entries from team database
function DB:get_team_entries(team_db_path)
  if not team_db_path or team_db_path == "" then
    return {}
  end

  local data, _ = self:load_team_db(team_db_path)
  if not data or type(data.entries) ~= "table" then
    return {}
  end

  return data.entries
end

-- ============================================================================
-- File Locking Mechanism for Team Sync
-- ============================================================================

local LOCK_FILENAME = "server_db.lock"
local LOCK_MAX_RETRIES = 10
local LOCK_WAIT_SECONDS = 1

-- Busy wait for specified seconds (Lua has no sleep)
local function busy_wait(seconds)
  local start = os.clock()
  while os.clock() - start < seconds do
    -- Busy loop
  end
end

-- Check if lock file exists
local function lock_exists(lock_path)
  local f = io.open(lock_path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- Acquire lock with retry mechanism
-- Returns: success (bool), error_message (string or nil)
function DB:acquire_lock(team_path, max_retries)
  if not team_path or team_path == "" then
    return false, "Team path not configured"
  end

  max_retries = max_retries or LOCK_MAX_RETRIES
  local lock_path = path_join(team_path, LOCK_FILENAME)

  local retries = 0
  while lock_exists(lock_path) do
    if retries >= max_retries then
      return false, "Server busy (lock timeout after " .. max_retries .. " retries)"
    end
    -- Wait before retry
    busy_wait(LOCK_WAIT_SECONDS)
    retries = retries + 1
  end

  -- Create lock file
  local f = io.open(lock_path, "w")
  if f then
    -- Write lock info for debugging
    f:write(string.format("locked_by=%s\nlocked_at=%d\n",
      os.getenv("USERNAME") or os.getenv("USER") or "unknown",
      os.time()))
    f:close()
    return true
  else
    return false, "Failed to create lock file"
  end
end

-- Release lock
function DB:release_lock(team_path)
  if not team_path or team_path == "" then
    return
  end
  local lock_path = path_join(team_path, LOCK_FILENAME)
  os.remove(lock_path)
end

-- Force release stale lock (if lock is older than max_age seconds)
function DB:force_release_stale_lock(team_path, max_age)
  if not team_path or team_path == "" then
    return false
  end

  max_age = max_age or 60 -- Default 60 seconds

  local lock_path = path_join(team_path, LOCK_FILENAME)
  if not lock_exists(lock_path) then
    return false -- No lock to release
  end

  -- Check lock age
  local f = io.open(lock_path, "r")
  if f then
    local content = f:read("*all")
    f:close()

    local locked_at = content:match("locked_at=(%d+)")
    if locked_at then
      local age = os.time() - tonumber(locked_at)
      if age > max_age then
        os.remove(lock_path)
        return true -- Stale lock removed
      end
    end
  end

  return false
end

-- ============================================================================
-- Push (Upload) with Locking
-- ============================================================================

-- Push a single entry to team server with proper locking
-- Returns: success, message
function DB:push_to_team_locked(team_path, team_db_path, source_path, metadata)
  if not team_path or team_path == "" then
    return false, "Team path not configured"
  end

  -- Step 1: Try to force release stale locks
  self:force_release_stale_lock(team_path, 120)

  -- Step 2: Acquire lock
  local lock_ok, lock_err = self:acquire_lock(team_path)
  if not lock_ok then
    return false, lock_err
  end

  -- Use pcall to ensure lock is released even on error
  local success, result_msg = pcall(function()
    -- Step 3: Read remote DB
    local data, err = self:load_team_db(team_db_path)
    if not data then
      error("Failed to read team DB: " .. tostring(err))
    end

    data.entries = data.entries or {}

    -- Step 4: Find and update/insert entry
    local filename = source_path:match("([^/\\]+)$") or source_path
    local found_idx = nil

    for i, e in ipairs(data.entries) do
      if e and e.filename == filename then
        found_idx = i
        break
      end
    end

    local entry = {
      filename = filename,
      name = metadata.name or filename:gsub("%.RfxChain$", ""),
      description = metadata.description or "",
      metadata = metadata.metadata or {},
      plugins = metadata.plugins or {},
      published_by = os.getenv("USERNAME") or os.getenv("USER") or "Unknown",
      published_at = now_sec(),
      updated_at = now_sec(),
    }

    if found_idx then
      -- Preserve original publish time
      entry.published_at = data.entries[found_idx].published_at or now_sec()
      data.entries[found_idx] = entry
    else
      data.entries[#data.entries + 1] = entry
    end

    -- Step 5: Write back to remote DB
    local ok, save_err = self:save_team_db(team_db_path, data)
    if not ok then
      error("Failed to save team DB: " .. tostring(save_err))
    end

    return "Pushed successfully"
  end)

  -- Step 6: Always release lock
  self:release_lock(team_path)

  if success then
    return true, result_msg
  else
    return false, tostring(result_msg)
  end
end

-- ============================================================================
-- Pull (Download/Sync) with Locking
-- ============================================================================

-- Pull all missing entries from team server
-- Downloads files and merges metadata into local DB
-- Returns: success, message, stats_table
function DB:pull_from_team(team_path, team_db_path, local_download_dir, opts)
  opts = opts or {}

  if not team_path or team_path == "" then
    return false, "Team path not configured", nil
  end

  local stats = {
    downloaded = 0,
    updated = 0,
    skipped = 0,
    errors = {},
  }

  -- Step 1: Acquire lock for reading (brief lock to ensure consistent read)
  self:force_release_stale_lock(team_path, 120)
  local lock_ok, lock_err = self:acquire_lock(team_path, 3) -- Short timeout for read

  local team_data
  if lock_ok then
    team_data = self:load_team_db(team_db_path)
    self:release_lock(team_path)
  else
    -- If can't lock, try to read anyway (might get partial data)
    team_data = self:load_team_db(team_db_path)
  end

  if not team_data or type(team_data.entries) ~= "table" then
    return false, "Failed to read team database", stats
  end

  -- Step 2: Ensure download directory exists
  local download_dir = local_download_dir or (self:fxchains_root() or "")
  ensure_dir(download_dir)

  -- Step 3: Process each team entry
  for _, te in ipairs(team_data.entries) do
    if te and te.filename then
      local filename = te.filename
      local source_file = path_join(team_path, filename)
      local target_file = path_join(download_dir, filename)

      -- Check if we already have this file locally
      local local_entry = nil
      for _, le in ipairs(self:entries()) do
        if le and le.rel_path then
          local le_filename = le.rel_path:match("([^/\\]+)$")
          if le_filename == filename then
            local_entry = le
            break
          end
        end
      end

      if not file_exists(target_file) then
        -- Case A: File doesn't exist locally -> Download
        if file_exists(source_file) then
          -- Copy file
          local rf = io.open(source_file, "rb")
          if rf then
            local data = rf:read("*all")
            rf:close()

            local wf = io.open(target_file, "wb")
            if wf then
              wf:write(data)
              wf:close()

              -- Add to local DB
              self:add_entry(target_file, {
                name = te.name or filename:gsub("%.RfxChain$", ""),
                description = te.description or "",
                folder_id = 0, -- Default to root folder
                metadata = te.metadata or {},
                plugins = te.plugins or {},
              })

              stats.downloaded = stats.downloaded + 1
            else
              stats.errors[#stats.errors + 1] = "Cannot write: " .. filename
            end
          else
            stats.errors[#stats.errors + 1] = "Cannot read from server: " .. filename
          end
        else
          stats.errors[#stats.errors + 1] = "Server file missing: " .. filename
        end
      else
        -- Case B: File exists locally
        if local_entry then
          -- Update metadata if server is newer (Strategy 1: server is always right)
          local server_time = tonumber(te.updated_at) or 0
          local local_time = tonumber(local_entry.updated_at) or 0

          if server_time > local_time or opts.force_update then
            -- Update local metadata from server
            local_entry.name = te.name or local_entry.name
            local_entry.description = te.description or local_entry.description
            local_entry.metadata = te.metadata or local_entry.metadata
            local_entry.plugins = te.plugins or local_entry.plugins
            local_entry.updated_at = now_sec()

            self:update_entry(local_entry, { save = false })
            stats.updated = stats.updated + 1
          else
            stats.skipped = stats.skipped + 1
          end
        else
          -- File exists but not in DB -> Add to DB
          self:add_entry(target_file, {
            name = te.name or filename:gsub("%.RfxChain$", ""),
            description = te.description or "",
            folder_id = 0,
            metadata = te.metadata or {},
            plugins = te.plugins or {},
          })
          stats.updated = stats.updated + 1
        end
      end
    end
  end

  -- Save local DB
  self:save()

  local msg = string.format("Downloaded: %d, Updated: %d, Skipped: %d",
    stats.downloaded, stats.updated, stats.skipped)

  if #stats.errors > 0 then
    msg = msg .. string.format(", Errors: %d", #stats.errors)
  end

  return true, msg, stats
end

-- ============================================================================
-- Full Sync (Bidirectional)
-- ============================================================================

-- Sync local changes to team and pull team changes to local
-- Returns: success, message, stats
function DB:full_sync(team_path, team_db_path, local_download_dir)
  if not team_path or team_path == "" then
    return false, "Team path not configured"
  end

  -- First pull from team
  local pull_ok, pull_msg, pull_stats = self:pull_from_team(team_path, team_db_path, local_download_dir)

  local msg = "Pull: " .. tostring(pull_msg)

  return pull_ok, msg, pull_stats
end

return DB
