-- FXMiner/src/db/db_folders.lua
-- 虚拟文件夹管理

local json = require("json")
local Utils = require("db.db_utils")

local Folders = {}

-- Default folders database structure
local function default_folders_db()
  return {
    next_id = 1,
    folders_by_id = {
      ["0"] = { id = 0, name = "Root", parent_id = nil },
    },
  }
end

-- Normalize folders database structure
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

-- Renumber sort indices for folders under a parent
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

-- Check if folder is descendant of another folder
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

-- Initialize folders methods on DB instance
function Folders.init(DB)
  -- Load folders from file
  function DB:load_folders(script_root)
    local root = tostring(script_root or "")
    if root == "" then
      return false, "script_root missing"
    end

    local path = Utils.path_join(root, "folders_db.json")
    self.folders_path = path

    if not Utils.file_exists(path) then
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

  -- Save folders to file
  function DB:save_folders()
    if not self.folders_path or self.folders_path == "" then
      return false, "folders_db path missing"
    end
    self.folders = normalize_folders_db(self.folders)
    return json.save_to_file(self.folders, self.folders_path, true)
  end

  -- Get folders database
  function DB:get_folders()
    self.folders = normalize_folders_db(self.folders)
    return self.folders
  end

  -- Get folder by ID
  function DB:get_folder(id)
    self.folders = normalize_folders_db(self.folders)
    id = tonumber(id) or 0
    return self.folders.folders_by_id[tostring(id)]
  end

  -- Get folder name by ID
  function DB:get_folder_name(id)
    local f = self:get_folder(id)
    return (f and tostring(f.name)) or ""
  end

  -- List children folders of a parent
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

  -- Create new folder
  function DB:create_folder(name, parent_id, opts)
    self.folders = normalize_folders_db(self.folders)
    name = Utils.trim(name)
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

  -- Rename folder
  function DB:rename_folder(id, new_name)
    self.folders = normalize_folders_db(self.folders)
    id = tonumber(id) or 0
    if id == 0 then
      return false, "Cannot rename Root"
    end
    new_name = Utils.trim(new_name)
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

  -- Move folder to new parent
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

  -- Create parent folder for a child
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

  -- Delete folder
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

  -- Set entry's folder
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
end

return Folders

