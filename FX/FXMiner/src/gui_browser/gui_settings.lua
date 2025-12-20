-- FXMiner/src/gui_browser/gui_settings.lua
-- 设置面板 UI

local W = require("widgets")

local Settings = {}

-- Dependencies (will be injected)
local App, DB, Config, Engine = nil, nil, nil, nil
local state = nil
local save_user_config_fn = nil

-- Trim helper
local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Draw settings panel
function Settings.draw(ctx)
  local ImGui = App.ImGui

  W.separator_text(ctx, ImGui, "Settings")

  -- Team Publish Path
  ImGui.Text(ctx, "Team Server Path (NAS/Network Drive):")
  ImGui.PushItemWidth(ctx, -80)

  -- Sync with Config (user input takes priority, but sync if Config changed externally)
  if state.settings_team_path == "" and Config.TEAM_PUBLISH_PATH and Config.TEAM_PUBLISH_PATH ~= "" then
    state.settings_team_path = Config.TEAM_PUBLISH_PATH
  elseif Config.TEAM_PUBLISH_PATH and state.settings_team_path ~= Config.TEAM_PUBLISH_PATH then
    -- If Config was updated (e.g., from user config load), sync it
    state.settings_team_path = Config.TEAM_PUBLISH_PATH
  end

  -- InputText with proper binding
  local _, new_path = ImGui.InputText(ctx, "##team_path", state.settings_team_path)
  state.settings_team_path = new_path
  ImGui.PopItemWidth(ctx)

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Browse##team_browse", 70, 0) then
    -- Try to use JS_Dialog_BrowseForFolder if available
    if reaper.JS_Dialog_BrowseForFolder then
      local rv, path = reaper.JS_Dialog_BrowseForFolder("Select Team Server Folder", state.settings_team_path or "")
      if rv == 1 and path and path ~= "" then
        -- Normalize path separators (convert backslashes to forward slashes)
        path = path:gsub("\\", "/")
        -- Update state - this will be displayed in the input field in the next frame
        state.settings_team_path = path
        -- Also update Config immediately so it's available for other operations
        Config.TEAM_PUBLISH_PATH = path
      end
    else
      state.team_sync_status = "Install js_ReaScriptAPI for folder browser"
    end
  end

  -- Apply button
  if ImGui.Button(ctx, "Apply Path", 80, 0) then
    -- Update Config with user input
    local new_path = trim(state.settings_team_path)
    local old_path = Config.TEAM_PUBLISH_PATH
    Config.TEAM_PUBLISH_PATH = new_path
    
    -- IMPORTANT: Clear TEAM_DB_PATH so get_team_db_path() will derive it from TEAM_PUBLISH_PATH
    -- Set to empty string (not nil) to ensure get_team_db_path() uses TEAM_PUBLISH_PATH
    Config.TEAM_DB_PATH = ""

    -- Clear old team entries if path changed
    if old_path ~= new_path then
      state.team_entries = {}
      state.team_last_sync = 0
    end

    -- Validate path
    if new_path ~= "" then
      local f = io.open(new_path .. "/.fxminer_test", "w")
      if f then
        f:close()
        os.remove(new_path .. "/.fxminer_test")
        state.settings_team_path_valid = true
        state.team_sync_status = "✓ Path valid and writable"
        
        -- Save to user config file
        if save_user_config_fn and save_user_config_fn(Config) then
          state.team_sync_status = "✓ Path saved and valid"
        else
          state.team_sync_status = "✓ Path valid (save failed)"
        end
        
        -- Reload team entries from new path
        -- IMPORTANT: Clear TEAM_DB_PATH so get_team_db_path() derives from new TEAM_PUBLISH_PATH
        Config.TEAM_DB_PATH = ""
        
        -- Calculate team DB path from new publish path
        local team_db_path = nil
        if Config.get_team_db_path then
          team_db_path = Config.get_team_db_path()
        else
          -- Fallback: manually construct path
          if Config.path_join and Config.TEAM_PUBLISH_PATH then
            team_db_path = Config.path_join(Config.TEAM_PUBLISH_PATH, "server_db.json")
          end
        end
        
        -- Clear entries first (always clear, even if path is invalid)
        state.team_entries = {}
        
        if team_db_path and team_db_path ~= "" then
          -- Load from new path
          local entries = DB:get_team_entries(team_db_path)
          state.team_entries = entries or {}
          state.team_last_sync = os.time()
          
          if #state.team_entries > 0 then
            state.team_sync_status = "✓ Path saved, loaded " .. #state.team_entries .. " entries from: " .. team_db_path
          else
            state.team_sync_status = "✓ Path saved, no entries found in: " .. team_db_path
          end
        else
          state.team_sync_status = "✓ Path saved, but team DB path could not be determined"
        end
      else
        state.settings_team_path_valid = false
        state.team_sync_status = "✗ Path not writable"
      end
    else
      -- Empty path - clear config
      Config.TEAM_PUBLISH_PATH = ""
      Config.TEAM_DB_PATH = ""
      state.settings_team_path_valid = false
      state.team_sync_status = "Path cleared"
      state.team_entries = {}
      state.team_last_sync = 0
      if save_user_config_fn then save_user_config_fn(Config) end -- Save empty path
    end
  end

  ImGui.SameLine(ctx)
  local valid_text = state.settings_team_path_valid and "✓ Valid" or ""
  ImGui.TextDisabled(ctx, valid_text)

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)

  -- Team Sync Actions
  W.separator_text(ctx, ImGui, "Team Sync (with File Locking)")

  local team_enabled = Config.TEAM_PUBLISH_PATH and Config.TEAM_PUBLISH_PATH ~= ""

  if not team_enabled and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end

  -- Full Sync button (Pull + refresh)
  if ImGui.Button(ctx, "Full Sync", 80, 0) then
    local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
    if team_db_path then
      state.team_sync_status = "Syncing..."

            -- Use the locked pull function
            local ok, msg, stats = DB:pull_from_team(
              Config.TEAM_PUBLISH_PATH,
              team_db_path,
              Config.TEAM_DOWNLOAD_DIR or Config.FXCHAINS_ROOT
            )

      if ok then
        -- Refresh team entries list
        state.team_entries = DB:get_team_entries(team_db_path)
        state.team_last_sync = os.time()
        state.team_sync_status = "✓ " .. tostring(msg)
      else
        state.team_sync_status = "✗ Sync failed: " .. tostring(msg)
      end
    else
      state.team_sync_status = "Team DB path not configured"
    end
  end

  ImGui.SameLine(ctx)

  -- Pull from Team (view only, no download)
  if ImGui.Button(ctx, "Refresh List", 85, 0) then
    local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
    if team_db_path and Config.TEAM_PUBLISH_PATH and Config.TEAM_PUBLISH_PATH ~= "" then
      -- Clear old entries first
      state.team_entries = {}
      -- Reload from current team DB path
      state.team_entries = DB:get_team_entries(team_db_path)
      state.team_last_sync = os.time()
      state.team_sync_status = string.format("Loaded %d entries from team DB", #state.team_entries)
    else
      state.team_entries = {}
      state.team_sync_status = "Team DB path not configured"
    end
  end

  ImGui.SameLine(ctx)

  -- Force release stale lock
  if ImGui.Button(ctx, "Clear Lock", 75, 0) then
    local removed = DB:force_release_stale_lock(Config.TEAM_PUBLISH_PATH, 0)
    if removed then
      state.team_sync_status = "Lock file removed"
    else
      state.team_sync_status = "No lock file found"
    end
  end

  ImGui.Spacing(ctx)

  -- Push Selected to Team (with locking)
  if ImGui.Button(ctx, "Push Selected to Team", 140, 0) then
    if state.selected_rel and not state.selected_rel:match("^team:") then
      local e = DB:find_entry_by_rel(state.selected_rel)
      if e then
        local abs_path = DB:rel_to_abs(e.rel_path)
        if abs_path then
          state.team_sync_status = "Pushing..."

          -- Step 1: Copy file to team folder
          local Engine = require("fx_engine")
          local result, msg, published_path = Engine.publish_to_team(Config, abs_path, { force_overwrite = true })

          if result == Engine.PUBLISH_OK then
            -- Step 2: Sync metadata with locking
            local team_db_path = Config.get_team_db_path and Config.get_team_db_path()
            if team_db_path then
              local metadata = {
                name = e.name,
                description = e.description,
                metadata = e.metadata,
                plugins = e.plugins,
              }

              local sync_ok, sync_msg = DB:push_to_team_locked(
                Config.TEAM_PUBLISH_PATH,
                team_db_path,
                abs_path,
                metadata
              )

              if sync_ok then
                -- Refresh team entries
                state.team_entries = DB:get_team_entries(team_db_path)
                state.team_sync_status = "✓ Pushed: " .. tostring(e.name)
              else
                state.team_sync_status = "File copied but DB sync failed: " .. tostring(sync_msg)
              end
            else
              state.team_sync_status = "✓ Pushed (no DB sync)"
            end
          else
            state.team_sync_status = "✗ Push failed: " .. tostring(msg)
          end
        else
          state.team_sync_status = "Cannot resolve file path"
        end
      else
        state.team_sync_status = "Entry not found in local DB"
      end
    else
      if state.selected_rel and state.selected_rel:match("^team:") then
        state.team_sync_status = "Cannot push team entries (select a local item)"
      else
        state.team_sync_status = "Select a local item first"
      end
    end
  end

  if not team_enabled and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)

  -- Sync explanation
  W.separator_text(ctx, ImGui, "How Sync Works")
  ImGui.TextDisabled(ctx, "Full Sync: Downloads missing files from team server,")
  ImGui.TextDisabled(ctx, "updates local metadata if server version is newer.")
  ImGui.TextDisabled(ctx, "Push: Uploads selected file + metadata to team server.")
  ImGui.TextDisabled(ctx, "File locking prevents concurrent write conflicts.")

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)

  -- Status area
  W.separator_text(ctx, ImGui, "Status")

  if state.team_sync_status and state.team_sync_status ~= "" then
    -- Color based on status
    local is_error = state.team_sync_status:find("✗") or state.team_sync_status:find("failed")
    local is_success = state.team_sync_status:find("✓")

    -- Get Col_Text constant (handle both function and constant forms)
    local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text

    if is_error and ImGui.PushStyleColor and col_text then
      ImGui.PushStyleColor(ctx, col_text, 0xFF6060FF)
      ImGui.TextWrapped(ctx, state.team_sync_status)
      ImGui.PopStyleColor(ctx, 1)
    elseif is_success and ImGui.PushStyleColor and col_text then
      ImGui.PushStyleColor(ctx, col_text, 0x60FF60FF)
      ImGui.TextWrapped(ctx, state.team_sync_status)
      ImGui.PopStyleColor(ctx, 1)
    else
      ImGui.TextWrapped(ctx, state.team_sync_status)
    end
  else
    ImGui.TextDisabled(ctx, "No recent activity")
  end

  if state.team_last_sync > 0 then
    local ago = os.time() - state.team_last_sync
    local ago_str
    if ago < 60 then
      ago_str = ago .. " seconds ago"
    elseif ago < 3600 then
      ago_str = math.floor(ago / 60) .. " minutes ago"
    else
      ago_str = math.floor(ago / 3600) .. " hours ago"
    end
    ImGui.TextDisabled(ctx, "Last sync: " .. ago_str)
  end

  -- Team entries count
  if state.team_entries and #state.team_entries > 0 then
    ImGui.TextDisabled(ctx, "Team library: " .. #state.team_entries .. " items")
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)

  -- Close settings button
  if ImGui.Button(ctx, "Close Settings", -1, 0) then
    state.show_settings = false
  end
end

-- Initialize settings module
function Settings.init(app_ctx, db_instance, cfg, engine, state_table, save_user_config_func)
  App = app_ctx
  DB = db_instance
  Config = cfg
  Engine = engine
  state = state_table
  save_user_config_fn = save_user_config_func
end

return Settings

