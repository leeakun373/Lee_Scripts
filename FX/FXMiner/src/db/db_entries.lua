-- FXMiner/src/db/db_entries.lua
-- 条目管理：CRUD、扫描、迁移等

local json = require("json")
local Utils = require("db.db_utils")

local Entries = {}

-- Helper function to strip extension
local function strip_ext(filename)
  local s = tostring(filename or "")
  return (s:gsub("%.RfxChain$", ""):gsub("%.rfxchain$", ""))
end

-- Initialize entries methods on DB instance
function Entries.init(DB)
  -- Ensure entry has all default fields
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
            local s = Utils.trim(tostring(it or ""))
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

  -- Calculate entry status
  function DB:calc_status(e)
    self:_ensure_entry_defaults(e)
    -- Check if any metadata field has non-empty value
    for k, v in pairs(e.metadata or {}) do
      if Utils.trim(tostring(v or "")) ~= "" then
        return "indexed"
      end
    end
    return "unindexed"
  end

  -- Rebuild keywords from entry content
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

  -- Update entry
  function DB:update_entry(e, opts)
    opts = opts or {}
    self:_ensure_entry_defaults(e)
    e.updated_at = Utils.now_sec()
    e.status = self:calc_status(e)
    self:rebuild_keywords(e)
    if opts.save ~= false then
      self:save()
    end
    return true
  end

  -- Migrate all entries to new schema
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

  -- Collect used values for a specific field key
  function DB:collect_used_values(key)
    key = tostring(key or "")
    if key == "" then return {} end

    local values = {}
    local seen = {}

    for _, e in ipairs(self:entries()) do
      self:_ensure_entry_defaults(e)
      if tostring(e.status) == "indexed" then
        if key == "Category" then
          local v = Utils.trim(e.metadata.Category)
          if v ~= "" and not seen[v] then
            seen[v] = true
            values[#values + 1] = v
          end
        else
          local arr = e.metadata[key]
          if type(arr) == "table" then
            for _, it in ipairs(arr) do
              local v = Utils.trim(it)
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

  -- Add entry to database
  function DB:add_entry(abs_rfx_path, meta)
    meta = meta or {}

    local rel = self:make_relpath(abs_rfx_path)
    local e = self._index[rel]
    local t = Utils.now_sec()

    if not e then
      e = {
        id = Utils.hash32(rel),
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

  -- Delete entry from database
  function DB:delete_entry(rel_path, opts)
    opts = opts or {}
    local delete_file = opts.delete_file ~= false -- default to true
    
    rel_path = tostring(rel_path or "")
    if rel_path == "" then
      return false, "rel_path missing"
    end
    
    local e = self._index[rel_path]
    if not e then
      return false, "Entry not found"
    end
    
    -- Delete physical file if requested
    if delete_file then
      local abs_path = self:rel_to_abs(rel_path)
      if abs_path and Utils.file_exists(abs_path) then
        local ok, err = pcall(os.remove, abs_path)
        if not ok then
          return false, "Failed to delete file: " .. tostring(err)
        end
      end
    end
    
    -- Remove from entries array
    local entries = self.data.entries or {}
    for i = #entries, 1, -1 do
      if entries[i] and entries[i].rel_path == rel_path then
        table.remove(entries, i)
        break
      end
    end
    
    -- Remove from index
    self._index[rel_path] = nil
    
    -- Save database
    if opts.save ~= false then
      self:save()
    end
    
    return true
  end

  -- Scan FX chains directory and add to database
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

    -- Try to load FXEngine for plugin parsing
    local FXEngine = nil
    local ok_eng, eng = pcall(require, "fx_engine")
    if ok_eng and eng and eng.parse_rfxchain_file then
      FXEngine = eng
    end

    local db_modified = false

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
              id = Utils.hash32(rel),
              rel_path = rel,
              created_at = Utils.now_sec(),
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

          -- Fill missing plugins for legacy files
          if FXEngine and (not e.plugins or #e.plugins == 0) and Utils.file_exists(abs) then
            local plugins = FXEngine.parse_rfxchain_file(abs)
            if plugins and #plugins > 0 then
              e.plugins = plugins
              db_modified = true
            end
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

    -- After scanning, check all existing entries for missing plugins
    if FXEngine then
      for _, e in ipairs(self.data.entries) do
        if e and e.rel_path and (not e.plugins or #e.plugins == 0) then
          local abs = self:rel_to_abs(e.rel_path)
          if abs and Utils.file_exists(abs) then
            local plugins = FXEngine.parse_rfxchain_file(abs)
            if plugins and #plugins > 0 then
              e.plugins = plugins
              db_modified = true
            end
          end
        end
      end
    end

    self:save()
    return true
  end

  -- Prune missing files from database
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
        if not abs or not Utils.file_exists(abs) then
          self._index[rel] = nil
          table.remove(entries, i)
        end
      end
    end

    self:_reindex()
    self:save()
    return true
  end

  -- Get all entries (read-only)
  function DB:entries()
    return (self.data and self.data.entries) or {}
  end

  -- Find entry by relative path
  function DB:find_entry_by_rel(rel_path)
    return self._index and self._index[rel_path] or nil
  end

  -- Get all tags (legacy)
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
end

return Entries

