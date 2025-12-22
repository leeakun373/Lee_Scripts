-- FXMiner/src/db/db_team_sync.lua
-- 团队同步功能：push/pull/sync/locking

local json = require("json")
local Utils = require("db.db_utils")

local TeamSync = {}

-- Lock file constants
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

-- Initialize team sync methods on DB instance
function TeamSync.init(DB)
  -- Load team database from server path
  function DB:load_team_db(team_db_path)
    if not team_db_path or team_db_path == "" then
      return nil, "Team DB path not configured"
    end

    if not Utils.file_exists(team_db_path) then
      -- Return empty structure if file doesn't exist yet
      return {
        schema_version = "1.0",
        entries = {},
        last_updated = Utils.now_sec(),
      }
    end

    local raw = Utils.read_all(team_db_path)
    if not raw or raw == "" then
      return {
        schema_version = "1.0",
        entries = {},
        last_updated = Utils.now_sec(),
      }
    end

    local ok, data = pcall(function() return json.decode(raw) end)
    if not ok or type(data) ~= "table" then
      return nil, "Failed to parse team DB JSON"
    end

    return data
  end

  -- Save team database to server path
  function DB:save_team_db(team_db_path, data)
    if not team_db_path or team_db_path == "" then
      return false, "Team DB path not configured"
    end

    if type(data) ~= "table" then
      return false, "Invalid data"
    end

    data.last_updated = Utils.now_sec()

    -- Capturing real error messages and removing the second parameter for compatibility.
    -- The custom json.lua expects a string or nil for the second argument, not a boolean.
    -- Use 2 spaces for indentation to make the JSON file readable
    local ok, json_str_or_err = pcall(function() return json.encode(data, "  ") end)
    
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
    if team_dir then Utils.ensure_dir(team_dir) end

    local success, err = Utils.write_all(team_db_path, json_str)
    if not success then
      return false, "Failed to write file: " .. tostring(err)
    end

    return true
  end

  -- Sync a single entry to team database
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
      published_at = Utils.now_sec(),
      updated_at = Utils.now_sec(),
    }

    if found_idx then
      -- Update existing
      entry.published_at = data.entries[found_idx].published_at or Utils.now_sec() -- preserve original publish time
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
  -- opts.filter_missing: if true, filter out entries where file doesn't exist
  function DB:get_team_entries(team_db_path, opts)
    opts = opts or {}
    if not team_db_path or team_db_path == "" then
      return {}
    end

    local data, _ = self:load_team_db(team_db_path)
    if not data or type(data.entries) ~= "table" then
      return {}
    end

    -- If filter_missing is enabled, filter out entries where file doesn't exist
    if opts.filter_missing and self.cfg and self.cfg.TEAM_PUBLISH_PATH then
      local team_path = self.cfg.TEAM_PUBLISH_PATH
      local filtered = {}
      for _, entry in ipairs(data.entries) do
        if entry and entry.filename then
          local file_path = Utils.path_join(team_path, entry.filename)
          if Utils.file_exists(file_path) then
            filtered[#filtered + 1] = entry
          end
        end
      end
      return filtered
    end

    return data.entries
  end

  -- Acquire lock with retry mechanism
  function DB:acquire_lock(team_path, max_retries)
    if not team_path or team_path == "" then
      return false, "Team path not configured"
    end

    max_retries = max_retries or LOCK_MAX_RETRIES
    local lock_path = Utils.path_join(team_path, LOCK_FILENAME)

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
    local lock_path = Utils.path_join(team_path, LOCK_FILENAME)
    os.remove(lock_path)
  end

  -- Force release stale lock
  function DB:force_release_stale_lock(team_path, max_age)
    if not team_path or team_path == "" then
      return false
    end

    max_age = max_age or 60 -- Default 60 seconds

    local lock_path = Utils.path_join(team_path, LOCK_FILENAME)
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

  -- Push a single entry to team server with proper locking
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
        published_at = Utils.now_sec(),
        updated_at = Utils.now_sec(),
      }

      if found_idx then
        -- Preserve original publish time
        entry.published_at = data.entries[found_idx].published_at or Utils.now_sec()
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

  -- Pull missing entries from team server
  -- opts.selected_filenames: optional array of filenames to pull (if nil, pull all)
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

    -- Filter entries if selected_filenames is provided
    local entries_to_process = team_data.entries
    if opts.selected_filenames and type(opts.selected_filenames) == "table" and #opts.selected_filenames > 0 then
      local selected_set = {}
      for _, filename in ipairs(opts.selected_filenames) do
        selected_set[tostring(filename)] = true
      end
      entries_to_process = {}
      for _, te in ipairs(team_data.entries) do
        if te and te.filename and selected_set[tostring(te.filename)] then
          entries_to_process[#entries_to_process + 1] = te
        end
      end
    end

    -- Step 2: Ensure download directory exists
    -- Default to TEAM_DOWNLOAD_DIR (FXChains/FXMiner/) to keep team files separate
    local download_dir = local_download_dir or (self.cfg and (self.cfg.TEAM_DOWNLOAD_DIR or self.cfg.FXCHAINS_ROOT) or "")
    Utils.ensure_dir(download_dir)

    -- Step 3: Process each team entry (filtered if needed)
    for _, te in ipairs(entries_to_process) do
      if te and te.filename then
        local filename = te.filename
        local source_file = Utils.path_join(team_path, filename)
        local target_file = Utils.path_join(download_dir, filename)

        -- Check if we already have this file locally (by filename in DB)
        local local_entry = nil
        local local_file_exists = false
        
        -- First, check if file exists in download directory
        local target_exists = Utils.file_exists(target_file)
        
        -- Then check if file exists elsewhere in local DB
        for _, le in ipairs(self:entries()) do
          if le and le.rel_path then
            local le_filename = le.rel_path:match("([^/\\]+)$")
            if le_filename == filename then
              local_entry = le
              -- Check if the actual file exists on disk (anywhere in FXChains)
              if le.abs_path and Utils.file_exists(le.abs_path) then
                local_file_exists = true
                break
              end
            end
          end
        end
        
        -- Also check if file exists anywhere in FXChains root (even if not in DB)
        -- This is important: files might exist in root or subdirs but not in DB yet
        if not local_file_exists then
          local fxchains_root = self.cfg and self.cfg.FXCHAINS_ROOT or ""
          if fxchains_root and fxchains_root ~= "" then
            local r = reaper
            if r and r.EnumerateFiles then
              local function check_in_dir(dir)
                -- Check files in current directory
                local fi = 0
                while true do
                  local fn = r.EnumerateFiles(dir, fi)
                  if not fn then break end
                  fi = fi + 1
                  if fn:lower() == filename:lower() then
                    return true
                  end
                end
                -- Check subdirectories (but skip download dir to avoid checking it twice)
                local di = 0
                while true do
                  local sub = r.EnumerateSubdirectories(dir, di)
                  if not sub then break end
                  di = di + 1
                  -- Skip the download directory (FXMiner folder) as we already checked it
                  local download_dir_name = self.cfg and self.cfg.TEAM_DOWNLOAD_DIR_NAME or "FXMiner"
                  if sub ~= download_dir_name then
                    local sub_path = Utils.path_join(dir, sub)
                    if check_in_dir(sub_path) then
                      return true
                    end
                  end
                end
                return false
              end
              if check_in_dir(fxchains_root) then
                local_file_exists = true
              end
            end
          end
        end

        -- Only download if:
        -- 1. File doesn't exist in download directory AND
        -- 2. File doesn't exist anywhere locally (not in DB or not in file system)
        if not target_exists and not local_file_exists then
          -- Case A: File doesn't exist locally -> Download
          if Utils.file_exists(source_file) then
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
            -- Server file missing: remove from database (with lock)
            stats.errors[#stats.errors + 1] = "Server file missing: " .. filename .. " (removed from DB)"
            -- Remove entry from team database
            pcall(function()
              self:remove_team_entry_locked(team_path, team_db_path, filename)
            end)
          end
        else
          -- Case B: File exists locally (either in download dir or elsewhere)
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
              local_entry.updated_at = Utils.now_sec()

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

  -- Remove a single entry from team database (with lock)
  function DB:remove_team_entry_locked(team_path, team_db_path, filename)
    if not team_path or team_path == "" or not team_db_path or team_db_path == "" then
      return false, "Team path or DB path not configured"
    end

    if not filename or filename == "" then
      return false, "Filename not provided"
    end

    -- Step 1: Force release stale locks
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

      -- Step 4: Find and remove entry
      local found_idx = nil
      for i, e in ipairs(data.entries) do
        if e and e.filename == filename then
          found_idx = i
          break
        end
      end

      if found_idx then
        -- Remove entry
        table.remove(data.entries, found_idx)

        -- Step 5: Write back to remote DB
        local ok, save_err = self:save_team_db(team_db_path, data)
        if not ok then
          error("Failed to save team DB: " .. tostring(save_err))
        end

        return "Removed entry: " .. filename
      else
        return "Entry not found: " .. filename
      end
    end)

    -- Step 6: Always release lock
    self:release_lock(team_path)

    if success then
      return true, result_msg
    else
      return false, tostring(result_msg)
    end
  end

  -- Clean team database: remove all entries where files don't exist
  function DB:clean_team_db(team_path, team_db_path)
    if not team_path or team_path == "" or not team_db_path or team_db_path == "" then
      return false, "Team path or DB path not configured", nil
    end

    local stats = {
      removed = 0,
      kept = 0,
      errors = {},
    }

    -- Step 1: Force release stale locks
    self:force_release_stale_lock(team_path, 120)

    -- Step 2: Acquire lock
    local lock_ok, lock_err = self:acquire_lock(team_path)
    if not lock_ok then
      return false, lock_err, stats
    end

    -- Use pcall to ensure lock is released even on error
    local success, result_msg = pcall(function()
      -- Step 3: Read remote DB
      local data, err = self:load_team_db(team_db_path)
      if not data then
        error("Failed to read team DB: " .. tostring(err))
      end

      data.entries = data.entries or {}

      -- Step 4: Filter entries - keep only those where file exists
      local cleaned_entries = {}
      for _, entry in ipairs(data.entries) do
        if entry and entry.filename then
          local file_path = Utils.path_join(team_path, entry.filename)
          if Utils.file_exists(file_path) then
            cleaned_entries[#cleaned_entries + 1] = entry
            stats.kept = stats.kept + 1
          else
            stats.removed = stats.removed + 1
          end
        end
      end

      data.entries = cleaned_entries

      -- Step 5: Write back to remote DB
      local ok, save_err = self:save_team_db(team_db_path, data)
      if not ok then
        error("Failed to save team DB: " .. tostring(save_err))
      end

      local msg = string.format("Removed: %d, Kept: %d", stats.removed, stats.kept)
      return msg
    end)

    -- Step 6: Always release lock
    self:release_lock(team_path)

    if success then
      return true, result_msg, stats
    else
      return false, tostring(result_msg), stats
    end
  end

  -- Full sync (bidirectional)
  function DB:full_sync(team_path, team_db_path, local_download_dir)
    if not team_path or team_path == "" then
      return false, "Team path not configured"
    end

    -- First pull from team
    local pull_ok, pull_msg, pull_stats = self:pull_from_team(team_path, team_db_path, local_download_dir)

    local msg = "Pull: " .. tostring(pull_msg)

    return pull_ok, msg, pull_stats
  end
end

return TeamSync

